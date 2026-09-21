# frozen_string_literal: true

module Parsanol
  # Explains the first difference between two parse trees.
  #
  # Built for engine-parity debugging (parsanol-ruby#83): when
  # `tree_ruby != tree_native`, `TreeDiff.why` pinpoints the first
  # divergent node instead of leaving you to eyeball two inspect
  # dumps.
  #
  # @example
  #   Parsanol::TreeDiff.why(ruby_tree, native_tree)
  #   # => { path: "paragraph.lines",
  #   #      why: "kind mismatch: Array vs Hash",
  #   #      ruby: "Array(1)",
  #   #      native: "Hash{text, line_break}" }
  #
  # Returns nil when the trees are equal.
  module TreeDiff
    module_function

    def why(left, right, max_depth: 200)
      step(left, right, [], 0, max_depth)
    end

    def step(left, right, path, depth, max_depth)
      if depth > max_depth
        return { path: format_path(path), why: "depth limit exceeded", ruby: kind(left),
                 native: kind(right) }
      end
      containers = (left.is_a?(Hash) && right.is_a?(Hash)) ||
        (left.is_a?(Array) && right.is_a?(Array))
      # Containers always descend: Hash#== would short-circuit equal via
      # Slice's content-only ==, hiding offset drift.
      return nil if !containers && equal_values?(left, right)

      if left.is_a?(Hash) && right.is_a?(Hash)
        only_left = left.keys - right.keys
        only_right = right.keys - left.keys
        if only_left.any? || only_right.any?
          return { path: format_path(path),
                   why: "key mismatch: ruby-only #{only_left.inspect}, " \
                        "native-only #{only_right.inspect}",
                   ruby: kind(left), native: kind(right) }
        end
        left.each do |key, value|
          if right.key?(key)
            found = step(value, right[key], path + [key], depth + 1, max_depth)
            return found if found
          end
        end
        nil
      elsif left.is_a?(Array) && right.is_a?(Array)
        if left.length != right.length
          return { path: format_path(path),
                   why: "size mismatch: ruby #{left.length} vs native #{right.length}",
                   ruby: "Array(#{left.length})", native: "Array(#{right.length})" }
        end
        left.each_with_index do |value, index|
          found = step(value, right[index], path + ["[#{index}]"], depth + 1, max_depth)
          return found if found
        end
        nil
      elsif left.is_a?(::Parsanol::Slice) && right.is_a?(::Parsanol::Slice)
        if left.content == right.content
          { path: format_path(path),
            why: "offset drift: #{left.offset} vs #{right.offset}",
            ruby: kind(left), native: kind(right) }
        else
          { path: format_path(path),
            why: "content mismatch: #{left.content.inspect} vs #{right.content.inspect}",
            ruby: kind(left), native: kind(right) }
        end
      else
        { path: format_path(path), why: "kind mismatch: #{kind(left)} vs #{kind(right)}",
          ruby: kind(left), native: kind(right) }
      end
    end

    # Equality for parity purposes: Slices must match on content AND
    # offset (position drift is a real divergence), and a Slice never
    # equals a plain String here even though Slice#== would allow it —
    # engines that disagree on type disagree on the tree.
    def equal_values?(left, right)
      left_is_slice = left.is_a?(::Parsanol::Slice)
      right_is_slice = right.is_a?(::Parsanol::Slice)
      if left_is_slice || right_is_slice
        left_is_slice && right_is_slice &&
          left.content == right.content && left.offset == right.offset
      else
        left == right
      end
    end

    def kind(item)
      case item
      when ::Parsanol::Slice then "Slice(#{item.content.inspect}@#{item.offset})"
      when Hash then "Hash{#{item.keys.join(', ')}}"
      when Array then "Array(#{item.length})"
      when String then "String(#{item.inspect})"
      when nil then "nil"
      else item.class.name
      end
    end

    def format_path(path)
      path.each_with_index.inject(+"") do |acc, (part, i)|
        if i.zero? || part.to_s.start_with?("[")
          acc << part.to_s
        else
          acc << "." << part.to_s
        end
      end
    end
  end
end
