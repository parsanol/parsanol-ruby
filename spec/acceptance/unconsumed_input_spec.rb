# frozen_string_literal: true

require "spec_helper"

describe "Unconsumed input:" do
  class RepeatingBlockParser < Parsanol::Parser
    root :expressions
    rule(:expressions) { expression.repeat }
    rule(:expression) { str("(") >> aab >> str(")") }
    rule(:aab) { str("a").repeat(1) >> str("b") }
  end
  describe RepeatingBlockParser do
    let(:parser) { described_class.new }

    it "throws annotated error" do
      catch_failed_parse { parser.parse("(aaac)") }
    end

    it "doesn't error out if prefix is true" do
      expect do
        parser.parse("(aaac)", prefix: true)
      end.not_to raise_error
    end
  end
end
