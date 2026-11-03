# frozen_string_literal: true

# rubocop:disable RSpec/MultipleDescribes -- the radar is a separate surface

require "parsanol"
require "parsanol/parg"
require "json"

RSpec.describe "the capture edition (ruby#304, ruby#357; edition 2 is the only edition)" do
  def compile(source)
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(document).envelope
  end

  def grammar(source)
    envelope = compile(source)
    envelope["entries"][envelope["default_entry"]]["grammar"]
  end

  describe "the header and the envelope" do
    it "a text capture over a reference-built rule stays the matched text (ruby#400)" do
      v2 = compile(<<~PARG)
        grammar T version "1.0.0" edition "v2" {
          root = number as num
          number = 1*digit
          digit = %x30-39
          entry main: root
        }
      PARG
      # Edition 2 is purely additive: the capture's value equals its
      # edition-1 value; no Named leaves inside a captured span.
      expect(v2["entries"]["main"]["grammar"]["atoms"]).not_to include(
        hash_including("Named" => hash_including("name" => "digit")),
      )
      artifact = Parsanol::PARG::Artifact.new(JSON.parse(JSON.generate(v2)), nil, nil)
      expect(artifact.parse("main", "123", mode: :native)).to eq(num: "123")
      expect(artifact.parse("main", "123", mode: :ruby)).to eq(num: "123")

      v1 = compile(<<~PARG)
        grammar T version "1.0.0" {
          root = number as num
          number = 1*digit
          digit = %x30-39
          entry main: root
        }
      PARG
      expect(v1["entries"]["main"]["grammar"]["atoms"]).to eq(v2["entries"]["main"]["grammar"]["atoms"])
    end

    it "defaults to edition 2: a grammar without a declaration gets the named trees" do
      default = compile(<<~PARG)
        grammar D version "1.0.0" {
          entry main: main
          main = sep pair
          sep = ","
          pair = ( 1*( %x61-7A ) ) as k "="
        }
      PARG
      expect(default["edition"]).to eq(2)
      names = default.dig("entries", "main", "grammar", "atoms")
        .filter_map { |atom| atom.dig("Named", "name") }
      expect(names).to include("sep")
      expect(names).to include("k")
    end

    it "opts into edition 2 with the canonical numeric header" do
      explicit = compile(<<~PARG)
        grammar D version "1.0.0" edition 2 {
          entry main: main
          main = sep pair
          sep = ","
          pair = ( 1*( %x61-7A ) ) as k "="
        }
      PARG
      expect(explicit["edition"]).to eq(2)
      names = explicit.dig("entries", "main", "grammar", "atoms")
        .filter_map { |atom| atom.dig("Named", "name") }
      expect(names).to include("sep")
      expect(names).to include("k")
    end

    it "rejects the removed mode keyword; the quoted edition alias canonicalizes" do
      expect do
        compile(<<~PARG)
          grammar M version "1.0.0" mode "v2" {
            entry main: w
            w = 1*( %x61-7A )
          }
        PARG
      end.to raise_error(Parsanol::PARG::ParseError, /edition.*mode.*removed/m)

      quoted = compile(<<~PARG)
        grammar Q version "1.0.0" edition "v2" {
          entry main: w
          w = 1*( %x61-7A )
        }
      PARG
      expect(quoted["edition"]).to eq(2)

      expect do
        compile(<<~PARG)
          grammar C version "1.0.0" edition "classic" {
            entry main: w
            w = 1*( %x61-7A )
          }
        PARG
      end.to raise_error(Parsanol::PARG::ParseError, /edition 1 was removed/)
    end

    it "loads artifacts that spell the edition with the legacy quoted form" do
      envelope = compile(<<~PARG)
        grammar L version "1.0.0" edition 2 {
          entry main: w
          w = 1*( %x61-7A )
        }
      PARG
      envelope["edition"] = "v2"
      envelope["checksum"] = Parsanol::PARG::Compiler.checksum(envelope)
      artifact = Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
      expect(artifact.edition).to eq(2)
    end

    it "does not name whitespace-glue rules (ruby#352)" do
      # A rule that can only match whitespace is glue: wrapping it named
      # every gap in the tree and broke consumers that fold captures
      # into parameters. Conservative exemption: literal-only bodies
      # whose every literal strips to empty.
      glue = compile(<<~PARG)
        grammar G version "1.0.0" edition 2 {
          entry main: main
          space = " "
          ws = space space / space
          sep = space "," space
          main = pair
          pair = ( 1*( %x61-7A ) ) as k sep ( 1*( %x30-39 ) ) as n
        }
      PARG
      names = glue.dig("entries", "main", "grammar", "atoms")
        .filter_map { |atom| atom.dig("Named", "name") }
      expect(names).not_to include("space")
      expect(names).not_to include("ws")
      # sep carries the comma — semantic, stays named.
      expect(names).to include("sep")
    end

    it "treats character-class whitespace as glue too (ruby#352)" do
      # Real grammars spell whitespace as %x20 classes, which compile
      # to Re atoms: the Str-only exemption named every gap.
      glue = compile(<<~PARG)
        grammar G version "1.0.0" edition 2 {
          entry main: main
          ws = %x20 / %x09
          padding = 1*ws
          gap = %x09-0D / %x20
          main = word padding word2 gap word3
          word = 1*( %x61-7A )
          word2 = 1*( %x61-7A )
          word3 = 1*( %x61-7A )
        }
      PARG
      names = glue.dig("entries", "main", "grammar", "atoms")
        .filter_map { |atom| atom.dig("Named", "name") }
      expect(names).not_to include("ws")
      expect(names).not_to include("padding")
      expect(names).not_to include("gap")
      expect(names).to include("word")
    end

    it "keeps classes that admit non-whitespace named" do
      digits = compile(<<~PARG)
        grammar G version "1.0.0" edition 2 {
          entry main: main
          digit = %x30-39
          main = digit "x"
        }
      PARG
      names = digits.dig("entries", "main", "grammar", "atoms")
        .filter_map { |atom| atom.dig("Named", "name") }
      expect(names).to include("digit")
    end

    it "rejects grammars that pin the removed edition 1" do
      expect do
        compile(<<~PARG)
          grammar C version "1.0.0" edition 1 {
            entry main: main
            main = sep pair
            sep = ","
            pair = ( 1*( %x61-7A ) ) as k "="
          }
        PARG
      end.to raise_error(Parsanol::PARG::ParseError, /edition 1 was removed/)
    end

    it "rejects unknown editions" do
      expect do
        compile(<<~PARG)
          grammar B version "1.0.0" edition "future" {
            entry main: w
            w = "x"
          }
        PARG
      end.to raise_error(Parsanol::PARG::ParseError, /edition 1 was removed|edition "future" is not supported/)

      expect do
        compile(<<~PARG)
          grammar B version "1.0.0" edition 3 {
            entry main: w
            w = "x"
          }
        PARG
      end.to raise_error(Parsanol::PARG::ParseError, /edition 1 was removed|edition 3 is not supported/)
    end
  end

  describe "the compile-time wrap" do
    it "wraps uncaptured rule references in Named(rule_name)" do
      atoms = grammar(<<~PARG)["atoms"]
        grammar M version "1.0.0" {
          entry main: main
          main = pair
          pair = ( 1*( %x61-7A ) ) as k "="
        }
      PARG
      # `main = pair`: pair's subtree has a capture (k), so the ref
      # stays bare. Every atom stream kind stays ordinary.
      names = atoms.filter_map { |atom| atom.dig("Named", "name") }
      expect(names).to include("k")
      expect(names).not_to include("pair")
    end

    it "wraps a reference whose subtree has no capture" do
      atoms = grammar(<<~PARG)["atoms"]
        grammar M version "1.0.0" edition 2 {
          entry main: main
          main = sep pair
          sep = ","
          pair = ( 1*( %x61-7A ) ) as k "="
        }
      PARG
      names = atoms.filter_map { |atom| atom.dig("Named", "name") }
      expect(names).to include("sep")
      expect(names).to include("k")
    end

    it "accepts the fully named tree" do
      artifact = Parsanol::PARG::Artifact.from_json(
        JSON.generate(compile(<<~PARG)),
          grammar M version "1.0.0" edition 2 {
            entry main: main
            main = sep pair
            sep = ","
            pair = ( 1*( %x61-7A ) ) as k "="
          }
        PARG
      )
      shape = artifact.parse("main", ",abc=")
      expect(shape).to be_truthy
      expect(artifact.edition).to eq(2)
    end

    it "keys the wrap with a Symbol, like `as` captures and the native engine" do
      artifact = Parsanol::PARG::Artifact.from_json(
        JSON.generate(compile(<<~PARG)),
          grammar M version "1.0.0" edition "v2" {
            entry main: main
            main = word "=" val
            atomic word = 1*( %x61-7A )
            val = ( 1*( %x61-7A ) ) as v
          }
        PARG
      )
      expect(artifact.parse("main", "ab=cd", mode: :ruby).keys)
        .to contain_exactly(:word, :v)
    end

    it "gives the same tree on both engines" do
      skip "native engine unavailable" unless Parsanol::Native.available?

      artifact = Parsanol::PARG::Artifact.from_json(
        JSON.generate(compile(<<~PARG)),
          grammar M version "1.0.0" edition "v2" {
            entry main: main
            main = word "=" word2
            atomic word = 1*( %x61-7A )
            atomic word2 = 1*( %x61-7A )
          }
        PARG
      )
      ruby = artifact.parse("main", "ab=cd", mode: :ruby)
      native = artifact.parse("main", "ab=cd", mode: :native)
      expect(ruby.transform_values(&:to_s))
        .to eq(native.transform_values(&:to_s))
    end
  end

  describe "the glue declaration (parsanol-ruby#364)" do
    def wrapped_names(envelope, entry = "main")
      envelope.dig("entries", entry, "grammar", "atoms")
        .filter_map { |atom| atom.dig("Named", "name") }
    end

    it "keeps declared glue rules bare in edition 2" do
      envelope = compile(<<~PARG)
        grammar G version "1.0.0" edition 2 {
          glue ws
          entry main: main
          ws = 1*( %x20 / ";" / %x0A )
          main = "a" ws "b"
        }
      PARG
      expect(wrapped_names(envelope)).not_to include("ws")
    end

    it "compiles a glue rule's own body unwrapped, all the way down" do
      # ws eats comments; without the glue chain edition 2 would name
      # comment and any_char per character inside every gap.
      envelope = compile(<<~PARG)
        grammar G version "1.0.0" edition 2 {
          glue ws comment
          entry main: main
          ws = ( 1*" " ) / comment
          comment = "//" ( *( !%x0A any_char ) )
          any_char = %x00-10FFFF
          main = "a" ws "b"
        }
      PARG
      names = wrapped_names(envelope)
      expect(names).not_to include("ws")
      expect(names).not_to include("comment")
      expect(names).not_to include("any_char")
    end

    it "adds no envelope field (the wrap is unconditional)" do
      envelope = compile(<<~PARG)
        grammar G version "1.0.0" edition 2 {
          glue ws
          entry main: main
          ws = 1*( %x20 / ";" / %x0A )
          main = "a" ws "b"
        }
      PARG
      expect(wrapped_names(envelope)).not_to include("ws")
      expect(envelope).not_to have_key("glue")
      expect(envelope).not_to have_key("glue_rules")
    end

    it "raises when glue names no rule" do
      expect do
        compile(<<~PARG)
          grammar G version "1.0.0" edition 2 {
            glue
            entry main: main
            main = "a"
          }
        PARG
      end.to raise_error(Parsanol::PARG::ParseError, /glue must name/)
    end
  end
end

# rubocop:enable RSpec/MultipleDescribes
