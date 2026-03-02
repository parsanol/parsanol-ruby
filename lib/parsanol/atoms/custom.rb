# frozen_string_literal: true

module Parsanol
  module Atoms
    # Base class for creating custom parser atoms.
    #
    # Custom atoms allow extending Parsanol with domain-specific matching logic
    # that cannot be expressed with the built-in combinators.
    #
    # @example Custom atom for matching indentation-sensitive content
    #   class IndentAtom < Parsanol::Atoms::Custom
    #     def initialize(expected_indent)
    #       @expected_indent = expected_indent
    #       super()
    #     end
    #
    #     # Required: Implement try_match
    #     def try_match(source, context, consume_all)
    #       pos = source.pos
    #       indent = count_indent(source)
    #
    #       if indent == @expected_indent
    #         content = read_until_newline(source)
    #         [true, content]
    #       else
    #         source.pos = pos  # Restore position on failure
    #         [false, nil]
    #       end
    #     end
    #
    #     private
    #
    #     def count_indent(source)
    #       # ... implementation ...
    #     end
    #   end
    #
    #   # Usage in parser
    #   class MyParser < Parsanol::Parser
    #     rule(:indented_line) { IndentAtom.new(2) }
    #   end
    #
    class Custom < Base
      # Required: Implement this method to define matching behavior
      #
      # @param source [Parsanol::Source] The input source with position tracking
      # @param context [Parsanol::Atoms::Context] Parse context for memoization
      # @param consume_all [Boolean] If true, must consume entire input
      # @return [Array<Boolean, Object>] Tuple of [success, result]
      #   - success: true if match succeeded, false otherwise
      #   - result: matched value on success, nil on failure
      #
      # @note You MUST restore source.bytepos on failure for proper backtracking
      #
      def try_match(source, context, consume_all)
        raise NotImplementedError,
          "Custom atoms must implement #try_match(source, context, consume_all)"
      end

      # Override of Base#try that delegates to try_match
      # Handles error reporting and result wrapping
      #
      # @api private
      def try(source, context, consume_all)
        success, result = try_match(source, context, consume_all)

        if success
          [true, result]
        else
          # Generate error cause for reporting
          context.err(
            self,
            source,
            "Failed to match custom atom: #{self.class.name}"
          )
        end
      end

      # Optional: Override to provide first set for optimization
      # Returns the set of characters/strings this atom can match at start
      #
      # @return [Set<String>, nil] First set, or nil if not determinable
      def first_set
        nil  # Unknown by default
      end

      # Optional: Override to enable caching for this atom
      # Return false for context-dependent matching (e.g., indentation)
      #
      # @return [Boolean] true if atom can be cached
      def cacheable?
        true
      end

      # Optional: Override to provide custom serialization for native parser
      # Return nil if atom cannot be serialized (must use pure Ruby mode)
      #
      # @return [Hash, nil] JSON-serializable representation
      def to_native_format
        nil  # Not serializable by default
      end

      # Override to_s_inner for debug printing
      # @api private
      def to_s_inner(prec = nil)
        "custom(#{self.class.name})"
      end
    end
  end
end
