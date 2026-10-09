# frozen_string_literal: true

module Parsanol
  module Atoms
    # Inspects the text behind the current position and consumes
    # nothing, yielding nil.
    #
    # Two forms (rs#137/#163):
    # - Literal: the previous +count+ bytes must equal +pattern+
    #   (the precedes?/does_not_precede? fixed-window guard).
    # - Regex: +source+ is searched in the preceding text and must
    #   end at the position — the CommonMark flanking form, which is
    #   class-based, multibyte and variable-length.
    class Lookbehind < Base
      attr_reader :count, :pattern, :regex_source, :positive

      def initialize(count, pattern, positive: true)
        super()
        @count = count
        @pattern = pattern
        @regex_source = nil
        @compiled = nil
        @positive = positive
      end

      # Class-based flanking guard: +source+ must match the text
      # ending at the position.
      def self.regex(source, positive: true)
        atom = new(0, "", positive: positive)
        atom.instance_variable_set(:@regex_source, source)
        atom
      end

      def regex?
        !@regex_source.nil?
      end

      def try(source, context, _consume_all)
        start = source.bytepos
        if regex?
          @compiled ||= Regexp.new("(?:#{@regex_source})\\z")
          matched = @compiled.match?(source.input.byteslice(0, start))
        else
          behind =
            if start >= @count
              source.input.byteslice(start - @count, @count)
            end
          matched = !behind.nil? && behind == @pattern.b
        end
        return ok(nil) if matched == @positive

        message = regex? ? "text behind does not match /#{@regex_source}/" : "text behind is not #{@pattern.inspect}"
        context.err_at(self, source, message, start)
      end

      def to_s_inner(_prec)
        if regex?
          "lookbehind(/#{@regex_source}/, #{@positive ? '+' : '-'})"
        else
          "lookbehind(#{@count}, #{@pattern.inspect}, #{@positive ? '+' : '-'})"
        end
      end
    end
  end
end
