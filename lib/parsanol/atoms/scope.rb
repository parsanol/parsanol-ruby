# frozen_string_literal: true

# Starts a new scope in the parsing process. Please also see the #captures
# method.
#
module Parsanol
  module Atoms
    class Scope < Parsanol::Atoms::Base
      attr_reader :block

      def initialize(block)
        super()

        @block = block
      end

      def cached?
        false
      end

      def apply(source, context, consume_all)
        # Phase 55: Cache @block ivar to reduce lookup overhead
        block = @block
        context.scope do
          parslet = block.call
          return parslet.apply(source, context, consume_all)
        end
      end

      def to_s_inner(prec)
        "scope { #{block.call.to_s(prec)} }"
      end
    end
  end
end
