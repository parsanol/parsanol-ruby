# frozen_string_literal: true

# Parsanol Transform Mode Options
#
# This module provides the ZeroCopy transformation mode for maximum performance:
#
# ZeroCopy - Direct FFI object construction (requires native extension, fastest)
#
# Usage:
#   class MyParser < Parsanol::Parser
#     include Parsanol::ZeroCopy
#     rule(:number) { match('[0-9]').repeat(1).as(:int) }
#     root(:number)
#
#     output_types(number: MyNumberClass)
#   end
#
# For standard parsing, use the Parse Modes API instead:
#   parser.parse(input, mode: :native)  # or :ruby, :json

require 'parsanol/options/zero_copy'
