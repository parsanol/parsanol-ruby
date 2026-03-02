# frozen_string_literal: true

# Captures the result of parsing and stores it for later use.
# Use the capture method to capture a sub-expression result, then
# access it via context.captures[:name] in dynamic blocks.
#
# @example
#   str('a').capture(:first) >> dynamic { |ctx| str(ctx.captures[:first]) }
#
module Parsanol
  module Atoms
    class Capture < Parsanol::Atoms::Base
      attr_reader :inner_atom, :capture_key

      def initialize(atom, name)
        super()
        @inner_atom = atom
        @capture_key = name.to_sym
      end

      def apply(source, context, consume_all)
        success, result = @inner_atom.apply(source, context, consume_all)

        if success
          # Flatten and store the captured value in context
          flattened = flatten(result)
          context.captures[@capture_key] = flattened
        end

        [success, result]
      end

      def to_s_inner(prec)
        "(#{@capture_key.inspect} = #{@inner_atom.to_s(prec)})"
      end
    end
  end
end
