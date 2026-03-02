# frozen_string_literal: true

# Ordered choice - tries alternatives left-to-right, returning first success.
# Fails only if all alternatives fail.
#
# @example Simple choice
#   str('a') | str('b')  # matches 'a' or 'b'
#
# This is PEG ordered choice - no backtracking to later alternatives.
#
class Parsanol::Atoms::Alternative < Parsanol::Atoms::Base
  # @return [Array<Parsanol::Atoms::Base>] alternative parsers
  attr_reader :alternatives

  # Creates a new choice.
  #
  # @param options [Array<Parsanol::Atoms::Base>] alternatives
  def initialize(*options)
    super()
    @alternatives = options
    @choice_error = "Expected one of #{options.inspect}".freeze
  end

  # Adds an alternative with flattening.
  #
  # @param parser [Parsanol::Atoms::Base] new alternative
  # @return [Parsanol::Atoms::Alternative] flattened choice
  def |(parser)
    expanded = if parser.is_a?(Parsanol::Atoms::Alternative)
      @alternatives + parser.alternatives
    else
      @alternatives + [parser]
    end
    self.class.new(*expanded)
  end

  # Tries each alternative in order.
  #
  # @param source [Parsanol::Source] input
  # @param context [Parsanol::Atoms::Context] context
  # @param consume_all [Boolean] require full consumption
  # @return [Array(Boolean, Object)] result
  def try(source, context, consume_all)
    options = @alternatives
    count = options.size

    # Optimized paths for common sizes
    case count
    when 2
      try_two(options[0], options[1], source, context, consume_all)
    when 3
      try_three(options[0], options[1], options[2], source, context, consume_all)
    else
      try_many(options, source, context, consume_all)
    end
  end

  precedence CHOICE

  # String representation.
  #
  # @param prec [Integer] precedence
  # @return [String]
  def to_s_inner(prec)
    @alternatives.map { |a| a.to_s(prec) }.join(' / ')
  end

  # FIRST set is union of all alternatives' FIRST sets.
  #
  # @return [Set]
  def compute_first_set
    return Set.new if @alternatives.empty?
    @alternatives.map(&:first_set).reduce(&:union)
  end

  private

  # Two-alternative fast path
  def try_two(a1, a2, source, context, consume_all)
    success, value1 = a1.apply(source, context, consume_all)
    return [success, value1] if success

    success, value2 = a2.apply(source, context, consume_all)
    return [success, value2] if success

    context.err(self, source, @choice_error, [value1, value2])
  end

  # Three-alternative fast path
  def try_three(a1, a2, a3, source, context, consume_all)
    success, value1 = a1.apply(source, context, consume_all)
    return [success, value1] if success

    success, value2 = a2.apply(source, context, consume_all)
    return [success, value2] if success

    success, value3 = a3.apply(source, context, consume_all)
    return [success, value3] if success

    context.err(self, source, @choice_error, [value1, value2, value3])
  end

  # General case for N alternatives
  def try_many(options, source, context, consume_all)
    errors = nil

    options.each do |alt|
      success, value = alt.apply(source, context, consume_all)
      return [success, value] if success

      errors ||= []
      errors << value
    end

    context.err(self, source, @choice_error, errors)
  end
end
