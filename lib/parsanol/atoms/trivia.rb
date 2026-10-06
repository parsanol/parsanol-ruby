# frozen_string_literal: true

module Parsanol
  module Atoms
    # The injected skip wrapper: Ignored semantics (matched bytes
    # contribute nothing to values or spans) plus diagnostics
    # transparency — failures inside trivia are marked and never
    # surface in rendered trees or deepest-failure positions.
    class Trivia < Ignored
      def apply(source, context, consume_all)
        context.with_trivia do
          super
        end
      end

      def to_s_inner(prec)
        "trivia(#{@wrapped_atom.to_s(prec)})"
      end
    end

    # parsanol-ruby#152: the skip-declared capture wrapper. Whitespace
    # trivia stays Ignored; comment-shaped units (the grammar names the
    # capture rules in the declaration) are recorded into the context
    # channel for attachment to the next successful Named capture.
    # Span discipline is unchanged: the matched bytes still contribute
    # nothing to values or capture spans.
    class TriviaCapture < Trivia
      # +capturers+ maps leading-literal marker -> kind label (the
      # compiler derives markers from each capturer rule's first Str
      # atom, e.g. "//" => :line_comment); units not matching any
      # marker are whitespace-shaped and stay unrecorded.
      attr_reader :capturers

      def initialize(atom, capturers)
        super(atom)
        @capturers = capturers
      end

      def apply(source, context, consume_all)
        context.with_trivia do
          start = source.bytepos
          ok, _value = @wrapped_atom.apply(source, context, consume_all)
          if ok && source.bytepos > start
            record(source, context, start, source.bytepos)
            return ok(nil)
          end
          [ok, _value]
        end
      end

      def to_s_inner(_prec)
        "trivia!(@wrapped_atom.to_s(prec))"
      end

      private

      def record(source, context, start_pos, end_pos)
        return unless @capturers

        text = source.input[start_pos...end_pos]
        # A trivia unit may lead with whitespace before the comment
        # shape; markers test the comment head.
        stripped = text.lstrip
        marker, label = @capturers.find { |m, _label| stripped.start_with?(m) }
        return unless marker

        context.push_captured_trivia(label, stripped.strip)
      end
    end
  end
end
