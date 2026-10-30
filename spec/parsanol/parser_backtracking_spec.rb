# frozen_string_literal: true

require "spec_helper"

RSpec.describe Parsanol::Parser do
  it "bounds recursive backtracking when a grammar falls back from the VM" do
    parser = Class.new(described_class) do
      rule(:bang) { str("!") }
      rule(:recursive) do
        (str("x").as(:head) >> recursive.as(:tail) >> bang) |
          (str("x").as(:head) >> recursive.as(:tail)) | str("x").as(:head)
      end
      rule(:document) do
        # Failed alternatives activate adaptive memoization before recursion.
        alternatives = Array.new(70) { str("x").repeat(1) >> str("?").present? }
        alternatives.reduce { |choice, branch| choice | branch } | recursive
      end
      root(:document)
    end.new
    allow(Parsanol::VM).to receive(:program_for).and_return(nil)
    # A call bound catches lost memo coverage without a timing-sensitive test
    # or allowing the unfixed recursive expansion to hang the spec process.
    expect(parser.bang.parslet).to receive(:try).at_most(80).times.and_call_original

    result = parser.parse("x" * 20, mode: :ruby)
    heads = []
    while result
      heads << result.fetch(:head).to_s
      result = result[:tail]
    end

    expect(heads).to eq(Array.new(20, "x"))
  end
end
