# frozen_string_literal: true

require "spec_helper"
require "parsanol"
require "parsanol/native"

RSpec.describe "Parsanol::Native Ractor safety", if: RUBY_ENGINE == "ruby" && defined?(Ractor) do
  let(:grammar) do
    Class.new(Parsanol::Parser) do
      rule(:line) { str("x") >> match("[0-9]").repeat(1) >> str("\n") }
      rule(:doc) { line.repeat(1) }
      root(:doc)
    end.new
  end

  let(:input) { "x123\n" * 500 }

  it "parses from a non-main Ractor" do
    handle = Parsanol::Native::Parser.grammar_handle(grammar)
    ractor = Ractor.new(handle, input) do |h, inp|
      Parsanol::Native._parse_handle(h, inp).class.name
    end

    expect(ractor.take).to eq("Parsanol::Slice")
  end

  it "parses correctly across parallel Ractors" do
    handle = Parsanol::Native::Parser.grammar_handle(grammar)

    reference = Parsanol::Native._parse_handle(handle, input).to_s

    results = Array.new(4) do
      ractor = Ractor.new(handle, input) do |h, inp|
        Parsanol::Native._parse_handle(h, inp).to_s
      end
      ractor.take
    end

    expect(results).to all(eq(reference))
  end
end
