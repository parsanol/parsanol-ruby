# frozen_string_literal: true

require "parsanol"

RSpec.describe Parsanol::PG::Import do
  def compile_source(src, tables_dir: nil)
    document = Parsanol::PG::Parser.new(src).parse
    Parsanol::PG::Compiler.compile(document, tables_dir: tables_dir)
  end

  describe ":abnf" do
    let(:abnf) do
      <<~ABNF
        ; sample ABNF grammar
        identifier = publisher SP number
        publisher = "iso" / "ieee"    ; bare strings are case-insensitive
        number = 2*4DIGIT
        crlf-pair = %x0D.0A
        range-pair = %x30-39
        list = "a"
        list =/ "b" / "c"
      ABNF
    end

    it "imports, compiles, and parses" do
      src = described_class.import(:abnf, abnf)
      expect(src).to include("grammar imported_abnf")
      expect(src).to include('%i"iso" / %i"ieee"')
      result = compile_source(src)
      atom = result.atoms.fetch("identifier")
      parsed = atom.parse("ISO 1234")
      expect(parsed.to_s).to eq("ISO 1234")
    end

    it "keeps ABNF core rules available" do
      src = described_class.import(:abnf, abnf)
      expect(src).to include("digit = %x30-39")
      expect(src).to include("sp = %x20")
    end

    it "merges incremental alternatives (=/)" do
      src = described_class.import(:abnf, abnf)
      expect(src).to include('list = %i"a" / %i"b" / %i"c"')
    end

    it "rejects prose-vals" do
      expect { described_class.import(:abnf, "bad = <any char>\n") }
        .to raise_error(Parsanol::PG::Import::Error, /prose/)
    end

    it "converts decimal and binary numeric values to hex" do
      src = described_class.import(:abnf, "vt = %d13 / %b1010\n")
      expect(src).to include("%x0d / %x0a")
    end
  end

  describe ":ebnf" do
    let(:ebnf) do
      <<~EBNF
        (* ISO 14977 style *)
        identifier = publisher , "-" , number ;
        publisher = "iso" | "ieee" ;
        number = digit , { digit } ;
        digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
      EBNF
    end

    it "imports, compiles, and parses" do
      src = described_class.import(:ebnf, ebnf)
      expect(src).to include("grammar imported_ebnf")
      result = compile_source(src)
      parsed = result.atoms.fetch("identifier").parse("iso-42")
      expect(parsed.to_s).to eq("iso-42")
    end

    it "approximates syntactic exceptions with lookahead" do
      src = described_class.import(:ebnf, "x = \"abc\" - \"ab\" ;\n")
      expect(src).to include('!("ab") "abc"')
      expect(src).to include("syntactic exception")
      expect { compile_source(src) }.not_to raise_error
    end

    it "rejects special sequences" do
      expect { described_class.import(:ebnf, "x = ? control chars ? ;\n") }
        .to raise_error(Parsanol::PG::Import::Error, /special sequence/)
    end
  end

  describe ":pest" do
    let(:pest) do
      <<~PEST
        // sample pest grammar
        num = { ASCII_DIGIT+ }
        word = @{ ('a'..'z')+ }
        sum = { term ~ "+" ~ term }
        term = { num | word }
      PEST
    end

    it "imports, compiles, and parses" do
      src = described_class.import(:pest, pest)
      expect(src).to include("grammar imported_pest")
      result = compile_source(src)
      parsed = result.atoms.fetch("sum").parse("42 + abc")
      expect(parsed.to_s).to eq("42 + abc")
    end

    it "notes the implicit-whitespace difference at ~" do
      src = described_class.import(:pest, pest)
      expect(src).to include("implicit")
    end

    it "maps character ranges and builtins to hex" do
      src = described_class.import(:pest, pest)
      expect(src).to include("%x61-7a")
      expect(src).to include("%x30-39")
    end

    it "rejects pest-only builtins" do
      expect { described_class.import(:pest, "r = { PUSH(\"x\") }") }
        .to raise_error(Parsanol::PG::Import::Error, /PUSH/)
    end

    it "rejects the implicit WHITESPACE rule" do
      expect { described_class.import(:pest, "WHITESPACE = { \" \" }") }
        .to raise_error(Parsanol::PG::Import::Error, /WHITESPACE/)
    end
  end

  describe "unknown kinds" do
    it "raises with the supported list" do
      expect { described_class.import(:bnf, "x = y") }
        .to raise_error(Parsanol::PG::Import::Error, /:abnf, :ebnf, :pest/)
    end
  end
end
