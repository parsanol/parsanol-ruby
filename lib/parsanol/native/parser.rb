# frozen_string_literal: true

require 'digest'

module Parsanol
  module Native
    # Core parsing functionality using Rust native extension
    module Parser
      GRAMMAR_HASH_CACHE = Hash.new
      GRAMMAR_CACHE = Hash.new

      class << self
        @cached_available = nil

        def available?
          return @cached_available unless @cached_available.nil?

          @cached_available = begin
            require 'parsanol/parsanol_native'
            Parsanol::Native.is_available
          rescue LoadError
            false
          end
        end

        # Parse input with a Ruby grammar, returning clean AST.
        #
        # @param grammar [Parsanol::Atoms::Base] Ruby grammar or JSON string
        # @param input [String] Input string to parse
        def parse(grammar, input)
          raise LoadError, "Native parser not available. Run `rake compile` to build." unless available?

          grammar_json = grammar.is_a?(String) ? grammar : serialize_grammar(grammar)
          Parsanol::Native.parse(grammar_json, input)
        end

        # Serialize a Ruby grammar to JSON (cached).
        def serialize_grammar(root_atom)
          root_atom = root_atom.root if root_atom.is_a?(::Parsanol::Parser)
          obj_id = root_atom.object_id
          cache_key = GRAMMAR_HASH_CACHE[obj_id] ||= grammar_structure_hash(root_atom)
          GRAMMAR_CACHE[cache_key] ||= GrammarSerializer.serialize(root_atom)
        end

        def clear_cache
          GRAMMAR_HASH_CACHE.clear
          GRAMMAR_CACHE.clear
        end

        def cache_stats
          {
            hash_cache_size: GRAMMAR_HASH_CACHE.size,
            grammar_cache_size: GRAMMAR_CACHE.size
          }
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
