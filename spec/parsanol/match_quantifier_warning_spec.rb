# frozen_string_literal: true

require "spec_helper"
require "parsanol"

# Parsanol.match is the DSL atom constructor, not Regexp#match.
# rubocop:disable Performance/RedundantMatch

RSpec.describe "Parsanol.match quantifier warnings" do
  def with_captured_warnings
    prior = $stderr
    require "stringio"
    $stderr = StringIO.new
    result = yield
    [result, $stderr.string]
  ensure
    $stderr = prior
  end

  it "matches exactly one character regardless of the quantifier (Parslet parity)" do
    atom = Parsanol.match("[0-9]+")
    expect(atom).to be_a(Parsanol::Atoms::Re)

    source = Parsanol::Source.new("123")
    result, _end_pos = atom.parse(source, prefix: true)
    expect(result.to_s).to eq("1")
  end

  it "warns once for a quantified pattern" do
    _, warnings = with_captured_warnings do
      Parsanol.match("[pqr]+")
      2.times { Parsanol.match("[pqr]+") }
    end

    messages = warnings.lines.count { |l| l.include?("matches exactly one character") }
    expect(messages).to eq(1)
    expect(warnings).to include("match(\"[pqr]+\")")
    expect(warnings).to include("repeat(1)")
  end

  it "does not warn for quantifier-free patterns or classes containing metacharacters" do
    _, warnings = with_captured_warnings do
      Parsanol.match("[A-Z]")
      Parsanol.match("[0-9+-]") # + inside a class is literal
      Parsanol.match("\\d")
      Parsanol.match(".")
    end

    expect(warnings).not_to include("matches exactly one character")
  end

  it "warns for brace, lazy, and group quantifiers" do
    _, warnings = with_captured_warnings do
      Parsanol.match("\\d{2,4}")
      Parsanol.match("[a]+?")
      Parsanol.match("(ab)*")
    end

    expect(warnings.scan("matches exactly one character").size).to eq(3)
  end
end
# rubocop:enable Performance/RedundantMatch
