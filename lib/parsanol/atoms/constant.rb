# frozen_string_literal: true

module Parsanol
  module Atoms
    # Matches empty and yields a constant value (coradoc-markdown
    # Output parity, rs#137 follow-up): the native wire carries the
    # value as wire data, so constant-yielding grammar shapes parse
    # on both engines with identical trees.
    class Constant < Base
      attr_reader :value

      def initialize(value)
        super()
        @value = value
      end

      def try(_source, _context, _consume_all)
        [true, @value]
      end

      def to_s_inner(_prec)
        "constant(#{@value.inspect})"
      end
    end
  end
end
