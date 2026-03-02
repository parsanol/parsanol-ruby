# frozen_string_literal: true

# Named capture - assigns a label to matched content.
# Results appear as { label: value } in the parse tree.
#
# @example Labeling matches
#   str('foo').as(:name)  # returns { name: 'foo' }
#
module Parsanol
  module Atoms
    class Named < Parsanol::Atoms::Base
      # @return [Parsanol::Atoms::Base] wrapped parser
      attr_reader :parslet

      # @return [Symbol] the capture label
      attr_reader :name

      # Creates a new named capture.
      #
      # @param parser [Parsanol::Atoms::Base] parser to wrap
      # @param label [Symbol] name for captures
      def initialize(parser, label)
        super()
        @parslet = parser
        @name = label
      end

      # Applies parser and wraps result in hash.
      #
      # @param source [Parsanol::Source] input
      # @param context [Parsanol::Atoms::Context] context
      # @param consume_all [Boolean] require full consumption
      # @return [Array(Boolean, Object)] result
      def apply(source, context, consume_all)
        success, value = @parslet.apply(source, context, consume_all)
        return [false, value] unless success

        ok(wrap_result(value))
      end

      # Named wrappers skip caching (inner parser handles it).
      #
      # @return [Boolean]
      def cached?
        false
      end

      # String representation.
      #
      # @param prec [Integer] precedence
      # @return [String]
      def to_s_inner(prec)
        "#{@name}:#{@parslet.to_s(prec)}"
      end

      # FIRST set is wrapped parser's FIRST set.
      #
      # @return [Set]
      def compute_first_set
        @parslet.first_set
      end

      private

      # Wraps matched value in labeled hash.
      #
      # @param matched [Object] matched value
      # @return [Hash] labeled result
      def wrap_result(matched)
        { @name => flatten(matched, true) }
      end
    end
  end
end
