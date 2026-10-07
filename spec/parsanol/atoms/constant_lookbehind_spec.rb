# frozen_string_literal: true

require "json"
require "spec_helper"

# rs#137 follow-up: the wire-expressible Constant / Lookbehind atoms
# (coradoc-markdown Output / precedes? parity). Interpreter semantics
# here; the native differential activates once the ext carries the
# rs#190 variants.
RSpec.describe "Constant and Lookbehind atoms" do
  let(:value) { { hr: true } }

  it "matches empty and yields the constant (ruby mode)" do
    atom = Parsanol::Atoms::Sequence.new(
      Parsanol::Atoms::Str.new("--"), Parsanol::Atoms::Constant.new(value)
    )
    source = Parsanol::Source.new("--rest")
    context = Parsanol::Atoms::Context.new
    ok, result = atom.apply(source, context, false)
    expect(ok).to be(true)
    expect(result).to include({ hr: true })
    expect(source.bytepos).to eq(2)
  end

  it "lookbehind asserts the byte window behind (ruby mode)" do
    atom = Parsanol::Atoms::Lookbehind.new(2, "--")
    source = Parsanol::Source.new("--rest")
    context = Parsanol::Atoms::Context.new
    source.bytepos = 2
    ok, = atom.apply(source, context, false)
    expect(ok).to be(true)
    expect(source.bytepos).to eq(2)
  end

  it "negative lookbehind refutes the byte window (ruby mode)" do
    atom = Parsanol::Atoms::Lookbehind.new(2, "zz", positive: false)
    source = Parsanol::Source.new("--rest")
    context = Parsanol::Atoms::Context.new
    source.bytepos = 2
    ok, = atom.apply(source, context, false)
    expect(ok).to be(true)
  end

  it "serializes both atoms to the wire shape" do
    constant = Parsanol::Atoms::Constant.new({ hr: true })
    wire = JSON.parse(
      Parsanol::Native.serialize_grammar(Parsanol::Atoms::Constant.new({ hr: true })),
    )
    expect(wire["root"]).to eq(0)
    expect(wire["atoms"][0]).to eq(
      "Constant" => { "value" => { "Hash" => [["hr", { "Bool" => true }]] } },
    )
    look = JSON.parse(
      Parsanol::Native.serialize_grammar(Parsanol::Atoms::Lookbehind.new(2, "--")),
    )
    expect(look["atoms"][0]).to eq(
      "Lookbehind" => { "count" => 2, "pattern" => "--", "positive" => true },
    )
    expect(constant.value).to eq(value)
  end

  it "parses identically natively once the ext carries rs#190", :native_parity do
    skip "ext lacks Constant/Lookbehind (rs#190 release pending)" unless native_supports_new_atoms?

    grammar = Parsanol::Atoms::Sequence.new(
      Parsanol::Atoms::Str.new("--"), Parsanol::Atoms::Constant.new({ hr: true })
    )
    wire = Parsanol::Native.serialize_grammar(grammar)
    native = Parsanol::Native.parse(wire, "--rest")
    expect(native[:hr]).to be(true)
  end

  def native_supports_new_atoms?
    Parsanol::Native.available?
    wire = Parsanol::Native.serialize_grammar(Parsanol::Atoms::Constant.new(nil))
    Parsanol::Native.parse(wire, "x")
    true
  rescue StandardError
    false
  end
end
