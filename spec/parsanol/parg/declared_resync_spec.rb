# frozen_string_literal: true

require "spec_helper"

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
