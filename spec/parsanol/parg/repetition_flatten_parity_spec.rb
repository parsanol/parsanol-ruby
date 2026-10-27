# frozen_string_literal: true

require "spec_helper"
require "json"

# parsanol-ruby#231: an uncaptured sequence rule used as a repetition
# body loses its captures when the repetition also carries Hash-shaped
# iterations. Verified against parslet 2.0.0 (2026-10-19, values below
# are parslet's own outputs for the equivalent DSL): parslet's
# CanFlatten#flatten_repetition keeps ONLY Hash iterations when any
# iteration is a Hash — the artifact runtime is in exact parity,
# including the position-dependent shapes the issue reported as loss.
# Slices normalize to their content (parslet carries offsets; so do we).
NORMALIZE = lambda do |value|
  case value
  when Hash then value.to_h { |key, item| [key, NORMALIZE.call(item)] }
  when Array then value.map { |item| NORMALIZE.call(item) }
  else value.to_s
  end
end

RSpec.describe "repetition flattening parity with parslet (parsanol-ruby#231)" do
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

  # Values verified against the parslet gem (2.0.0) on the equivalent
  # DSL: parslet's merge_fold hoists the sequence's repetition into an
  # array of single-key hashes, and the repetition keeps only Hash
  # iterations when any iteration is a Hash.
  {
    "(oh)" => { us: [{ open: "(" }, { inner: "o" }, { inner: "h" }, { close: ")" }] },
    "A(oh)" => { us: [{ atom: "A" }] },
    "(oh)A" => { us: [{ atom: "A" }] },
    "A(oh)B" => { us: [{ atom: "A" }, { atom: "B" }] },
  }.each do |input, expected|
    it "flattens #{input.inspect} exactly as parslet does (native)" do
      got = artifact.parse("s", input, mode: :native)
      expect(NORMALIZE.call(got)).to eq(expected)
    end

    it "flattens #{input.inspect} exactly as parslet does (ruby)" do
      got = artifact.parse("s", input, mode: :ruby)
      expect(NORMALIZE.call(got)).to eq(expected)
    end
  end
end
