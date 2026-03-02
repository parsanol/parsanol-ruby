# frozen_string_literal: true

# Named rule wrapper that provides lazy evaluation and caching for grammar
# rules. Rules are defined as Entity atoms and named, and they can be
# referenced by other rules with automatic cycle detection.
#
# @example
#   class MyParser < Parsanol::Parser
#     rule(:expression) { str('a') >> str('b') }
#     root(:expression)
#   end
#
#   MyParser.new.parse('ab')  # => ["a", "b"]
#
class Parsanol::Atoms::Entity < Parsanol::Atoms::Base
  attr_reader :rule_name, :block_definition

  # Alias for backward compatibility
  alias name rule_name

  def initialize(name, label_or_opts = {}, &body)
    super()
    @rule_name = name
    # Support both old API (label string) and new API (options hash)
    if label_or_opts.is_a?(Hash)
      @options = label_or_opts
    else
      @options = { label: label_or_opts }
    end
    @body = body
    @cached_atom = nil
    # Set label on self for display purposes
    self.label = @options[:label] if @options[:label]
  end

  # Evaluates the rule body, returns cached result.
  def parslet
    return @cached_atom unless @cached_atom.nil?

    @cached_atom = @body.call

    raise_not_implemented if @cached_atom.nil?

    @cached_atom.label = @options[:label] if @options[:label]
    @cached_atom
  end

  def try(source, context, consume_all)
    atom = parslet
    atom.apply(source, context, consume_all)
  end

  # Entities don't need caching since the underlying atom is already cached.
  def cached?
    false
  end

  def to_s_inner(prec)
    rule_name.to_s.upcase
  end

  private

  def raise_not_implemented
    trace_lines = caller.reject { |line| line =~ %r{#{Regexp.escape(__FILE__)}} }
    error_message = "rule '#{@rule_name}' has not been implemented, but already used?"
    exception = NotImplementedError.new(error_message)
    exception.set_backtrace(trace_lines)
    raise exception
  end
end
