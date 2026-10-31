# frozen_string_literal: true

require "parsanol"
require "json"

# TODO.sota/9 T1 (ruby#303): the RFC 5234 core rules are predeclared.
# Class-expressible members ride BUILTIN_CLASSES; CRLF and LWSP inject
# as real rules. A grammar's own rule of the same name shadows either
# mechanism, and only referenced names appear in the artifact.
RSpec.describe "PARG core rules" do
  def artifact_for(source)
    document = Parsanol::PARG::Parser.new(source).parse
    envelope = Parsanol::PARG::Compiler.compile(document).envelope
    Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
  end

  it "serves the class core rules without local definitions" do
    source = <<~PARG
      grammar Core version "1.0.0" edition "v1" {
        line = word SP number CRLF
        word = 1*( ALPHA )
        digit = %x30-39
        number = 1*digit
        entry document: line
      }
    PARG
    tree = artifact_for(source).parse("document", "abc 42\r\n")
    expect(tree).to eq("abc 42\r\n")
  end

  it "serves HEXDIG and HTAB" do
    source = <<~PARG
      grammar Core version "1.0.0" edition "v1" {
        hex = 2HEXDIG HTAB "x"
        entry document: hex
      }
    PARG
    tree = artifact_for(source).parse("document", "aF\tx")
    expect(tree).to eq("aF\tx")
  end

  it "lets a local rule shadow the prelude" do
    source = <<~PARG
      grammar Shadow version "1.0.0" edition "v1" {
        # local DIGIT: only "7" is a digit here
        DIGIT = "7"
        code = 2DIGIT
        entry main: code
      }
    PARG
    artifact = artifact_for(source)
    expect { artifact.parse("main", "77") }.not_to raise_error
    expect { artifact.parse("main", "12") }.to raise_error(Parsanol::ParseFailed)
  end

  it "injects CRLF and LWSP only when referenced" do
    source = <<~PARG
      grammar Core version "1.0.0" edition "v1" {
        folded = "a" LWSP "b"
        entry document: folded
      }
    PARG
    artifact = artifact_for(source)
    expect(artifact.parse("document", "a b")).to eq("a b")
    expect(artifact.parse("document", "ab")).to eq("ab")
    expect(artifact.parse("document", "a\r\n b")).to eq("a\r\n b")
  end

  it "injects CRLF transitively for LWSP" do
    source = <<~PARG
      grammar Core version "1.0.0" edition "v1" {
        gap = "a" LWSP LWSP "b"
        entry document: gap
      }
    PARG
    expect(artifact_for(source).parse("document", "a \r\n b")).to eq("a \r\n b")
  end

  it "does not touch grammars that define their own everything" do
    source = <<~PARG
      grammar Core version "1.0.0" edition "v1" {
        CRLF = "\r\n"
        line = "x" CRLF
        entry document: line
      }
    PARG
    expect(artifact_for(source).parse("document", "x\r\n")).to eq("x\r\n")
  end
end
