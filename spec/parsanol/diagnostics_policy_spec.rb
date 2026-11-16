# frozen_string_literal: true

require "spec_helper"

# ruby#520: the DiagnosticsPolicy surface (rs#498 v2) through the ruby
# FFI — Parser.diagnostics_handle gains the policy keyword. The
# guarantees are value-level: observable failure output (message,
# position) is identical between :legacy and :pending; :pending drops
# the successful-parse label allocation on the Rust side.
RSpec.describe "diagnostics policy (ruby#520)" do
  # The engine FFI setter lands first (parsanol-rs, ruby#520); the
  # crates.io pin flips on the next parsanol-ruby train. Skip until the
  # built extension carries the setter.
  before(:all) do
    skip "requires the engine FFI setter (the next engine-linked train)" unless
      Parsanol::Native.respond_to?(:_set_diagnostics_policy)
  end

  def policy_grammar
    Class.new(Parsanol::Parser) do
      rule(:key) { match("[a-z]").repeat(1) }
      rule(:value) { match("[0-9]").repeat(1) }
      rule(:doc) do
        (str("{") >> key.as(:key) >> str(":") >> value.as(:val) >> str("}")).as(:doc)
      end
      root(:doc)
    end.new
  end

  def failing_parse(grammar, policy)
    Parsanol::Native.parse(grammar, '{abc: "not-a-number"}', diagnostics_policy: policy)
  rescue Parsanol::ParseFailed => e
    e
  end

  it "accepts the policy keyword and rejects unknown spellings" do
    g = policy_grammar
    expect { Parsanol::Native::Parser.diagnostics_handle(g, policy: :legacy) }.not_to raise_error
    expect { Parsanol::Native::Parser.diagnostics_handle(g, policy: :pending) }.not_to raise_error
    expect do
      Parsanol::Native::Parser.diagnostics_handle(g, policy: :turbo)
    end.to raise_error(ArgumentError, /:legacy or :pending/)
  end

  it "keeps observable failure output identical between the policies" do
    legacy = failing_parse(policy_grammar, :legacy)
    pending = failing_parse(policy_grammar, :pending)
    expect(legacy).to be_a(Parsanol::ParseFailed)
    expect(pending).to be_a(Parsanol::ParseFailed)
    expect(pending.message).to eq(legacy.message)
  end

  it "keeps successful parses identical between the policies" do
    ok_legacy = Parsanol::Native.parse(policy_grammar, "{abc:42}", diagnostics_policy: :legacy)
    ok_pending = Parsanol::Native.parse(policy_grammar, "{abc:42}", diagnostics_policy: :pending)
    expect(ok_pending).to eq(ok_legacy)
  end

  it "applies the policy to cached handles on repeat calls" do
    first = Parsanol::Native::Parser.diagnostics_handle(policy_grammar, policy: :legacy)
    second = Parsanol::Native::Parser.diagnostics_handle(policy_grammar, policy: :pending)
    expect(second).to eq(first) # the same cached handle
    # and the pending policy is live on it (no raise from the setter)
    expect { Parsanol::Native.parse(policy_grammar, "{abc:1}", diagnostics_policy: :pending) }.not_to raise_error
  end
end
