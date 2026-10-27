# frozen_string_literal: true

# rubocop:disable RSpec/MultipleDescribes -- the radar is a separate surface

require "parsanol"
require "parsanol/parg"
require "json"

RSpec.describe "the capture modes (ruby#304, the #315 spec; the v2 default)" do
  def compile(source)
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(document).envelope
  end

  def grammar(source)
    envelope = compile(source)
    envelope["entries"][envelope["default_entry"]]["grammar"]
  end

  describe "the header and the envelope" do
    it "defaults to v2: a grammar without a declaration gets named trees" do
      default = compile(<<~PARG)
        grammar D version "1.0.0" {
          entry main: main
          main = sep pair
          sep = ","
          pair = ( 1*( %x61-7A ) ) as k "="
        }
      PARG
      expect(default["mode"]).to eq("v2")
      names = default.dig("entries", "main", "grammar", "atoms")
                     .filter_map { |atom| atom.dig("Named", "name") }
      expect(names).to include("sep")
      expect(names).to include("k")
    end

    it "records mode \"v1\" for grammars that pin the legacy shape" do
      classic = compile(<<~PARG)
        grammar C version "1.0.0" mode "v1" {
          entry main: main
          main = sep pair
          sep = ","
          pair = ( 1*( %x61-7A ) ) as k "="
        }
      PARG
      expect(classic["mode"]).to eq("v1")
      names = classic.dig("entries", "main", "grammar", "atoms")
                     .filter_map { |atom| atom.dig("Named", "name") }
      expect(names).to include("k")
      expect(names).not_to include("sep")
    end

    it "accepts an explicit mode \"v2\"" do
      explicit = compile(<<~PARG)
        grammar V version "1.0.0" mode "v2" {
          entry main: w
          w = 1*( %x61-7A )
        }
      PARG
      expect(explicit["mode"]).to eq("v2")
    end

    it "rejects unknown modes" do
      expect do
        compile(<<~PARG)
          grammar B version "1.0.0" mode "future" {
            entry main: w
            w = "x"
          }
        PARG
    end.to raise_error(Parsanol::PARG::ParseError, /supported modes/)
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
        grammar M version "1.0.0" {
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
        JSON.generate(compile(<<~PARG))
          grammar M version "1.0.0" {
            entry main: main
            main = sep pair
            sep = ","
            pair = ( 1*( %x61-7A ) ) as k "="
          }
        PARG
      )
      shape = artifact.parse("main", ",abc=")
      expect(shape).to be_truthy
    end
  end
end

describe "the migration radar (parg lint --captures)" do
  it "reports nothing on a v2 grammar (already named)" do
    source = <<~PARG
      grammar M version "1.0.0" {
        entry main: main
        main = sep pair
        sep = ","
        pair = ( 1*( %x61-7A ) ) as k "="
      }
    PARG
    document = Parsanol::PARG::Parser.new(source).parse
    compiler = Parsanol::PARG::Compiler.new(document, nil)
    document.rules.each_key { |rule| compiler.atom_for(rule) }
    expect(compiler.modern_radar).to be_empty
  end

  it "lists the would-be-wrapped references on a classic grammar" do
    source = <<~PARG
      grammar L version "1.0.0" mode "v1" {
        entry main: main
        main = sep pair
        sep = ","
        pair = ( 1*( %x61-7A ) ) as k "="
      }
    PARG
    document = Parsanol::PARG::Parser.new(source).parse
    compiler = Parsanol::PARG::Compiler.new(document, nil)
    document.rules.each_key { |rule| compiler.atom_for(rule) }
    radar = compiler.modern_radar
    expect(radar.join("\n")).to include('reference to sep produces no capture')
    expect(radar.join("\n")).not_to include("reference to pair")
  end
end

# rubocop:enable RSpec/MultipleDescribes
