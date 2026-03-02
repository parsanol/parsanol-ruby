# frozen_string_literal: true

# IndentAtom - Custom atom for indentation-sensitive matching
#
# This example demonstrates how to create a custom atom that matches
# lines with a specific indentation level. This is useful for parsing
# Python-like languages where indentation matters.
#
# Usage:
#   class PythonParser < Parsanol::Parser
#     rule(:indented_block) { IndentAtom.new(4) >> statement }
#   end

require 'parsanol'

class IndentAtom < Parsanol::Atoms::Custom
  # Create a new indentation matcher
  #
  # @param expected_indent [Integer] Number of spaces expected at start of line
  def initialize(expected_indent)
    @expected_indent = expected_indent
    super()
  end

  # Required: Implement the matching logic
  def try_match(source, context, consume_all)
    # Save position for potential backtrack
    start_pos = source.bytepos

    # Count leading spaces at current position
    indent = 0
    while source.bytepos < source.chars_left + start_pos
      # Peek at the next character without consuming it
      break unless source.matches?(/ /)

      # Consume one space
      char = source.consume(1)
      break unless char == ' '
      indent += 1
    end

    if indent == @expected_indent
      # Success - return the matched indentation as a slice
      # Use source.slice to create a proper Slice object
      [true, source.slice(start_pos, ' ' * indent)]
    else
      # Failure - restore position for backtracking
      source.bytepos = start_pos
      [false, nil]
    end
  end

  # Override to_s_inner for better error messages
  def to_s_inner(prec = nil)
    "indent(#{@expected_indent})"
  end
end

# Example usage
if __FILE__ == $0
  class IndentedParser < Parsanol::Parser
    rule(:line) { indent >> content }
    rule(:indent) { IndentAtom.new(2) }
    rule(:content) { match['a-z'].repeat(1) }
    root(:line)
  end

  parser = IndentedParser.new

  # This should parse - exactly 2 spaces of indentation
  puts parser.parse("  hello").inspect

  # This will fail - wrong indentation
  begin
    puts parser.parse("    hello").inspect
  rescue Parsanol::ParseFailed => e
    puts "Failed as expected: #{e.message}"
  end
end
