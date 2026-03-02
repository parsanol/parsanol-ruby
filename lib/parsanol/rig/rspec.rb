# frozen_string_literal: true

# RSpec matcher for parsing expectations. Provides a fluent DSL for
# specifying parsing behavior in tests.
#
# @example Basic usage
#   expect(parser).to parse("input")
#
# @example With expected output
#   expect(parser).to parse("123").as(123)
#
# @example With block validation
#   expect(parser).to parse("input").as { |result| result.size > 0 }
#
# Inspired by RSpec matcher patterns and Parslet's testing utilities.
#
RSpec::Matchers.define(:parse) do |input_text, options|
  expected_output = nil
  validator_block = nil
  actual_result = nil
  error_trace = nil

  match do |parser_instance|
    begin
      actual_result = parser_instance.parse(input_text)
      if validator_block
        validator_block.call(actual_result)
      else
        expected_output.nil? || expected_output == actual_result
      end
    rescue Parsanol::ParseFailed => e
      if options && options[:trace]
        error_trace = e.parse_failure_cause.ascii_tree
      end
      false
    end
  end

  failure_message do |parser_instance|
    if validator_block
      "expected output of parsing #{input_text.inspect} with " \
      "#{parser_instance.inspect} to meet block conditions, but it didn't"
    else
      msg = if expected_output
        "expected output of parsing #{input_text.inspect} with " \
        "#{parser_instance.inspect} to equal #{expected_output.inspect}, " \
        "but was #{actual_result.inspect}"
      else
        "expected #{parser_instance.inspect} to be able to parse " \
        "#{input_text.inspect}"
      end
      msg += "\n#{error_trace}" if error_trace
      msg
    end
  end

  failure_message_when_negated do |parser_instance|
    if validator_block
      "expected output of parsing #{input_text.inspect} with " \
      "#{parser_instance.inspect} not to meet block conditions, but it did"
    else
      if expected_output
        "expected output of parsing #{input_text.inspect} with " \
        "#{parser_instance.inspect} not to equal #{expected_output.inspect}"
      else
        "expected #{parser_instance.inspect} to not parse " \
        "#{input_text.inspect}, but it did"
      end
    end
  end

  # Chain method for specifying expected output or validation block
  chain :as do |expected = nil, &block|
    expected_output = expected
    validator_block = block
  end
end
