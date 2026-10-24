# frozen_string_literal: true

module Parsanol
  module PARG
    # Parsed PARG document: grammar rules plus the binding sections.
    class Document
      Binding = Struct.new(:capture, :path, :type, :card, :preprocess)
      # `capture` = phase 1 (grammar layer): asserts the raw capture tree,
      # no bindings section needed. `example` = phase 2 (bindings layer):
      # asserts the bound, preprocessed attribute hash.
      # `capture` = phase 1 (grammar layer): asserts the raw capture tree,
      # no bindings section needed. `example` = phase 2 (bindings layer):
      # asserts the bound, preprocessed attribute hash.
      TEST_KINDS = %i[accept reject example capture shape].freeze
      # Test kinds whose expectations are `{ key: value }` pairs.
      PAIR_KINDS = %w[example capture].freeze

      Test = Struct.new(:entry, :kind, :input, :expect)

      attr_accessor :grammar_name, :version, :source, :uses, :skip_declaration, :skip_source,
                    :atomic_rules, :skip_capture_key, :brace_rules
      # R2 declared resync: rule name -> skip pattern (the span matched
      # at a recovery point is consumed as annotated error text).
      attr_reader :resyncs
      attr_reader :rules, :bindings, :preprocess, :entries, :docs, :tests, :render, :derive,
                  :declaration_order,
                  :customs, :states
      # Entries authored in this file (pre-import); nil-entry tests resolve
      # against these first.
      attr_accessor :own_entries
      # Rule names the grammar itself wrote, snapshotted before the
      # compiler injects core rules — lints must not mistake an injected
      # prelude rule for an authored shadow.
      attr_accessor :authored_rules

      def initialize
        @grammar_name = nil
        @version = "0.0.0"
        @source = nil
        @rules = {}
        @render = {}
        @derive = {}
        @bindings = {}
        @preprocess = {}
        @entries = {}
        @declaration_order = []
        @docs = {}
        @tests = []
        @uses = []
        @own_entries = nil
        @customs = {}
        @states = {}
        # Rules declared `atomic <name> = ...`: skip-trivia injection is
        # suppressed inside their bodies (token-shaped rules match
        # contiguously).
        @atomic_rules = []
        @brace_rules = []
        @authored_rules = nil
        # R2 declared resync: rule -> skip pattern. Recovery consumes
        # each pattern match at a failure point as annotated error text
        # and resumes the iteration after it.
        @resyncs = {}
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
