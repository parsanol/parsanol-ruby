# frozen_string_literal: true

# Debug helper for parser development.
# Adds a convenient method to Parsanol::Atoms::Base for debugging parse failures.
#
# @example
#   class MyParser < Parsanol::Parser
#     rule(:foo) { str('foo') }
#     root(:foo)
#   end
#
#   # Instead of writing rescue blocks:
#   MyParser.new.parse_with_debug('invalid')
#   # Prints the error tree automatically and returns nil
#
# Inspired by Parslet (MIT License).
module Parsanol
  module Atoms
    class Base
      # Parses input and automatically displays error information on failure.
      # This is a convenience method for development and debugging.
      # Unlike #parse, this method catches ParseFailed and prints debug info.
      #
      # @param input [String] the input to parse
      # @param options [Hash] options passed to #parse
      # @return [Object] parse result on success, nil on failure
      def parse_with_debug(input, options = {})
        parse(input, options)
      rescue Parsanol::ParseFailed => e
        # Display the error tree for debugging
        puts e.parse_failure_cause.ascii_tree
        nil
      end
    end
  end
end
