# frozen_string_literal: true

require "digest"

module Parsanol
  module Native
    # Core parsing functionality using Rust native extension
    module Parser
      # Cap for the grammar-keyed caches. The handle cache pins a
      # Rust-side HandleEntry (parsed Grammar + compiled program) per
      # live entry — without the cap, every grammar ever registered
      # accumulates on both sides of the FFI boundary. 32 mirrors
      # VM::PROGRAM_CACHE_LIMIT; eviction re-registers on demand (the
      # Rust artifact cache short-circuits the re-compile).
      CACHE_LIMIT = 32

      # Identity-keyed memo: root atom object => structure hash. Keyed
      # by the OBJECT, not object_id — a recycled id must never return a
      # dead grammar's hash for a new grammar (through GRAMMAR_CACHE /
      # HANDLE_CACHE that would alias the new grammar to the old
      # grammar's serialized JSON and Rust handle: a silent wrong
      # native parse).
      GRAMMAR_HASH_CACHE = Hash.new.compare_by_identity
      GRAMMAR_CACHE = Hash.new
      # structure-hash => Rust-side grammar handle. Keyed by content so a
      # recycled object_id can never alias a different grammar.
      HANDLE_CACHE = Hash.new

      class << self
        @cached_available = nil

        def available?
          return @cached_available unless @cached_available.nil?

          @ext_loaded = begin
            # Try versioned path first (released gem), then non-versioned (local dev)
            ruby_version = RUBY_VERSION.split(".").take(2).join(".")
            begin
              require "parsanol/#{ruby_version}/parsanol_native"
            rescue LoadError
              require "parsanol/parsanol_native"
            end
            Parsanol::Native.is_available
          rescue LoadError
            false
          end
          @cached_available = @ext_loaded || Ffi.available?
        end

        # True when the MRI C-API extension is loaded; false when the
        # engine runs through the ffi-gem cdylib tier instead.
        def extension_loaded?
          @ext_loaded ? true : false
        end

        # Parse input with a Ruby grammar, returning clean AST.
        #
        # @param grammar [Parsanol::Atoms::Base] Ruby grammar or JSON string
        # @param input [String] Input string to parse
        def parse(grammar, input, **)
          # Delegate to Parsanol::Native.parse for consistency
          Parsanol::Native.parse(grammar, input, **)
        end

        # Parse input with a Ruby grammar, returning the parslet-shaped
        # AST as a flat event stream [[events], [strings]] — one FFI
        # return, no per-node Ruby objects. Replay with EventPlayer or
        # consume the opcodes directly.
        #
        # @param grammar [Parsanol::Atoms::Base] Ruby grammar definition
        # @param input [String] Input string to parse
        # @return [Array<Array<Integer>, Array<String>>]
        def parse_events(grammar, input)
          handle = grammar_handle(grammar)
          blob, strings = Native._parse_handle_events(handle, input)
          [blob.unpack("q*"), strings]
        end

        # Serialize a Ruby grammar to JSON (cached).
        def serialize_grammar(root_atom)
          grammar_json(root_atom)
        end

        # Resolve a Rust-side handle for the grammar, registering it once.
        # Per-call cost is the memoized structure-hash lookup plus one Hash
        # access — no JSON marshal, no re-hash inside Rust.
        def grammar_handle(root_atom, compatibility: :strict)
          root_atom = root_atom.root if root_atom.is_a?(::Parsanol::Parser)
          legacy = compatibility == :parslet
          # Legacy decisions depend on the exact shared-node graph. The
          # strict structure hash deliberately omits repeated-node targets.
          # Retaining the root in this bounded key also prevents id recycling.
          cache_key = legacy ? [:parslet, root_atom] : grammar_cache_key(root_atom)
          handle = HANDLE_CACHE[cache_key]
          if handle
            # Refresh recency: reinsertion moves the entry to the end,
            # so churn cannot evict a hot grammar's handle.
            HANDLE_CACHE[cache_key] = HANDLE_CACHE.delete(cache_key)
            return handle
          end

          json = legacy ? GrammarSerializer.serialize(root_atom, preserve_identity: true) : grammar_json(root_atom)
          handle = Native._register_grammar(json)
          HANDLE_CACHE[cache_key] = handle
          trim_caches
          handle
        end

        # The handle for the per-reference layout, the one Parslet
        # compatibility used before it serialized each atom once. A shared
        # wire atom shares one memo entry, so a reference that replays a
        # successful prefix never re-runs the body; the speculative
        # failures of that first run are dropped with its success, and the
        # deepest position left in the failure is shallower than before.
        # The per-reference layout is kept to recover that position only.
        # nil when both layouts are the same and a second run would only
        # repeat the first.
        def diagnostics_handle(root_atom)
          root_atom = root_atom.root if root_atom.is_a?(::Parsanol::Parser)
          cache_key = [:parslet_diagnostics, root_atom]
          if HANDLE_CACHE.key?(cache_key)
            handle = HANDLE_CACHE.delete(cache_key)
            HANDLE_CACHE[cache_key] = handle
            return handle || nil
          end

          # The shared layout numbers atoms in another order, so the
          # layouts are compared by size: the per-reference layout only
          # ever adds copies.
          json = GrammarSerializer.serialize(root_atom)
          shared = GrammarSerializer.serialize(root_atom, preserve_identity: true)
          same = JSON.parse(json)["atoms"].size == JSON.parse(shared)["atoms"].size
          handle = same ? false : Native._register_grammar(json)
          HANDLE_CACHE[cache_key] = handle
          trim_caches
          handle || nil
        end

        # Drop a handle whose Rust-side entry no longer exists; the next
        # grammar_handle call re-registers.
        def invalidate_handle(handle)
          HANDLE_CACHE.reject! { |_key, cached| cached == handle }
        end

        def clear_cache
          HANDLE_CACHE.each_value { |handle| Native._release_grammar(handle) if handle }
          GRAMMAR_HASH_CACHE.clear
          GRAMMAR_CACHE.clear
          HANDLE_CACHE.clear
        end

        def cache_stats
          {
            hash_cache_size: GRAMMAR_HASH_CACHE.size,
            grammar_cache_size: GRAMMAR_CACHE.size,
            handle_cache_size: HANDLE_CACHE.size,
          }
        end

        # Public (rs#166): the VM program cache shares compiled
        # programs across fresh parser instances keyed on this —
        # the same disambiguator the grammar cache uses.
        def public_structure_hash(atom)
          grammar_structure_hash(atom)
        end

        private

        def grammar_cache_key(root_atom)
          root_atom = root_atom.root if root_atom.is_a?(::Parsanol::Parser)
          cached = GRAMMAR_HASH_CACHE[root_atom]
          return cached if cached

          hash = grammar_structure_hash(root_atom)
          GRAMMAR_HASH_CACHE[root_atom] = hash
          GRAMMAR_HASH_CACHE.shift while GRAMMAR_HASH_CACHE.size > CACHE_LIMIT
          hash
        end

        def grammar_json(root_atom)
          root_atom = root_atom.root if root_atom.is_a?(::Parsanol::Parser)
          cache_key = grammar_cache_key(root_atom)
          json = GRAMMAR_CACHE[cache_key]
          return json if json

          json = GrammarSerializer.serialize(root_atom)
          GRAMMAR_CACHE[cache_key] = json
          json
        end

        # FIFO eviction past the cap; evicted handles are released
        # Rust-side so HandleEntries (Grammar + program) do not
        # accumulate. Re-registration on a later miss is cheap: the
        # Rust artifact cache reloads the compiled program.
        def trim_caches
          while HANDLE_CACHE.size > CACHE_LIMIT
            key, handle = HANDLE_CACHE.first
            HANDLE_CACHE.delete(key)
            GRAMMAR_CACHE.delete(key)
            Native._release_grammar(handle) if handle
          end
          GRAMMAR_CACHE.shift while GRAMMAR_CACHE.size > CACHE_LIMIT
        end

        def grammar_structure_hash(atom)
          Digest::MD5.hexdigest(append_atom_structure(atom))
        end

        def append_atom_structure(atom, visited = {}.compare_by_identity, output = +"")
          if visited[atom]
            # An Entity's self-reference keeps its name in the
            # fingerprint, mirroring the non-visited branch (ruby#404).
            if atom.is_a?(Parsanol::Atoms::Entity)
              return output << "[:entity, " << atom.rule_name.to_s.inspect << ", [:cycle, " << atom.class.name.inspect << "]]"
            end

            return output << "[:cycle, " << atom.class.name.inspect << "]"
          end

          visited[atom] = true
          case atom
          when Parsanol::Atoms::Entity
            # The rule name belongs in the fingerprint (rs#404-class
            # collision): Entity is transparent in the serialized graph's
            # STRUCTURE only when the target is spelled out, but the JSON
            # keeps the Entity node itself — two webs whose Entities point
            # at different rules share a transparent fingerprint while
            # serializing differently, and the serializer cache then
            # serves one grammar's JSON for the other.
            output << "[:entity, " << atom.rule_name.to_s.inspect << ", "
            append_atom_structure(atom.parslet, visited, output) << "]"
          when Parsanol::Atoms::Str
            output << "[:str, " << atom.str.inspect << "]"
          when Parsanol::Atoms::Re
            output << "[:re, " << atom.match.inspect << "]"
          when Parsanol::Atoms::Sequence, Parsanol::Atoms::Alternative
            children = atom.is_a?(Parsanol::Atoms::Sequence) ? atom.parslets : atom.alternatives
            output << (atom.is_a?(Parsanol::Atoms::Sequence) ? "[:seq, [" : "[:alt, [")
            index = 0
            while index < children.length
              output << ", " unless index.zero?
              append_atom_structure(children[index], visited, output)
              index += 1
            end
            output << "]]"
          when Parsanol::Atoms::Repetition
            output << "[:rep, " << atom.min.inspect << ", " << atom.max.inspect << ", "
            append_atom_structure(atom.parslet, visited, output) << "]"
          when Parsanol::Atoms::Named
            output << "[:named, " << atom.name.to_s.inspect << ", "
            append_atom_structure(atom.parslet, visited, output) << "]"
          when Parsanol::Atoms::Lookahead
            output << "[:lookahead, " << atom.positive.inspect << ", "
            append_atom_structure(atom.bound_parslet, visited, output) << "]"
          when Parsanol::Atoms::Constant
            # The inspected constant remains a string inside the fingerprint.
            output << "[:constant, " << atom.value.inspect.inspect << "]"
          when Parsanol::Atoms::Lookbehind
            output << "[:lookbehind, " << atom.count.inspect << ", " << atom.pattern.inspect << ", " << atom.positive.inspect << "]"
          # Capturing trivia must precede its Trivia and Ignored parents.
          when Parsanol::Atoms::TriviaCapture
            output << "[:trivia_capture, " << atom.capturers.to_a.sort.inspect << ", "
            append_atom_structure(atom.wrapped_atom, visited, output) << "]"
          when Parsanol::Atoms::Trivia
            output << "[:trivia, "
            append_atom_structure(atom.wrapped_atom, visited, output) << "]"
          when Parsanol::Atoms::Ignored
            output << "[:ignored, "
            append_atom_structure(atom.wrapped_atom, visited, output) << "]"
          else
            output << "[:unknown, " << atom.class.name.inspect << "]"
          end
        end
      end
    end
  end
end
