# frozen_string_literal: true

require "spec_helper"

# parsanol-ruby#152: skip phase 2 — `skip = trivia capture: comments`
# attaches comment-shaped trivia to the capture it precedes, under
# `comments:`. Whitespace is never recorded; no-capture grammars stay
# byte-identical; captured bytes never join span captures.
RSpec.describe "PARG trivia capture" do
  def compile_capture_grammar
    source = <<~PARG
      grammar Cap version "1" {
        skip = trivia capture: comments
        trivia = 1*( ( 1*" " ) / line_comment / block_comment )
        line_comment = "//" ( *( !newline ANY ) )
        block_comment = "/*" ( *( !"*/" ANY ) ) "*/"
        newline = %x0A
        word = ( 1*( ALPHA ) ) as word
        sep = ","
        item = ( word / num ) as item
        num = ( 1*( DIGIT ) ) as num
        list = ( item *( sep item ) ) as list
        entry document: list
        test { accept "alpha, 42" }
      }
    PARG
    document = Parsanol::PARG::Parser.new(source).parse
    envelope = Parsanol::PARG::Compiler.compile(document).envelope
    Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
  end

  it "attaches comments to the capture they precede" do
    tree = compile_capture_grammar.parse("document", "alpha /* intro */ , 42", mode: :ruby)
    items = tree[:list]
    second = items[1][:item]
    expect(second[:num].to_s).to eq("42")
    expect(second[:comments]).to eq([{ block_comment: "/* intro */" }])
    # span discipline: the comment's bytes are outside the num span
    expect(second[:num].offset).to eq(20)
  end

  it "attaches trailing trivia to the enclosing entry capture" do
    tree = compile_capture_grammar.parse("document", "alpha // tail", mode: :ruby)
    expect(tree[:comments]).to eq([{ line_comment: "// tail" }])
  end

  it "never records whitespace and omits the key when no comments match" do
    tree = compile_capture_grammar.parse("document", "  alpha , 42  ", mode: :ruby)
    expect(tree).not_to have_key(:comments)
    expect(tree[:list][0][:item]).not_to have_key(:comments)
  end

  it "keeps no-capture grammars byte-identical (key absence)" do
    source = <<~PARG
      grammar Plain version "1" {
        skip = spaces
        spaces = 1*" "
        word = ( 1*( ALPHA ) ) as word
        entry document: word
      }
    PARG
    envelope = Parsanol::PARG::Parser.new(source).parse.then do |doc|
      Parsanol::PARG::Compiler.compile(doc).envelope
    end
    artifact = Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
    tree = artifact.parse("document", "  abc ", mode: :ruby)
    expect(tree).to eq(word: "abc")
  end

  it "reserves capture as a keyword" do
    expect do
      Parsanol::PARG::Parser.new(<<~PARG).parse
        grammar Bad version "1" {
          capture = "x"
          entry document: capture
        }
      PARG
    end.to raise_error(Parsanol::PARG::ParseError)
  end
end
