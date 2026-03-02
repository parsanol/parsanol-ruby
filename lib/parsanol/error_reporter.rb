# frozen_string_literal: true

# A namespace for all error reporters.
#
# Error reporters collect and format parse errors. The parsing engine
# calls reporter methods as it attempts to match atoms, building up
# an error structure that can be presented to the user.
#
# @example Using a specific error reporter
#   parser = MyParser.new
#   parser.parse(input, reporter: Parsanol::ErrorReporter::Deepest.new)
#
# @example Creating a custom error reporter
#   class MyReporter < Parsanol::ErrorReporter::Base
#     def initialize
#       @errors = []
#     end
#
#     def err(atom, source, message, children = nil)
#       @errors << { position: source.pos, message: message }
#       @errors.last
#     end
#
#     def err_at(atom, source, message, pos, children = nil)
#       @errors << { position: pos, message: message }
#       @errors.last
#     end
#   end
#
module Parsanol::ErrorReporter
  # Base class for error reporters.
  #
  # Error reporters collect and format parse errors. The parsing engine
  # calls reporter methods as it attempts to match atoms, building up
  # an error structure that can be presented to the user.
  #
  # Subclasses must implement {#err} and {#err_at} methods.
  #
  class Base
    # Report an error at the current parse position.
    #
    # @param atom [Parsanol::Atoms::Base] The atom that failed to match
    # @param source [Parsanol::Source] The input source
    # @param message [String, Array<String>] Error message(s)
    # @param children [Array<Cause>, nil] Child errors from deeper levels
    # @return [Object] An error cause object (implementation-specific)
    #
    # @abstract Subclasses must implement this method
    #
    def err(atom, source, message, children = nil)
      raise NotImplementedError,
        "Error reporters must implement #err(atom, source, message, children)"
    end

    # Report an error at a specific position.
    #
    # @param atom [Parsanol::Atoms::Base] The atom that failed to match
    # @param source [Parsanol::Source] The input source
    # @param message [String, Array<String>] Error message(s)
    # @param pos [Integer] The byte position of the error
    # @param children [Array<Cause>, nil] Child errors from deeper levels
    # @return [Object] An error cause object (implementation-specific)
    #
    # @abstract Subclasses must implement this method
    #
    def err_at(atom, source, message, pos, children = nil)
      raise NotImplementedError,
        "Error reporters must implement #err_at(atom, source, message, pos, children)"
    end

    # Called when an expression successfully parses.
    #
    # This method allows reporters to track successful parses for
    # better error context. The default implementation does nothing.
    #
    # @param source [Parsanol::Source] The input source at success position
    # @return [void]
    #
    def succ(source)
      # Default: no-op
    end

    # Called after parse completes for finalization.
    #
    # Override this method to perform cleanup or generate final reports.
    # The default implementation does nothing.
    #
    # @return [void]
    #
    def finalize
      # Default: no-op
    end
  end
end

require 'parsanol/error_reporter/tree'
require 'parsanol/error_reporter/deepest'
require 'parsanol/error_reporter/contextual'
