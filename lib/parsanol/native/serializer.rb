# frozen_string_literal: true

module Parsanol
  # Grammar serializer for native parser
  # Serializes Parslet atoms to JSON format expected by Rust parser
  #
  class GrammarSerializer
    # Serialize a Parslet grammar (root atom) to JSON string
    #
    # @param root [Parsanol::Atoms::Base] The root atom of the grammar
    # @return [String] JSON representation of the grammar
    def self.serialize(root)
      # Create fresh instance for each serialization
      # (state is specific to each grammar)
      new.serialize(root)
    end

    def initialize
      @atoms = []
      @atom_cache = {} # object_id => atom_id for deduplication
    end

    # Main serialization method
    def serialize(root)
      root_id = serialize_atom(root)

      # Build JSON output directly to avoid intermediate Hash
      # This is faster than creating a Hash and calling to_json
      %({"atoms":#{@atoms.to_json},"root":#{root_id}})
    end

    private

    # Serialize a single atom and return its atom_id
    def serialize_atom(atom)
      # Check cache for deduplication
      cache_key = atom.object_id
      return @atom_cache[cache_key] if @atom_cache.key?(cache_key)

      # Entity atoms are special - they're just lazy references to other atoms
      # Don't create a new atom, just resolve and return the referenced atom_id
      return serialize_entity(atom) if atom.is_a?(Parsanol::Atoms::Entity)

      # Serialize based on atom type first (recursively)
      serialized = case atom
                   when Parsanol::Atoms::Str
                     serialize_str(atom)
                   when Parsanol::Atoms::Re
                     serialize_re(atom)
                   when Parsanol::Atoms::Sequence
                     serialize_sequence(atom)
                   when Parsanol::Atoms::Alternative
                     serialize_alternative(atom)
                   when Parsanol::Atoms::Repetition
                     serialize_repetition(atom)
                   when Parsanol::Atoms::Named
                     serialize_named(atom)
                   when Parsanol::Atoms::Lookahead
                     serialize_lookahead(atom)
                   when Parsanol::Atoms::Capture
                     serialize_capture(atom)
                   when Parsanol::Atoms::Scope
                     serialize_scope(atom)
                   when Parsanol::Atoms::Dynamic
                     serialize_dynamic(atom)
                   else
                     # Fallback for unknown atom types
                     serialize_unknown(atom)
                   end

      # Now reserve an atom_id and cache
      atom_id = @atoms.size
      @atom_cache[cache_key] = atom_id
      @atoms << serialized

      atom_id
    end

    def serialize_str(atom)
      {
        'Str' => {
          'pattern' => atom.str
        }
      }
    end

    def serialize_re(atom)
      # Ruby's Regexp#to_s produces "(?-mix:pattern)" format
      # We need to extract just the pattern for the Rust parser
      pattern = atom.match
      pattern = ::Regexp.last_match(1) if pattern =~ /^\(\?[-mix]*:(.+)\)$/
      {
        'Re' => {
          'pattern' => pattern
        }
      }
    end

    def serialize_sequence(atom)
      atom_ids = atom.parslets.map { |p| serialize_atom(p) }
      {
        'Sequence' => {
          'atoms' => atom_ids
        }
      }
    end

    def serialize_alternative(atom)
      atom_ids = atom.alternatives.map { |p| serialize_atom(p) }
      {
        'Alternative' => {
          'atoms' => atom_ids
        }
      }
    end

    def serialize_repetition(atom)
      {
        'Repetition' => {
          'atom' => serialize_atom(atom.parslet),
          'min' => atom.min,
          'max' => atom.max
        }
      }
    end

    def serialize_named(atom)
      {
        'Named' => {
          'name' => atom.name.to_s,
          'atom' => serialize_atom(atom.parslet)
        }
      }
    end

    def serialize_entity(atom)
      # Entity is a lazy reference - resolve it to the actual parslet
      # Cache FIRST before resolving to handle circular references
      cache_key = atom.object_id

      # Reserve an atom_id and cache it before resolving
      # This prevents infinite recursion when a rule references itself
      atom_id = @atoms.size
      @atom_cache[cache_key] = atom_id

      # Add a placeholder that will be replaced
      @atoms << nil

      parslet = begin
        atom.parslet
      rescue StandardError
        nil
      end

      if parslet
        # Serialize the resolved parslet inline (don't call serialize_atom to avoid double-caching)
        serialized = case parslet
                     when Parsanol::Atoms::Str
                       serialize_str(parslet)
                     when Parsanol::Atoms::Re
                       serialize_re(parslet)
                     when Parsanol::Atoms::Sequence
                       serialize_sequence(parslet)
                     when Parsanol::Atoms::Alternative
                       serialize_alternative(parslet)
                     when Parsanol::Atoms::Repetition
                       serialize_repetition(parslet)
                     when Parsanol::Atoms::Named
                       serialize_named(parslet)
                     when Parsanol::Atoms::Entity
                       # Nested entity - just reference it via serialize_atom
                       { 'Entity' => { 'atom' => serialize_atom(parslet) } }
                     when Parsanol::Atoms::Lookahead
                       serialize_lookahead(parslet)
                     else
                       serialize_unknown(parslet)
                     end

        # Replace the placeholder with the serialized atom
        @atoms[atom_id] = serialized
      else
        # If the entity's block returns nil, create a placeholder that will fail
        @atoms[atom_id] = {
          'Str' => {
            'pattern' => "\x00__UNIMPLEMENTED_ENTITY_#{atom.name}__"
          }
        }
      end
      atom_id
    end

    def serialize_lookahead(atom)
      {
        'Lookahead' => {
          'atom' => serialize_atom(atom.bound_parslet),
          'positive' => atom.positive
        }
      }
    end

    def serialize_capture(atom)
      # Capture stores matched text for later use by Dynamic.
      # Native parser doesn't support cross-atom captures,
      # so we serialize the inner atom but the capture is a no-op.
      # Grammars using capture+dynamic will need Ruby fallback.
      serialize_atom(atom.parslet)
    end

    def serialize_scope(atom)
      # Scope creates a new capture scope.
      # Native parser doesn't have scoped captures,
      # so we just serialize the inner atom from the block.
      inner = begin
        atom.block.call
      rescue StandardError
        nil
      end
      if inner
        serialize_atom(inner)
      else
        serialize_unknown(atom)
      end
    end

    def serialize_dynamic(_atom)
      # Dynamic evaluates a Ruby block at parse time.
      # This cannot be serialized to JSON - the grammar
      # requires Ruby fallback for this portion.
      # We create a marker that will fail at parse time
      # with a clear error message.
      {
        'Str' => {
          'pattern' => "\x00__DYNAMIC_NOT_SUPPORTED__"
        }
      }
    end

    def serialize_unknown(_atom)
      # For unsupported atom types, create a placeholder
      # This will cause a parse error at runtime
      {
        'Str' => {
          'pattern' => '' # Empty pattern that will never match
        }
      }
    end
  end
end
