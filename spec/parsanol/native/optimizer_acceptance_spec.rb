# frozen_string_literal: true

require "spec_helper"

# Regression specs for the optimizer's rule: it may never alter the
# accepted language (issue #39 — H2/_2O was accepted under native and
# rejected by parslet after Re runs were merged by source concatenation).
RSpec.describe "optimizer acceptance parity", :native do
  let(:alternating_pair) do
    # Re("a|") then Re("b"): the sequence demands "a" followed by "b".
    # Naively merging the sources ("a|" + "b" = "a|b") produces a single
    # one-char class that also accepts "a" alone.
    Parsanol.match("a|") >> Parsanol.match("b")
  end

  it "rejects what the unmerged sequence rejects (native)" do
    expect { Parsanol::Native.parse(alternating_pair, "a") }
      .to raise_error(Parsanol::ParseFailed)
  end

  it "accepts what the unmerged sequence accepts (native)" do
    expect(Parsanol::Native.parse(alternating_pair, "ab")).not_to be_nil
  end

  it "matches the Ruby engine on both inputs" do
    ["a", "ab"].each do |input|
      ruby = begin
        alternating_pair.parse(input, mode: :ruby)
        :ok
      rescue Parsanol::ParseFailed
        :fail
      end
      native = begin
        Parsanol::Native.parse(alternating_pair, input)
        :ok
      rescue Parsanol::ParseFailed
        :fail
      end
      expect(native).to eq(ruby), "input #{input.inspect}: ruby=#{ruby} native=#{native}"
    end
  end

  it "Str-run merging stays safe across the sequence boundary" do
    atom = Parsanol.str("a") >> Parsanol.str("b") >> Parsanol.match("[c-z]")
    expect { Parsanol::Native.parse(atom, "ab") }.to raise_error(Parsanol::ParseFailed)
    expect(Parsanol::Native.parse(atom, "abc").to_s).to eq("abc")
  end
end
