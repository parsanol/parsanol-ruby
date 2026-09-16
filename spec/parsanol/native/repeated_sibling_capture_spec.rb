# frozen_string_literal: true

require "spec_helper"

class RepeatedSiblingCaptureParser < Parsanol::Parslet::Parser
  root(:chain)

  rule(:ident) { match("[A-Z]").as(:first) }
  rule(:leg) { (str("->").as(:arrow) >> match("[A-Z]").as(:product)).repeat(1) }
  rule(:chain) { ident >> leg }
end

RSpec.describe "bare repeated sibling captures", :native do
  let(:parser) { RepeatedSiblingCaptureParser.new }
  let(:input) { "A->B->C" }
  let(:expected) do
    [
      { first: Parsanol::Slice.new(0, "A", input) },
      { arrow: Parsanol::Slice.new(1, "->", input), product: Parsanol::Slice.new(3, "B", input) },
      { arrow: Parsanol::Slice.new(4, "->", input), product: Parsanol::Slice.new(6, "C", input) },
    ]
  end

  it "preserves every repeated sibling capture in Ruby mode" do
    expect(parser.parse(input, mode: :ruby)).to eq(expected)
  end

  it "preserves every repeated sibling capture in native mode" do
    expect(parser.parse(input, mode: :native)).to eq(expected)
  end
end
