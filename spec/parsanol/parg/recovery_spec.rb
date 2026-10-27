# frozen_string_literal: true

require "spec_helper"
require "json"

# TODO.sota/1 R1: best-effort recovery. parse_recovering returns the
# shape on success (zero behavior change) and, on ParseFailed, the
# failure offset plus every capture observed before the failure — from
# a journaling re-parse on the Ruby engine (tree parity with the
# native engine is enforced by the differential specs).
# Slices normalize to their content. Never compare .inspect across
# engines or runs: the bytecode VM's trees are plain hashes while the
# interpreter's carry parslet-style inspect - the values are
# parity-gated, the formats are not.
NORMALIZE = lambda do |value|
  case value
  when Hash then value.to_h { |key, item| [key, NORMALIZE.call(item)] }
  when Array then value.map { |item| NORMALIZE.call(item) }
  else value.to_s
  end
end

RSpec.describe "PARG recovery (TODO.sota/1 R1)" do
  def artifact
    source = <<~PARG
      grammar P version "1.0.0" mode "v1" {
        entry s: s
        s = ( 1*( u ) ) as us
        u = pa / g
        pa = ( %x41-5A ) as atom
        g = go 1*( gu ) gc
        go = ( "(" ) as open
        gu = ( %x61-7A ) as inner
        gc = ( ")" ) as close
      }
    PARG
    document = Parsanol::PARG::Parser.new(source).parse
    compiled = Parsanol::PARG::Compiler.compile(document, tables_dir: nil)
    Parsanol::PARG::Artifact.from_json(JSON.generate(compiled.envelope))
  end

  it "returns the shape on success" do
    # The success shape is verbatim the same-mode normal parse result —
    # recovery never alters green paths. (Never compare .inspect across
    # modes/engines: tree inspect formats differ by construction.)
    plain = artifact.parse("s", "(oh)")
    got = artifact.parse_recovering("s", "(oh)")
    expect(got["ok"]).to be(true)
    expect(got["shape"].inspect).to eq(plain.inspect)
  end

  it "reports the failure offset and observed captures on failure" do
    # "A(" — `atom` matches "A", then the `g` branch fails at the
    # unmatched "(": the input does not fully parse. The journal
    # records `atom` (committed) AND `open` (matched inside `g` before
    # it failed) — the documented best-effort superset.
    got = artifact.parse_recovering("s", "A(")
    expect(got["ok"]).to be(false)
    expect(got["error"]["offset"]).to eq(2)
    # Journal entries are the wrapped capture hashes; Slice values
    # stringify to their content.
    expect(got["captures"]["atom"].map { |e| e[:atom].to_s }).to include("A")
    expect(got["captures"]["open"].map { |e| e[:open].to_s }).to include("(")
  end

  it "reports the deepest failure offset for truncated input" do
    got = artifact.parse_recovering("s", "(oh")
    expect(got["ok"]).to be(false)
    expect(got["error"]["offset"]).to eq(3)
    expect(got["captures"]["open"].map { |e| e[:open].to_s }).to include("(")
  end

  it "leaves success paths byte-identical" do
    # The journaling is only active during recovery re-parses; a normal
    # parse never touches it.
    got = artifact.parse("s", "(oh)", mode: :ruby)
    expect(NORMALIZE.call(got)).to eq(
      NORMALIZE.call(us: [{ open: "(" }, { inner: "o" }, { inner: "h" }, { close: ")" }]),
    )
  end
end
