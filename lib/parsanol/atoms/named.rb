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
        trivia_before = context.take_pending_trivia_snapshot
        success, value = @parslet.apply(source, context, consume_all)
        unless success
          context.restore_pending_trivia(trivia_before)
          return [false, value]
        end

        comments = context.take_pending_trivia
        result = wrap_result(value)
        result = attach_comments(result, comments) unless comments.empty?
        ok(result)
      end

      private

      # parsanol-ruby#152: trivia captured ahead of this capture rides
      # with it under `comments:`. The attachment only fires when the
      # grammar declared capture AND trivia actually preceded — key
      # absence everywhere else keeps v1 trees byte-identical.
      def attach_comments(result, comments)
        list = comments.map { |unit| { unit[:kind] => unit[:text] } }
        if result.is_a?(Hash)
          result.merge(comments: list)
        else
          { @name => result, comments: list }
        end
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
