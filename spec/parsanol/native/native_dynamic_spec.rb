# frozen_string_literal: true

require "spec_helper"

# GH-85: grammars with dynamic atoms run on the native engine. The
# block receives a restricted context (pos, remaining, captures) and
# returns an atom subtree or a literal String.
RSpec.describe "native dynamic atoms", :native do
  include Parsanol
  extend Parsanol

  before do
    skip "native backend unavailable" unless Parsanol::Native.available?
  end

  it "parses grammars with dynamic atoms natively" do
    parser = Class.new(Parsanol::Parser) do
      rule(:x) do
        str("V:") >>
          dynamic { |ctx| ctx.remaining.start_with?("1") ? match("[0-9]").repeat(1) : str("none") } >>
          str("!")
      end
      root(:x)
    end

    expect(parser.new.native_expressible?).to be(true)
    expect(parser.new.parse("V:123!", mode: :native).to_s).to eq("V:123!")
  end

  it "dispatches on the remaining input" do
    grammar = str("V:") >>
      dynamic { |ctx| ctx.remaining.start_with?("1") ? match("[0-9]").repeat(1) : str("none") } >>
      str("!")

    expect(Parsanol::Native.parse(grammar, "V:123!").to_s).to eq("V:123!")
    expect(Parsanol::Native.parse(grammar, "V:none!").to_s).to eq("V:none!")
  end

  it "exposes captures to the block" do
    grammar = str("T:").capture(:t) >>
      dynamic { |ctx| ctx[:t] ? match("[a-z]").repeat(1) : str("?") }

    expect(Parsanol::Native.parse(grammar, "T:abc").to_s).to eq("T:abc")
  end

  it "accepts a literal String return as a Str match" do
    grammar = str("K:") >> dynamic { |_ctx| "lit" }
    expect(Parsanol::Native.parse(grammar, "K:lit").to_s).to eq("K:lit")
  end

  it "fails the position when the block returns nil" do
    grammar = str("A") >> dynamic { |_ctx| nil } >> str("B")
    expect { Parsanol::Native.parse(grammar, "AB") }
      .to raise_error(Parsanol::ParseFailed)
  end
end
