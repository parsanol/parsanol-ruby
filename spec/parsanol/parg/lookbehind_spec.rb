# frozen_string_literal: true

require "parsanol"
require "json"

# parsanol-ruby#197 / coradoc#281: the PARG behind-guard surface —
# `!<X` / `&<X` mirror the `!X` / `&X` lookahead prefixes, inspecting
# the text BEHIND the position and consuming nothing. A character
# class body compiles to the end-anchored flanking regex (the CommonMark
# intraword guard); a case-sensitive literal compiles to the fixed
# byte window. The wire atom and both engines have carried Lookbehind
# since 0.15.0 (rs#137/#163) — this is the language surface.
RSpec.describe "PARG lookbehind" do
  def parse(source, input, mode: :ruby)
    document = Parsanol::PARG::Parser.new(source).parse
    envelope = Parsanol::PARG::Compiler.compile(document).envelope
    artifact = Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
    artifact.parse("document", input, mode: mode)
  end

  let(:emph_grammar) do
    <<~PARG
      grammar E version "1" {
        word = 1*( ALPHA )
        star = "*"
        emph = ( !< ALPHA star 1*( !star ANY ) star ) as emph
        doc = *( word / emph / star / " " ) as doc
        entry document: doc
      }
    PARG
  end

  it "suppresses intraword emphasis through the negative class guard" do
    tree = parse(emph_grammar, "a*b mid *c*")
    # the mid-word `*b` run is NOT emphasis (a word char precedes the
    # opening star); the spaced `*c*` run is
    expect(tree).to eq(doc: [{ emph: "*c*" }])
  end

  it "matches the native engine on every guard outcome" do
    skip "native engine unavailable" unless Parsanol::Native.available?

    ["a*b mid *c*", "start *b* end", "*lead* tail"].each do |input|
      expect(parse(emph_grammar, input, mode: :native))
        .to eq(parse(emph_grammar, input, mode: :ruby))
    end
  end

  it "compiles a case-sensitive literal body to the fixed byte window" do
    source = <<~PARG
      grammar E version "1" {
        doc = "ab" ( &< "ab" "c" ) as doc
        entry document: doc
      }
    PARG
    expect(parse(source, "abc")).to eq(doc: "c")
    expect { parse(source, "xbc") }.to raise_error(Parsanol::ParseFailed)
  end

  it "rejects behind bodies that are not literals or classes" do
    source = <<~PARG
      grammar E version "1" {
        doc = ( !< doc ) as d
        entry document: doc
      }
    PARG
    document = Parsanol::PARG::Parser.new(source).parse
    expect { Parsanol::PARG::Compiler.compile(document) }
      .to raise_error(Parsanol::PARG::CompileError, /lookbehind body/)
  end
end
