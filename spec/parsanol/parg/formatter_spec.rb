# frozen_string_literal: true

require "parsanol"
require "json"
require "tmpdir"
require "fileutils"

# ruby#494: `parg fmt` — the canonical formatter. A formatter, not a
# re-writer: the three gates are semantics preservation (the compiled
# envelopes minus the provenance fields are identical), idempotence
# (fmt(fmt(x)) == fmt(x)), and parse-error passthrough. The corpus
# gates run over the pubid-grammar fleet when a checkout is present;
# the synthetic cases pin the canonical layout itself.
RSpec.describe Parsanol::PARG::Formatter do
  def fmt(source)
    described_class.format(source)
  end

  # -- canonical layout ---------------------------------------------------

  it "normalizes spacing, nesting, and the blank-line policy" do
    expect(fmt(<<~PARG)).to eq(<<~CANON)
      grammar Demo version "1.0.0" edition 2 {
        digit= %x30-39
        pair   =  1*digit "-"  digit
              entry main:pair
      }
    PARG
      grammar Demo version "1.0.0" edition 2 {
        digit = %x30-39
        pair = 1* digit "-" digit

        entry main: pair
      }
    CANON
  end

  it "breaks brace groups at each top-level slash, two spaces deeper" do
    expect(fmt(<<~PARG)).to eq(<<~CANON)
      grammar Demo version "1.0.0" {
        prefix = { "E9111" / "CECC"
            / "A" / "B" }
        paren = ( "x" / "y" )
      }
    PARG
      grammar Demo version "1.0.0" {
        prefix = {
          "E9111"
          / "CECC"
          / "A"
          / "B"
        }
        paren = ("x" / "y")
      }
    CANON
  end

  it "keeps slashes inside parens inline" do
    formatted = fmt(<<~PARG)
      grammar Demo version "1.0.0" {
        code = ( "x" / 1*( digit / upper ) )
      }
    PARG
    expect(formatted).to include('code = ("x" / 1* (digit / upper))')
  end

  it "preserves ## docs verbatim and attaches them at the rule indent" do
    formatted = fmt(<<~PARG)
      grammar Demo version "1.0.0" {
        ## The publisher vocabulary.
        ## Second line stays.
        publisher = %i"iso" / %i"ieee"
        identifier = publisher " " digit
        digit = 1*( %x30-39 )
      }
    PARG
    expect(formatted).to eq(<<~CANON)
      grammar Demo version "1.0.0" {
        ## The publisher vocabulary.
        ## Second line stays.
        publisher = %i"iso" / %i"ieee"
        identifier = publisher " " digit
        digit = 1* (%x30-39)
      }
    CANON
  end

  it "keeps interior # comments attached at their depth" do
    formatted = fmt(<<~PARG)
      grammar Demo version "1.0.0" {
        prefix = {
          # the two-letter codes first
          "AU" / "HC"
        }
      }
    PARG
    expect(formatted).to eq(<<~CANON)
      grammar Demo version "1.0.0" {
        prefix = {
          # the two-letter codes first
          "AU"
          / "HC"
        }
      }
    CANON
  end

  it "aligns bindings arrows on the widest left side" do
    expect(fmt(<<~PARG)).to eq(<<~CANON)
      grammar Demo version "1.0.0" {
        item = 1* %x30-39 as n
        main = item * ("," item)

        entry main: main

        bindings main {
          short            -> a (string)
          much_longer_name -> b (raw)
        }
      }
    PARG
      grammar Demo version "1.0.0" {
        item = 1* %x30-39 as n
        main = item * ("," item)

        entry main: main

        bindings main {
          short            -> a (string)
          much_longer_name -> b (raw)
        }
      }
    CANON
  end

  it "keeps multi-line example bodies as rows" do
    formatted = fmt(<<~PARG)
      grammar Demo version "1.0.0" {
        item = 1* %x30-39 as n
        main = item * ("," item)
        entry main: main
        test main {
          example "7" {
            n: 7,
          }
        }
      }
    PARG
    expect(formatted).to include("    example \"7\" {\n")
    # interior rows keep the body indent (row-oriented canonical)
    expect(formatted).to include("    n: 7,\n")
    expect(formatted).to include("    }\n")
  end

  # -- the gates ----------------------------------------------------------

  it "round-trips: the formatted source relexes to the same token stream" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        ## Doc.
        a   =   "x"  /  "y"
        b = { "p" / "q" }
      }
    PARG
    strip = ->(text) do
      Parsanol::PARG::Lexer.new(text).tokens
                           .reject { |t| %i[ws newline comment doc].include?(t.type) }
                           .map { |t| [t.type, t.value] }
    end
    expect(strip.call(fmt(source))).to eq(strip.call(source))
  end

  it "is idempotent on a layout-chaotic source" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        item="x"
        b    =    {  "p"
          /"q" }
        main = item * ("," item)
        entry main: main
        bindings main { x->x (string) }
      }
    PARG
    once = fmt(source)
    expect(fmt(once)).to eq(once)
  end

  it "raises the parser's error for an unparseable file" do
    expect { fmt("grammar Broken { main = ( }\n") }
      .to raise_error(Parsanol::PARG::ParseError)
  end

  # -- the fleet corpus (when a pubid-grammar checkout is present) -------

  def corpus_dir
    candidates = [
      ENV["PARG_GRAMMAR_DIR"],
      File.expand_path("../../../../pubid/pubid-grammar/grammars", __dir__),
    ].compact
    candidates.find { |dir| dir && Dir.glob(File.join(dir, "*.parg")).any? }
  end

  it "holds the gates over the fleet corpus" do
    dir = corpus_dir
    skip "no pubid-grammar checkout (set PARG_GRAMMAR_DIR)" unless dir

    provenance = %w[source source_hash semantics_hash checksum byte_checksum]
    files = Dir.glob(File.join(dir, "*.parg")).sort
    expect(files.length).to be >= 40
    files.each do |path|
      name = File.basename(path, ".parg")
      source = File.read(path)
      formatted = fmt(source)
      expect(fmt(formatted)).to eq(formatted), "#{name}: not idempotent"
      envelopes = {}
      [ [source, "orig"], [formatted, "fmt"] ].each do |text, tag|
        # imports resolve against the source's directory, so the
        # variants compile in place inside the checkout
        variant = File.join(dir, "_fmt_#{name}_#{tag}.parg")
        File.write(variant, text)
        begin
          status = Parsanol::PARG::CLI.new(["compile", variant, "-o", "#{variant}.json"]).run
          expect(status).to be_zero, "#{name}: formatted source does not compile"
          env = JSON.parse(File.read("#{variant}.json"))
          provenance.each { |key| env.delete(key) }
          envelopes[tag] = env
        ensure
          File.delete(variant)
          File.delete("#{variant}.json") if File.exist?("#{variant}.json")
        end
      end
      expect(envelopes["orig"]).to eq(envelopes["fmt"]), "#{name}: semantics changed"
    end
  end
end
