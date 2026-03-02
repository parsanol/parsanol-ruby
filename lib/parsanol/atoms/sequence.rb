# frozen_string_literal: true

# Sequential composition - matches parsers in left-to-right order.
# All parsers must succeed for the sequence to succeed.
#
# @example Sequence of matches
#   str('a') >> str('b')  # matches 'a' then 'b'
#
class Parsanol::Atoms::Sequence < Parsanol::Atoms::Base
  # @return [Array<Parsanol::Atoms::Base>] sequence members
  attr_reader :parslets

  # Creates a new sequence.
  #
  # @param components [Array<Parsanol::Atoms::Base>] parsers to sequence
  def initialize(*components)
    super()
    @parslets = components

    # Pre-built error message
    @fail_msg = "Failed to match sequence (#{inspect})".freeze
  end

  # Error messages hash (for compatibility)
  def error_msgs
    { failed: @fail_msg }
  end

  # Appends a parser to this sequence with flattening.
  #
  # @param parser [Parsanol::Atoms::Base] parser to append
  # @return [Parsanol::Atoms::Sequence] new flattened sequence
  def >>(parser)
    # Flatten nested sequences
    expanded = if parser.is_a?(Parsanol::Atoms::Sequence)
      @parslets + parser.parslets
    else
      @parslets + [parser]
    end

    # Merge adjacent string literals
    merged = merge_adjacent_strings(expanded)

    self.class.new(*merged)
  end

  # Executes all parsers in sequence.
  #
  # @param source [Parsanol::Source] input
  # @param context [Parsanol::Atoms::Context] context
  # @param consume_all [Boolean] require full consumption
  # @return [Array(Boolean, Object)] result
  def try(source, context, consume_all)
    components = @parslets
    count = components.size

    # Dispatch based on size for optimization
    case count
    when 1
      match_single(components[0], source, context, consume_all)
    when 2
      match_pair(components[0], components[1], source, context, consume_all)
    when 3
      match_triple(components[0], components[1], components[2], source, context, consume_all)
    else
      match_general(components, source, context, consume_all)
    end
  end

  precedence SEQUENCE

  # String representation.
  #
  # @param prec [Integer] precedence
  # @return [String]
  def to_s_inner(prec)
    @parslets.map { |p| p.to_s(prec) }.join(' ')
  end

  # FIRST set is first element's FIRST set (with epsilon propagation).
  #
  # @return [Set]
  def compute_first_set
    return Set.new if @parslets.empty?

    result = Set.new
    @parslets.each do |parser|
      first = parser.first_set
      result.merge(first.reject { |x| x == Parsanol::FirstSet::EPSILON })
      break unless first.include?(Parsanol::FirstSet::EPSILON)
    end
    result
  end

  private

  # Single element sequence
  def match_single(parser, source, context, consume_all)
    success, value = parser.apply(source, context, consume_all)
    return context.err(self, source, @fail_msg, [value]) unless success
    ok([:sequence, value])
  end

  # Two-element sequence with buffer pooling
  def match_pair(p1, p2, source, context, consume_all)
    success, v1 = p1.apply(source, context, false)
    return context.err(self, source, @fail_msg, [v1]) unless success

    success, v2 = p2.apply(source, context, consume_all)
    return context.err(self, source, @fail_msg, [v2]) unless success

    buffer = context.acquire_buffer(size: 3)
    buffer.push(:sequence)
    buffer.push(v1)
    buffer.push(v2)
    ok(Parsanol::LazyResult.new(buffer, context))
  end

  # Three-element sequence with buffer pooling
  def match_triple(p1, p2, p3, source, context, consume_all)
    success, v1 = p1.apply(source, context, false)
    return context.err(self, source, @fail_msg, [v1]) unless success

    success, v2 = p2.apply(source, context, false)
    return context.err(self, source, @fail_msg, [v2]) unless success

    success, v3 = p3.apply(source, context, consume_all)
    return context.err(self, source, @fail_msg, [v3]) unless success

    buffer = context.acquire_buffer(size: 4)
    buffer.push(:sequence)
    buffer.push(v1)
    buffer.push(v2)
    buffer.push(v3)
    ok(Parsanol::LazyResult.new(buffer, context))
  end

  # General case for N elements
  def match_general(components, source, context, consume_all)
    buffer = context.acquire_buffer(size: components.size + 1)
    buffer.push(:sequence)

    last_idx = components.size - 1
    idx = 0

    while idx <= last_idx
      must_consume = consume_all && (idx == last_idx)
      success, value = components[idx].apply(source, context, must_consume)

      unless success
        context.release_buffer(buffer)
        return context.err(self, source, @fail_msg, [value])
      end

      buffer.push(value)
      idx += 1
    end

    ok(Parsanol::LazyResult.new(buffer, context))
  end

  # Merges adjacent string atoms using Rope for efficiency
  def merge_adjacent_strings(components)
    result = []
    idx = 0

    while idx < components.size
      current = components[idx]

      if current.is_a?(Parsanol::Atoms::Str)
        rope = Parsanol::Rope.new.append(current.str)
        next_idx = idx + 1

        while next_idx < components.size && components[next_idx].is_a?(Parsanol::Atoms::Str)
          rope.append(components[next_idx].str)
          next_idx += 1
        end

        result << (next_idx > idx + 1 ? Parsanol::Atoms::Str.new(rope.to_s) : current)
        idx = next_idx
      else
        result << current
        idx += 1
      end
    end

    result
  end
end
