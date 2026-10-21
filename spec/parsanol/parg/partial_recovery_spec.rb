# frozen_string_literal: true

require "spec_helper"

# R1.5 (TODO.sota/1): parse_recovering carries the deepest repetition
# prefix as a shaped partial tree. The rs engine (parsanol-rs#274) is
# the source of truth; this pins interpreter parity through the
# canonical equality surface.
RSpec.describe "PARG partial-tree recovery (R1.5)" do
  def artifact
    source = <<~PARG
      grammar KV version "1.0.0" {
        pair = ( 1*( %x61-7A / %x30-39 ) ) as k "=" ( 1*( %x30-39 ) ) as v ";"
        document = 1*( pair )
        entry main: document
      }
    PARG
    document = Parsanol::PARG::Parser.new(source).parse
    compiled = Parsanol::PARG::Compiler.compile(document, tables_dir: nil)
    Parsanol::PARG::Artifact.from_json(JSON.generate(compiled.envelope))
  end

  it "returns the matched prefix on truncated input (both engines)" do
    art = artifact
    %i[native ruby].each do |mode|
      got = art.parse_recovering("main", "a=1;b=2;c=3", mode: mode)
      expect(got["ok"]).to be(false), "#{mode}: expected failure"
      partial = got["partial"]
      expect(partial).not_to be_nil, "#{mode}: no partial tree"
      items = partial[partial.keys.first]
      expect(items.length).to eq(2), "#{mode}: expected two complete items"
      expect(Parsanol::PARG::Bindings.canonical(items[0])).to eq(
        Parsanol::PARG::Bindings.canonical(k: "a", v: "1"),
      )
      expect(Parsanol::PARG::Bindings.canonical(items[1])).to eq(
        Parsanol::PARG::Bindings.canonical(k: "b", v: "2"),
      )
      expect(got["error"]["offset"]).to eq(11), "#{mode}: wrong failure offset"
    end
  end

  it "yields a nil partial when nothing matched (both engines)" do
    art = artifact
    %i[native ruby].each do |mode|
      got = art.parse_recovering("main", "=1;", mode: mode)
      expect(got["ok"]).to be(false)
      expect(got["partial"]).to be_nil, "#{mode}: expected no partial"
    end
  end

  it "leaves success paths untouched (no partial key)" do
    art = artifact
    got = art.parse_recovering("main", "a=1;b=2;", mode: :native)
    expect(got["ok"]).to be(true)
    expect(got).not_to have_key("partial")
  end
end
