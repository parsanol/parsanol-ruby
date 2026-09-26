# frozen_string_literal: true

module Parsanol
  module PG
    # Visitor over the PG IR (OCP): transformations and analyses walk the
    # tree through #visit instead of hand-rolled case statements.
    class Visitor
      CHILDREN = {
        lit: [], class: [], re: [], ref: [],
        seq: :a, alt: :a, rep: %i[a], opt: %i[a], pred: %i[b], cap: %i[b],
        table: []
      }.freeze

      def initialize(node)
        @node = node
      end

      # Yields every node (self first, depth-first).
      def each(&block)
        walk(@node, block)
      end

      def map
        rewrite(@node)
      end

      private

      def walk(node, block)
        return unless node.is_a?(Node)

        block.call(node)
        child_nodes(node).each { |child| walk(child, block) }
      end

      def child_nodes(node)
        case CHILDREN[node.kind]
        when :a then node.a
        when Array then node.a.map { |sym| node.public_send(sym) }
        else []
        end
      end

      # Rebuilds the tree: the block returns a replacement node or nil to
      # keep the original; children are rewritten first (bottom-up).
      def rewrite(node)
        return node unless node.is_a?(Node)

        case node.kind
        when :seq, :alt
          node.class.new(node.a.map { |child| rewrite(child) })
        when :rep
          Node.new(node.kind, rewrite(node.a), node.b, node.c)
        when :opt
          Node.new(node.kind, rewrite(node.a))
        when :pred, :cap
          Node.new(node.kind, node.a, rewrite(node.b))
        else
          yield(node) ? node : node
        end
      end
    end
  end
end
