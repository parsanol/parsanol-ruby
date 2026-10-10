# frozen_string_literal: true

require "parsanol"
require "json"

# parsanol-ruby#201: [ ... ] is the optional form; brackets whose
# elements are all character classes read as an optional sequence of
# single characters (matchable empty, null captures) — almost
# certainly a mis-typed multi-range class. The concise multi-range
# class is the alternation.
RSpec.describe "PARG bracket-class lint" do
  def compile(source)
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(document).envelope
  end

  it "rejects brackets over a sequence of character classes" do
    source = <<~PARG
      grammar E version "1" {
        escape_char = (%x5C ([%x21-2f%x3a-40%x5b-60%x7b-7e]) as text)
        entry document: escape_char
      }
    PARG
    expect { compile(source) }
      .to raise_error(Parsanol::PARG::CompileError,
                      /multi-range character class is an alternation/)
  end

  it "keeps a single-class bracket as the optional form" do
    source = <<~PARG
      grammar E version "1" {
        doc = ( "a" [ %x42 ] ) as doc
        entry document: doc
      }
    PARG
    envelope = compile(source)
    artifact = Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
    expect(artifact.parse("document", "aB", mode: :ruby)).to eq(doc: "aB")
    expect(artifact.parse("document", "a", mode: :ruby)).to eq(doc: "a")
  end

  it "captures the alternation-of-classes multi-range form on both engines" do
    skip "native engine unavailable" unless Parsanol::Native.available?

    source = <<~PARG
      grammar E version "1" {
        text = *( escape_char / plain ) as text
        escape_char = (%x5C (%x21-2f / %x3a-40 / %x5b-60 / %x7b-7e) as text)
        plain = 1*(%x20-5B / %x5D-7E)
        entry document: text
      }
    PARG
    envelope = compile(source)
    artifact = Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
    input = "a #{92.chr}_ b"
    expect(artifact.parse("document", input, mode: :ruby)).to eq(text: [{ text: "_" }])
    expect(artifact.parse("document", input, mode: :native)).to eq(text: [{ text: "_" }])
  end
end
