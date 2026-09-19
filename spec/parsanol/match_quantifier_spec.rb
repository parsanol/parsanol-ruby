# frozen_string_literal: true

require "spec_helper"

# GH-69: Parslet honors quantifiers embedded in match() patterns;
# Parsanol must too.
RSpec.describe "match with embedded quantifiers" do
  include Parsanol
  extend Parsanol

  it "matches greedily like Parslet" do
    expect(match("a+").parse("aaa")).to eq(Parsanol::Slice.new(0, "aaa", nil))
  end

  it "matches a maximal run inside a grammar" do
    grammar = str("<") >> match("[0-9]+").as(:n) >> str(">")
    expect(grammar.parse("<12345>")).to eq(n: Parsanol::Slice.new(1, "12345", nil))
  end

  it "keeps single-character semantics for plain classes" do
    expect(match("[a-z]").parse("q")).to eq(Parsanol::Slice.new(0, "q", nil))
    expect { match("[a-z]").parse("qq") }.to raise_error(Parsanol::ParseFailed)
  end

  it "fails when the quantified class cannot match" do
    expect { match("a+").parse("b") }.to raise_error(Parsanol::ParseFailed)
  end
end
