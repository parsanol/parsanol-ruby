# frozen_string_literal: true

# Parsanol Transform Mode Options
#
# This module provides three transformation modes for parsing:
#
# 1. RubyTransform - Parse in Rust/Ruby, Transform in Ruby (default, most flexible)
# 2. Serialized - Parse + Transform in Rust, JSON output (requires native extension)
# 3. ZeroCopy - Direct FFI object construction (requires native extension, fastest)
#
# Usage:
#   class MyParser < Parsanol::Parser
#     include Parsanol::RubyTransform  # or Serialized, or ZeroCopy
#     rule(:number) { match('[0-9]').repeat(1).as(:int) }
#     root(:number)
#   end

require 'parsanol/options/ruby_transform'
require 'parsanol/options/serialized'
require 'parsanol/options/zero_copy'
