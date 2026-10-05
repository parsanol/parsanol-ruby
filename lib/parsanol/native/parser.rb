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
        def parse(grammar, input)
          # Delegate to Parsanol::Native.parse for consistency
          Parsanol::Native.parse(grammar, input)
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
        def grammar_handle(root_atom)
          cache_key = grammar_cache_key(root_atom)
          handle = HANDLE_CACHE[cache_key]
          if handle
            # Refresh recency: reinsertion moves the entry to the end,
            # so churn cannot evict a hot grammar's handle.
            HANDLE_CACHE[cache_key] = HANDLE_CACHE.delete(cache_key)
            return handle
          end

          handle = Native._register_grammar(grammar_json(root_atom))
          HANDLE_CACHE[cache_key] = handle
          trim_caches
          handle
        end

        # Drop a handle whose Rust-side entry no longer exists; the next
        # grammar_handle call re-registers.
        def invalidate_handle(handle)
          HANDLE_CACHE.reject! { |_key, cached| cached == handle }
        end

        def clear_cache
          HANDLE_CACHE.each_value { |handle| Native._release_grammar(handle) }
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
            Native._release_grammar(handle)
          end
          GRAMMAR_CACHE.shift while GRAMMAR_CACHE.size > CACHE_LIMIT
        end

        def grammar_structure_hash(atom)
          Digest::MD5.hexdigest(atom_structure(atom).to_s)
        end

        def atom_structure(atom, visited = {})
          # Cycle detection - return a placeholder if we've seen this atom before
          obj_id = atom.object_id
          if visited[obj_id]
            return [:cycle, atom.class.name]
          end

          visited[obj_id] = true

          case atom
          when ::Parsanol::Atoms::Entity
            # Recursively resolve entity to get actual structure for hash
            atom_structure(atom.parslet, visited)
          when ::Parsanol::Atoms::Str
            [:str, atom.str]
          when ::Parsanol::Atoms::Re
            [:re, atom.match]
          when ::Parsanol::Atoms::Sequence
            [:seq, atom.parslets.map { |p| atom_structure(p, visited) }]
          when ::Parsanol::Atoms::Alternative
            [:alt, atom.alternatives.map { |p| atom_structure(p, visited) }]
          when ::Parsanol::Atoms::Repetition
            [:rep, atom.min, atom.max, atom_structure(atom.parslet, visited)]
          when ::Parsanol::Atoms::Named
            [:named, atom.name.to_s, atom_structure(atom.parslet, visited)]
          when ::Parsanol::Atoms::Lookahead
            [:lookahead, atom.positive,
             atom_structure(atom.bound_parslet, visited)]
          else
            [:unknown, atom.class.name]
          end
        end
      end
    end
  end
end
