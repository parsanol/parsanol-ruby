# frozen_string_literal: true

module Parsanol
  module PG
    # Parsed PG document: grammar rules plus the binding sections.
    class Document
      Binding = Struct.new(:capture, :path, :type, :card, :preprocess)
      TEST_KINDS = %i[accept reject example].freeze

      Test = Struct.new(:entry, :kind, :input, :expect)

      attr_accessor :grammar_name, :version, :source
      attr_reader :rules, :bindings, :preprocess, :entries, :docs, :tests

      def initialize
        @grammar_name = nil
        @version = "0.0.0"
        @source = nil
        @rules = {}
        @bindings = {}
        @preprocess = {}
        @entries = {}
        @docs = {}
        @tests = []
      end

      def validate!
        entries.each do |name, rule|
          next if rules.key?(rule)

          raise ParseError,
                "entry #{name.inspect} references unknown rule #{rule.inspect}"
        end
        bindings.each_key do |rule|
          next if rules.key?(rule)

          raise ParseError,
                "bindings reference unknown rule #{rule.inspect}"
        end
        known_steps = preprocess.keys
        bindings.each_value do |list|
          list.each do |binding|
            next if binding.preprocess.nil? || known_steps.include?(binding.preprocess)

            raise ParseError,
                  "binding #{binding.capture.inspect} references unknown " \
                  "preprocess step #{binding.preprocess.inspect}"
          end
        end
        tests.each do |test|
          unless TEST_KINDS.include?(test.kind)
            raise ParseError, "unknown test kind #{test.kind.inspect}"
          end
          next if test.entry.nil? || entries.key?(test.entry)

          raise ParseError,
                "test references unknown entry #{test.entry.inspect}"
        end
      end
    end
  end
end
