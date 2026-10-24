# frozen_string_literal: true

require "parsanol"
require "json"

# ruby#321: the constrained-decoding export. The compiled artifact
# lowers to XGrammar's EBNF; the supported subset lowers 1:1, the rest
# is rejected naming the construct — the importer philosophy in
# reverse.
RSpec.describe "PARG xgrammar export" do
  def export_source(source)
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Export.call(JSON.generate(Parsanol::PARG::Compiler.compile(document).envelope))
  end

  it "lowers literals, classes, sequences, and repetitions to EBNF" do
    ebnf = export_source(<<~PARG)
      grammar Demo version "1.0.0" {
        entry main: pair
        pair = "a" 1*%x30-39 [ "z" ]
        entry main: pair
      }
    PARG
    expect(ebnf).to eq("main_entry ::= \"a\" [\\x30-\\x39]+ \"z\"?\n")
  end

  it "expands ASCII fold literals to per-character classes" do
    ebnf = export_source(<<~PARG)
      grammar Fold version "1.0.0" {
        entry main: tag
        tag = %i"iso"
      }
    PARG
    expect(ebnf).to include("[Ii][Ss][Oo]")
  end

  it "rejects lookahead naming the construct" do
    source = <<~PARG
      grammar Look version "1.0.0" {
        entry main: tag
        tag = ( !"x" ALPHA ) as tag
      }
    PARG
    expect { export_source(source) }
      .to raise_error(Parsanol::PARG::Export::Error, /lookahead/)
  end

  it "rejects non-ASCII fold groups rather than approximating them" do
    source = <<~PARG
      grammar Fold version "1.0.0" {
        entry main: tag
        tag = %i"café"
      }
    PARG
    expect { export_source(source) }
      .to raise_error(Parsanol::PARG::Export::Error, /non-ASCII fold group/)
  end

  it "rejects an unknown target" do
    expect { Parsanol::PARG::Export.call("{}", target: :elephant) }
      .to raise_error(/unknown export target/)
  end
end
