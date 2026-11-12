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

  # ruby#460: the llguidance target — Lark subset, enters through
  # `start`, no {m,n} (bounds expand mechanically, capped), same
  # loud-reject contract.
  describe "PARG llguidance export" do
    def export_source(source, recovery: false)
      document = Parsanol::PARG::Parser.new(source).parse
      envelope = JSON.generate(Parsanol::PARG::Compiler.compile(document).envelope)
      Parsanol::PARG::Export.call(envelope, target: :llguidance, recovery: recovery)
    end

    it "enters through start and lowers literals, classes, and suffixes" do
      text = export_source(<<~PARG)
        grammar Demo version "1.0.0" {
          digit = %x30-39
          year = 4*digit as y
          entry main: stamp
          stamp = [year "-"] 1*ALPHA as head
        }
      PARG
      expect(text).to start_with("start: main_entry\n")
      expect(text).to include("main_entry:")
      expect(text).to include("]+")
      expect(text).to include(")?")
      # the bounded year expands: four exact copies then the * tail
      expect(text.scan("[\\x30-\\x39]").count).to eq(5)
    end

    it "expands bounded repetitions exactly without an upper-bound overrun" do
      text = export_source(<<~PARG)
        grammar Code version "1.0.0" {
          digit = %x30-39
          code = 1*3digit as c
          entry main: code
        }
      PARG
      body = text.lines.grep(/^main_entry/).first
      # one required copy, then optional copies up to the bound — never
      # more than three digits can match
      expect(body).to eq("main_entry: ( ( ( [\\x30-\\x39] ) ) ( ( [\\x30-\\x39] ) )? ( ( [\\x30-\\x39] ) )? )\n")
      expect(body.scan(")?").count).to eq(2)
    end

    it "rejects a bound past the expansion cap naming the construct" do
      source = <<~PARG
        grammar Big version "1.0.0" {
          digit = %x30-39
          many = 65*digit as m
          entry main: many
        }
      PARG
      document = Parsanol::PARG::Parser.new(source).parse
      envelope = JSON.generate(Parsanol::PARG::Compiler.compile(document).envelope)
      expect { Parsanol::PARG::Export.call(envelope, target: :llguidance) }
        .to raise_error(Parsanol::PARG::Export::Error, /65-item expansion cap|{65,n} exceeds/)
    end

    it "rejects lookahead naming the construct" do
      source = <<~PARG
        grammar Look version "1.0.0" {
          entry main: tail
          tail = "a" &"b"
        }
      PARG
      expect { export_source(source) }
        .to raise_error(Parsanol::PARG::Export::Error, /llguidance export.*lookahead/)
    end

    it "rejects a recursive grammar naming the re-entry" do
      # A recursive grammar's inline EBNF unfold is infinite in
      # principle — the self-hosted parg meta-grammar exposed the
      # naive walk's stack blowup; the rejection names the re-entry.
      source = <<~PARG
        grammar Recursive version "1.0.0" {
          entry main: expr
          expr = "(" expr ")"
        }
      PARG
      expect { export_source(source) }
        .to raise_error(Parsanol::PARG::Export::Error,
                        /recursive grammar: atom \d+ re-enters while being lowered/)
    end

    it "lowers shared subtrees through the memo walk" do
      # Rules referenced twice form a diamond DAG; the memo keeps the
      # walk linear in the DAG (2^4 unfold, 16 literal copies).
      ebnf = export_source(<<~PARG)
        grammar Diamond version "1.0.0" {
          entry main: a
          a = b b
          b = c c
          c = d d
          d = e e
          e = "x"
        }
      PARG
      expect(ebnf.scan('"x"').count).to eq(16)
    end

    it "registers both targets" do
      expect(Parsanol::PARG::Export::TARGETS).to contain_exactly(:xgrammar, :llguidance)
    end
  end
end
