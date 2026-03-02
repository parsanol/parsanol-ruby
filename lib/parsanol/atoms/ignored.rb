# frozen_string_literal: true

# Ignores the result of a match, Useful for cases where you want to match
# prefix or suffix without returning any.

#
# @example
#   str('foo')            # will return 'foo',
#   str('foo').ignore     # will return nil
#
# Inspired by Parslet (MIT License).

module Parsanol
  module Atoms
    class Ignored < Parsanol::Atoms::Base
      attr_reader :wrapped_atom

      def initialize(atom)
        super()
        @wrapped_atom = atom
      end

      def apply(source, context, consume_all)
        ok, result = @wrapped_atom.apply(source, context, consume_all)

        return [false, result] unless ok

        # Success - return nil instead of the matched value
        [true, nil]
      end

      def to_s_inner(prec)
        "ignored(#{@wrapped_atom.to_s(prec)})"
      end
    end
  end
end
