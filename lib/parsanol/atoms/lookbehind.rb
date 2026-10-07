# frozen_string_literal: true

module Parsanol
  module Atoms
    # Inspects the byte window behind the current position: the
    # previous +count+ bytes must equal +pattern+ (positive) or
    # differ (negative). Consumes nothing, yields nil — the
    # precedes?/does_not_precede? guard shape (coradoc-markdown
    # parity, rs#137 follow-up).
    class Lookbehind < Base
      attr_reader :count, :pattern, :positive

      def initialize(count, pattern, positive: true)
        super()
        @count = count
        @pattern = pattern
        @positive = positive
      end

      def try(source, _context, _consume_all)
        start = source.bytepos
        behind = start >= @count ? source.input.byteslice(start - @count, @count) : nil
        matched = !behind.nil? && behind == @pattern.b
        [matched == @positive, nil]
      end

      def to_s_inner(_prec)
        "lookbehind(#{@count}, #{@pattern.inspect}, #{@positive ? '+' : '-'})"
      end
    end
  end
end
