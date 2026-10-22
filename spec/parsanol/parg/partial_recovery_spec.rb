# frozen_string_literal: true

require "spec_helper"

# R1.5 (TODO.sota/1): parse_recovering carries the deepest repetition
# prefix as a shaped partial tree. The rs engine (parsanol-rs#274) is
# the source of truth; this pins interpreter parity through the
# canonical equality surface.
# R2 declared resync (TODO.sota/1): `resync <rule> = <pattern>` — the
# baked pattern owns the skip spans deterministically. Pinned on both
# engines; the rs spec (parsanol-rs) asserts the same fixture.
RSpec.describe "PARG declared resync (R2)" do
  def declared_artifact
    source = <<~PARG
      grammar RecoveryResync version "1.0.0" {
        pair = ( 1*( %x61-7A / %x30-39 ) ) as k "=" ( 1*( %x30-39 ) ) as v ";"
        document = 1*( pair )
        resync document = 1*( %x00-3A / %x3C-FF ) ";"
        entry main: document

        test main {
          accept "a=1;b=2;"
          reject "a=1;b=2;c=3"
        }
      }
    PARG
    document = Parsanol::PARG::Parser.new(source).parse
    compiled = Parsanol::PARG::Compiler.compile(document, tables_dir: nil)
    Parsanol::PARG::Artifact.from_json(JSON.generate(compiled.envelope))
  end

  it "resyncs with author-owned spans past garbage (both engines)" do
    art = declared_artifact
    %i[native ruby].each do |mode|
      got = art.parse_recovering("main", "a=1;b=2;@@junk@@;c=3;d=4;", mode: mode)
      expect(got["ok"]).to be(false), "#{mode}: expected failure"
      items = got["partial"][got["partial"].keys.first]
      expect(items.length).to eq(4), "#{mode}: expected all four pairs, got #{items.length}"
      expect(Parsanol::PARG::Bindings.canonical(items[2])).to eq(
        Parsanol::PARG::Bindings.canonical(k: "c", v: "3"),
      )
      resyncs = got["resyncs"]
      expect(resyncs.length).to eq(1), "#{mode}: expected one resync"
      expect(resyncs[0]["offset"]).to eq(8)
      expect(resyncs[0]["skipped"]).to eq("@@junk@@;")
      expect(resyncs[0]["resumed_at"]).to eq(17)
    end
  end

  it "adds no resyncs on plain truncation (both engines)" do
    art = declared_artifact
    %i[native ruby].each do |mode|
      got = art.parse_recovering("main", "a=1;b=2;c=3", mode: mode)
      expect(got["resyncs"]).to eq([]), "#{mode}: truncation needs no resync"
    end
  end

  it "rejects captures and unknown targets in resync declarations" do
    source = <<~PARG
      grammar Bad version "1.0.0" {
        a = "x"
        resync a = ( "y" ) as bad
        entry main: a
      }
    PARG
    # Capture validation runs at parse time (the span is annotated
    # error text — bindings inside it would be silently dropped).
    expect { Parsanol::PARG::Parser.new(source).parse }
      .to raise_error(Parsanol::PARG::ParseError, /may not contain captures/)

    source2 = <<~PARG
      grammar Bad2 version "1.0.0" {
        a = "x"
        resync missing = ";"
        entry main: a
      }
    PARG
    document2 = Parsanol::PARG::Parser.new(source2).parse
    expect { Parsanol::PARG::Compiler.compile(document2, tables_dir: nil) }
      .to raise_error(Parsanol::PARG::CompileError, /unknown rule/)
  end
end

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

  it "resyncs past garbage and recovers later items (both engines, R2)" do
    art = artifact
    %i[native ruby].each do |mode|
      got = art.parse_recovering("main", "a=1;b=2;###garbage###c=3;d=4;", mode: mode)
      expect(got["ok"]).to be(false)
      items = got["partial"][got["partial"].keys.first]
      expect(items.length).to eq(4), "#{mode}: expected all four pairs"
      expect(Parsanol::PARG::Bindings.canonical(items[2])).to eq(
        Parsanol::PARG::Bindings.canonical(k: "c", v: "3"),
      )
      resyncs = got["resyncs"]
      expect(resyncs.length).to eq(1), "#{mode}: expected one resync"
      expect(resyncs[0]["skipped"]).to eq("###garbage###")
      expect(resyncs[0]["offset"]).to eq(8)
      expect(resyncs[0]["resumed_at"]).to eq(21)
    end
  end

  it "carries the F7 error wire structure on both engines" do
    art = artifact
    %i[native ruby].each do |mode|
      got = art.parse_recovering("main", "a=1;b=2;c=3", mode: mode)
      wire = got["error"]
      f7_keys = %w[offset line column expected ranked message].freeze
      f7_keys.each do |key|
        expect(wire).to have_key(key), "#{mode}: error wire missing #{key}"
      end
      expect(wire["offset"]).to eq(11), "#{mode}: deepest offset"
      expect(wire["expected"]).to be_an(Array)
      expect(wire["expected"]).not_to be_empty, "#{mode}: expected-set empty"
      expect(wire["ranked"]).to be_an(Array)
      expect(wire["ranked"]).not_to be_empty, "#{mode}: ranked empty"
      positions = wire["ranked"].map(&:first)
      expect(positions).to eq(positions.sort.reverse), "#{mode}: ranked not deepest-first"
      expect(positions.first).to eq(11), "#{mode}: ranked deepest entry"
    end
  end

  it "adds no resyncs on plain truncation (both engines)" do
    art = artifact
    %i[native ruby].each do |mode|
      got = art.parse_recovering("main", "a=1;b=2;c=3", mode: mode)
      expect(got["resyncs"]).to eq([]), "#{mode}: truncation needs no resync"
    end
  end

  it "leaves success paths untouched (no partial key)" do
    art = artifact
    got = art.parse_recovering("main", "a=1;b=2;", mode: :native)
    expect(got["ok"]).to be(true)
    expect(got).not_to have_key("partial")
  end
end
