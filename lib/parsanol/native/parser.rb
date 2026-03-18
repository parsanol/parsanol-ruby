# frozen_string_literal: true

require 'digest'

module Parsanol
  module Native
    # Core parsing functionality using Rust native extension
    module Parser
      # Grammar cache (module-level for proper initialization)
      GRAMMAR_HASH_CACHE = Hash.new  # object_id => hash_key
      GRAMMAR_CACHE = Hash.new       # hash_key => grammar_json

      class << self
        @cached_available = nil

        # Check if native extension is available
        def available?
          return @cached_available unless @cached_available.nil?

          @cached_available = begin
            require 'parsanol/parsanol_native'
            Parsanol::Native.is_available
          rescue LoadError
            false
          end
        end

        # =======================================================================
        # PUBLIC API
        # =======================================================================

        # Parse input and return a clean AST with lazy line/column support
        #
        # @param grammar_json [String] JSON-serialized grammar
        # @param input [String] Input string to parse
        # @return [Hash, Array, Parsanol::Slice] Transformed AST
        def parse(grammar_json, input)
          unless available?
            raise LoadError,
                  "Native parser not available. Run `rake compile` to build."
          end

          Parsanol::Native.parse(grammar_json, input)
        end

        # Serialize a grammar to JSON with caching
        #
        # @param root_atom [Parsanol::Atoms::Base] Root atom of the grammar
        # @return [String] JSON string
        def serialize_grammar(root_atom)
          root_atom = root_atom.root if root_atom.is_a?(::Parsanol::Parser)

          obj_id = root_atom.object_id
          cache_key = GRAMMAR_HASH_CACHE[obj_id] ||= grammar_structure_hash(root_atom)
          GRAMMAR_CACHE[cache_key] ||= GrammarSerializer.serialize(root_atom)
        end

        # Parse with automatic grammar serialization
        #
        # @param root_atom [Parsanol::Atoms::Base] Root atom of the grammar
        # @param input [String] Input string to parse
        # @return [Object] Transformed AST
        def parse_with_grammar(root_atom, input)
          grammar_json = serialize_grammar(root_atom)
          parse(grammar_json, input)
        end

        # Clear grammar caches
        def clear_cache
          GRAMMAR_HASH_CACHE.clear
          GRAMMAR_CACHE.clear
        end

        # Get cache statistics
        def cache_stats
          {
            hash_cache_size: GRAMMAR_HASH_CACHE.size,
            grammar_cache_size: GRAMMAR_CACHE.size
          }
        end

        # =======================================================================
        # LOW-LEVEL API
        # =======================================================================

        # Parse using batch mode (returns flat u64 array)
        def parse_batch(grammar_json, input)
          unless available?
            raise LoadError, "Native parser not available. Run `rake compile` to build."
          end

          Parsanol::Native.parse_batch(grammar_json, input)
        end

        # Parse with streaming builder callback
        def parse_with_builder(grammar_json, input, builder)
          unless available?
            raise LoadError, "Native parser not available. Run `rake compile` to build."
          end

          Parsanol::Native.parse_with_builder(grammar_json, input, builder)
        end

        private

        def grammar_structure_hash(atom)
          Digest::MD5.hexdigest(atom_structure(atom).to_s)
        end

        def atom_structure(atom)
          case atom
          when ::Parsanol::Atoms::Str
            [:str, atom.str]
          when ::Parsanol::Atoms::Re
            [:re, atom.match]
          when ::Parsanol::Atoms::Sequence
            [:seq, atom.parslets.map { |p| atom_structure(p) }]
          when ::Parsanol::Atoms::Alternative
            [:alt, atom.alternatives.map { |p| atom_structure(p) }]
          when ::Parsanol::Atoms::Repetition
            [:rep, atom.min, atom.max, atom_structure(atom.parslet)]
          when ::Parsanol::Atoms::Named
            [:named, atom.name.to_s, atom_structure(atom.parslet)]
          when ::Parsanol::Atoms::Lookahead
            [:lookahead, atom.positive, atom_structure(atom.bound_parslet)]
          when ::Parsanol::Atoms::Entity
            [:entity, atom.name.to_s]
          else
            [:unknown, atom.class.name]
          end
        end
      end
    end
  end
end
