# frozen_string_literal: true

require "parsanol"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe Parsanol::PG do
  def compile_source(src, tables_dir:)
    document = Parsanol::PG::Parser.new(src).parse
    Parsanol::PG::Compiler.compile(document, tables_dir: tables_dir)
  end

  def write_artifact(env, dir)
    path = File.join(dir, "demo.json")
    File.write(path, JSON.generate(env))
    path
  end

  let(:stages_yaml) do
    <<~YAML
      CD: { abbr: CD, code: draft20 }
      DIS: { abbr: DIS, code: draft40 }
      IS: { abbr: IS, code: published }
    YAML
  end

  let(:source) do
    <<~PG
      # demo grammar
      grammar Demo version "1.2.0" {
        digit = %x30-39
        number = 1*digit
        space = " "
        dash = "-"
        publisher = %i"iso" / %i"ieee"
        stage_abbr = alt from_table "stages" column "abbr"
        stage_seq = stage_abbr as stage space
        part = dash number as part
        iso_identifier = publisher as publisher space [stage_seq] number as number [part]
      }

      bindings iso_identifier {
        publisher -> publisher (string)
        stage -> stage (string) preprocess: stage_code
        number -> number (integer)
        part -> part (string, 0..1)
      }

      preprocess stage_code {
        table_lookup stages abbr -> code
      }

      entry identifier: iso_identifier
    PG
  end

  describe "Parser" do
    it "parses the document" do
      document = Parsanol::PG::Parser.new(source).parse
      expect(document.version).to eq("1.2.0")
      expect(document.grammar_name).to eq("Demo")
      expect(document.rules).to include("iso_identifier", "stage_abbr")
      expect(document.entries).to eq("identifier" => "iso_identifier")
      expect(document.bindings["iso_identifier"].length).to eq(4)
      expect(document.preprocess["stage_code"]).to eq(
        [{ "op" => "table_lookup", "table" => "stages", "from" => "abbr", "to" => "code" }],
      )
    end

    it "records the source text" do
      document = Parsanol::PG::Parser.new(source).parse
      expect(document.source).to eq(source)
    end

    it "rejects malformed input" do
      expect { Parsanol::PG::Parser.new("grammar X { a = }").parse }
        .to raise_error(Parsanol::PG::ParseError)
      expect { Parsanol::PG::Parser.new("nonsense").parse }
        .to raise_error(Parsanol::PG::ParseError)
      expect { Parsanol::PG::Parser.new('grammar X version "1" { entry = "a" }').parse }
        .to raise_error(Parsanol::PG::ParseError, /keyword/)
    end

    it "rejects duplicate rules and dangling references" do
      src = <<~PG
        grammar X version "1" { a = "x" }
        entry e: missing
      PG
      expect { Parsanol::PG::Parser.new(src).parse }
        .to raise_error(Parsanol::PG::ParseError, /unknown rule/)

      dup = <<~PG
        grammar X version "1" {
          a = "x"
          a = "y"
        }
      PG
      expect { Parsanol::PG::Parser.new(dup).parse }
        .to raise_error(Parsanol::PG::ParseError, /duplicate/)
    end
  end

  describe "Compiler" do
    it "rejects left recursion (direct and indirect)" do
      expect do
        compile_source(<<~PG, tables_dir: nil)
          grammar X version "1" {
            a = a "x"
          }
        PG
      end.to raise_error(Parsanol::PG::CompileError, /left recursion/)

      expect do
        compile_source(<<~PG, tables_dir: nil)
          grammar X version "1" {
            a = b "x"
            b = a / "y"
          }
        PG
      end.to raise_error(Parsanol::PG::CompileError, /left recursion/)
    end

    it "rejects unknown rule references" do
      expect do
        compile_source('grammar X version "1" { a = missing }', tables_dir: nil)
      end.to raise_error(Parsanol::PG::CompileError, /unknown rule/)
    end

    it "rejects a non-final branch that can match empty" do
      src = 'grammar X version "1" { a = [ "b" ] / "c" }'
      expect do
        compile_source(src, tables_dir: nil)
      end.to raise_error(Parsanol::PG::CompileError, /match empty/)
    end

    it "rejects a shorter literal shadowing a longer later branch" do
      src = 'grammar X version "1" { p = "iso" / "iso/iec" }'
      expect do
        compile_source(src, tables_dir: nil)
      end.to raise_error(Parsanol::PG::CompileError, /shadows branch 2/)
    end

    it "records an order-dependent warning for overlapping branches" do
      src = 'grammar X version "1" { p = "iso/iec" / "iso" }'
      result = compile_source(src, tables_dir: nil)
      expect(result.warnings.join).to include("order-dependent")
    end

    it "emits a portable grammar JSON per entry" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "stages.yaml"), stages_yaml)
        result = compile_source(source, tables_dir: dir)
        grammar = result.envelope["entries"]["identifier"]["grammar"]
        expect(grammar).to include("atoms", "root")
        expect(grammar["atoms"]).not_to be_empty
      end
    end
  end

  describe "Artifact" do
    subject(:artifact) do
      Parsanol::PG::Artifact.load(path, tables_dir: tables_dir)
    end

    let(:tables_dir) do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "stages.yaml"), stages_yaml)
      dir
    end

    let(:path) do
      write_artifact(compile_source(source, tables_dir: tables_dir).envelope,
                     tables_dir)
    end

    after { FileUtils.rm_rf(tables_dir) }

    it "verifies the checksum and loads" do
      expect(artifact.version).to eq("1.2.0")
      expect(artifact.entries).to eq(["identifier"])
    end

    it "is byte-stable across compilations" do
      first = compile_source(source, tables_dir: tables_dir).envelope
      second = compile_source(source, tables_dir: tables_dir).envelope
      expect(first["checksum"]).to eq(second["checksum"])
    end

    it "rejects a tampered artifact" do
      env = compile_source(source, tables_dir: tables_dir).envelope
      env["version"] = "9.9.9"
      path = write_artifact(env, tables_dir)
      expect { Parsanol::PG::Artifact.load(path, tables_dir: tables_dir) }
        .to raise_error(Parsanol::PG::ArtifactError, /checksum mismatch/)
    end

    it "rejects unknown entries" do
      expect { artifact.parse("nope", "x") }
        .to raise_error(Parsanol::PG::ArtifactError, /unknown entry/)
    end

    it "parses and applies bindings end to end" do
      bound = artifact.parse_and_bind("identifier", "ISO CD 12345-89")
      expect(bound).to eq(
        publisher: "ISO",
        stage: "draft20",
        number: 12_345,
        part: "89",
      )
    end

    it "omits absent optional bindings" do
      bound = artifact.parse_and_bind("identifier", "ieee IS 123")
      expect(bound).to eq(publisher: "ieee", stage: "published", number: 123)
    end

    it "matches case-insensitive literals" do
      bound = artifact.parse_and_bind("identifier", "ISO IS 7")
      expect(bound[:publisher]).to eq("ISO")
    end

    it "parses identically through the native and ruby paths" do
      skip "native extension not available" unless Parsanol::Native.available?

      native = artifact.parse_and_bind("identifier", "ISO CD 12345-89")
      ruby = artifact.parse_and_bind("identifier", "ISO CD 12345-89", mode: :ruby)
      expect(native).to eq(ruby)
    end

    it "rejects unknown parse modes" do
      expect { artifact.parse("identifier", "ISO IS 7", mode: :warp) }
        .to raise_error(ArgumentError, /mode/)
    end
  end
end
