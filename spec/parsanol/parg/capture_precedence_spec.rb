# frozen_string_literal: true

require "parsanol"
require "json"

# parsanol-ruby#197: `as` after a repetition's own closing paren must
# wrap the REPETITION, matching the Ruby DSL's `.repeat.as(:name)` —
# the repetition's body parser is postfix-blind. The body claimed the
# postfix before, inverting the tree to rep(cap(...)) and naming every
# iteration instead of the whole run, which scattered and emptied
# captures in enclosing folds.
RSpec.describe "PARG capture precedence" do
  def compile_document(source)
    Parsanol::PARG::Parser.new(source).parse
  end

  def parse_artifact(source, input, mode: :ruby)
    document = compile_document(source)
    envelope = Parsanol::PARG::Compiler.compile(document).envelope
    artifact = Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
    artifact.parse("document", input, mode: mode)
  end

  it "binds `as` after a repetition's paren to the repetition" do
    document = compile_document(<<~PARG)
      grammar E version "1" {
        text = *( word ) as text
        word = 1*( ALPHA )
        entry document: text
      }
    PARG
    rule = document.rules["text"]
    expect(rule.kind).to eq(:cap)
    expect(rule.a).to eq("text")
    expect(rule.b.kind).to eq(:rep)
  end

  it "binds `as` inside the body's own parens to the body" do
    document = compile_document(<<~PARG)
      grammar E version "1" {
        text = *( ( word ) as each )
        word = 1*( ALPHA )
        entry document: text
      }
    PARG
    rule = document.rules["text"]
    expect(rule.kind).to eq(:rep)
    expect(rule.a.kind).to eq(:cap)
    expect(rule.a.a).to eq("each")
  end

  it "keeps the double-paren capture idiom on the whole repetition" do
    document = compile_document(<<~PARG)
      grammar E version "1" {
        text = ( 1*( ALPHA ) ) as text
        entry document: text
      }
    PARG
    rule = document.rules["text"]
    expect(rule.kind).to eq(:cap)
    expect(rule.b.kind).to eq(:rep)
  end

  # The #197 repro shape: an escape rule inside `*( ... ) as name` —
  # the per-item inversion emptied/lost the escape's capture in the
  # enclosing fold. Both engines must agree with the DSL twin.
  it "captures the escaped character through the repetition fold" do
    source = <<~PARG
      grammar E version "1" {
        text = *( escape_char / plain ) as text
        escape_char = (%x5C ( %x5f ) as text)
        plain = 1*(%x20-5B / %x5D-7E)
        entry document: text
      }
    PARG
    input = "a #{92.chr}_b"
    expect(input.bytes).to eq([97, 32, 92, 95, 98])
    expect(parse_artifact(source, input))
      .to eq(text: [{ text: "_" }])

    skip "native engine unavailable" unless Parsanol::Native.available?
    expect(parse_artifact(source, input, mode: :native))
      .to eq(text: [{ text: "_" }])
  end

  it "captures a whole group after the repetition's prefix terminal" do
    source = <<~PARG
      grammar E version "1" {
        text = *( escape_char / plain ) as text
        escape_char = (%x5C (%x5C %x5f) as text)
        plain = 1*(%x20-5B / %x5D-7E)
        entry document: text
      }
    PARG
    input = "a #{92.chr}#{92.chr}_b"
    expect(parse_artifact(source, input))
      .to eq(text: [{ text: "\\_" }])
  end
end
