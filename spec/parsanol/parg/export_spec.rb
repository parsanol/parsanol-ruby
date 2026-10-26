# frozen_string_literal: true

require "parsanol"
require "json"

# ruby#321: the constrained-decoding export. The compiled artifact
# lowers to XGrammar's EBNF; the supported subset lowers 1:1, the rest
# is rejected naming the construct — the importer philosophy in
# reverse.
RSpec.describe "PARG xgrammar export" do
  def export_source(source, recovery: false)
    document = Parsanol::PARG::Parser.new(source).parse
    envelope = JSON.generate(Parsanol::PARG::Compiler.compile(document).envelope)
    Parsanol::PARG::Export.call(envelope, target: :xgrammar, recovery: recovery)
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

  it 'rejects unicode classes rather than emitting \\p/\\u escapes raw' do
    source = <<~PARG
      grammar Unicode version "1.0.0" {
        entry main: main
        main = ( 1*%p{L} ) as word
      }
    PARG
    expect { export_source(source) }
      .to raise_error(Parsanol::PARG::Export::Error, /unicode category/)
  end

  it "recovery mode wraps the spine with the declared resync as an escape" do
    source = <<~PARG
      grammar KV version "1.0.0" {
        pair = ( 1*( %x61-7A / %x30-39 ) ) as k "=" ( 1*( %x30-39 ) ) as v ";"
        document = 1*( pair )
        resync document = 1*( %x00-3A / %x3C-FF ) ";"
        entry main: document
      }
    PARG
    plain_body = export_source(source).split("::=").last.strip
    recovery = export_source(source, recovery: true)
    expect(recovery).to include("|")
    expect(recovery).to include("( #{plain_body} | ")
  end

  it "recovery mode refuses non-spine roots, naming the shape" do
    source = <<~PARG
      grammar One version "1.0.0" {
        one = "x" ", " "y"
        resync one = 1*( %x00-77 ) "x"
        entry main: one
      }
    PARG
    expect { export_source(source, recovery: true) }
      .to raise_error(Parsanol::PARG::Export::Error, /not a repetition spine/)
  end

  it "recovery mode without a declared resync emits the plain grammar" do
    source = <<~PARG
      grammar Plain version "1.0.0" {
        word = ( 1*( %x61-7A ) ) as w
        entry main: word
      }
    PARG
    expect(export_source(source, recovery: true)).to eq(export_source(source))
  end

  it "rejects an unknown target" do
    expect { Parsanol::PARG::Export.call("{}", target: :elephant) }
      .to raise_error(/unknown export target/)
  end
end
