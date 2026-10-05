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
  end
end
