# frozen_string_literal: true

# Compatibility Test Helper
#
# This helper allows running tests against both Parslet and Parsanol::Parslet
# to verify behavioral compatibility.
#
# Usage:
#   PARSANOL_BACKEND=parslet bundle exec rspec spec/parslet_imported/
#   PARSANOL_BACKEND=parsanol bundle exec rspec spec/parslet_imported/
#
# Default is to use Parsanol::Parslet

module ParsletCompatibilityHelper
  def use_original_parslet?
    ENV['PARSANOL_BACKEND'] == 'parslet'
  end

  def parslet_module
    @parslet_module ||= if use_original_parslet?
                          require 'parslet'
                          Parslet
                        else
                          require 'parsanol/parslet'
                          Parsanol::Parslet
                        end
  end

  # Normalize results for comparison
  # Parslet returns Slice objects, Parsanol returns strings/hashes
  def normalize_result(obj)
    case obj
    when defined?(Parslet::Slice) && Parslet::Slice
      obj.to_s
    when Hash
      obj.transform_values { |v| normalize_result(v) }
    when Array
      obj.map { |v| normalize_result(v) }
    else
      obj
    end
  end

  # Parse and normalize result for comparison
  def parslet_parse(parser, input)
    result = parser.parse(input)
    normalize_result(result)
  rescue StandardError => e
    e
  end

  # Check if two results are equivalent
  def results_equivalent?(result1, result2)
    normalize_result(result1) == normalize_result(result2)
  end
end

RSpec.configure do |config|
  config.include ParsletCompatibilityHelper

  config.before(:suite) do
    # Pre-load the appropriate module
    if ENV['PARSANOL_BACKEND'] == 'parslet'
      puts 'Running tests with original Parslet'
      require 'parslet'
    else
      puts 'Running tests with Parsanol::Parslet compatibility layer'
      require 'parsanol/parslet'
    end
  end
end
