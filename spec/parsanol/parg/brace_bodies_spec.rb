# frozen_string_literal: true

require "parsanol"
require "json"

# TODO.sota/9 T2 (ruby#302): `name = { ... }` is the self-delimiting
# rule body — newlines and comments are whitespace inside, the body
# extends to the matching `}`, and `##` doc comments attach structurally.
# Additive: `{` never appeared at a rule head before; line-mode parsing
# is unchanged (the whole-conformance recompile gate pins that).
RSpec.describe "PARG brace bodies" do
  def compile(source)
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(document)
  end

  def artifact_for(source)
    Parsanol::PARG::Artifact.from_json(JSON.generate(compile(source).envelope))
  end

  it "parses a multi-line body with comments inside the braces" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        ## Publisher code: case-insensitive tag.
        publisher = {
          # a line comment inside the body
          %i"iso" / %i"ieee"
        }

        digit = %x30-39
        number = 1*digit

        ## Publisher, one space, a number.
        iso_identifier = { publisher as publisher
                           " " number as number }

        entry identifier: iso_identifier
      }
    PARG
    tree = artifact_for(source).parse("identifier", "iso 12345")
    expect(tree).to eq(publisher: "iso", number: "12345")
  end

  it "attaches the doc comment to the brace rule structurally" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        ## The documented rule.
        documented = {
          "x"
        }

        entry document: documented
      }
    PARG
    expect(compile(source).envelope[:docs] || compile(source).envelope["docs"])
      .to include("documented" => "The documented rule.")
  end

  it "mixes line-mode and brace-mode rules in one grammar" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        braced = { "a" "b" }
        line = "c" "d"
        both = braced line
        entry document: both
      }
    PARG
    tree = artifact_for(source).parse("document", "abcd")
    expect(tree).to eq("abcd")
  end

  it "lets alternatives and captures sit on their own lines inside the body" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        value =
          {
            number as value /
            word as value
          }

        digit = %x30-39
        number = 1*digit
        word = 1*( ALPHA )
        entry document: value
      }
    PARG
    tree = artifact_for(source).parse("document", "42")
    expect(tree).to eq(value: "42")
  end

  it "rejects an unclosed brace body" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        broken = { "a"
        other = "b"
        entry document: other
      }
    PARG
    expect { Parsanol::PARG::Parser.new(source).parse }
      .to raise_error(Parsanol::PARG::ParseError)
  end

  it "compiles every line-mode grammar unchanged" do
    # The brace form is additive: a grammar that never opens a brace at
    # a rule head parses exactly as before.
    source = <<~PARG
      grammar Demo version "1.0.0" {
        pair = key "=" value
        key = 1*( ALPHA )
        digit = %x30-39
        value = 1*digit
        entry document: pair
      }
    PARG
    tree = artifact_for(source).parse("document", "abc=42")
    expect(tree).to eq("abc=42")
  end
end
