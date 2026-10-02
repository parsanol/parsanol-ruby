# frozen_string_literal: true

require "parsanol"
require "fileutils"
require "json"
require "tmpdir"

# GH-121: JSON and PARG sources are UTF-8 by definition, so the PARG
# runtime must read them as UTF-8 even when the process locale is not
# (LANG/LC_ALL unset or C/POSIX makes Encoding.default_external US-ASCII).
RSpec.describe "PARG file reads under a non-UTF-8 locale" do
  def compile_source(src, tables_dir:)
    document = Parsanol::PARG::Parser.new(src).parse
    Parsanol::PARG::Compiler.compile(document, tables_dir: tables_dir)
  end

  def write_utf8(path, text)
    File.write(path, text, encoding: Encoding::UTF_8)
    path
  end

  # Assigning Encoding.default_external warns; the assignment is the point.
  def with_default_external(encoding)
    verbose = $VERBOSE
    $VERBOSE = nil
    Encoding.default_external = encoding
  ensure
    $VERBOSE = verbose
  end

  around do |example|
    previous = Encoding.default_external
    with_default_external(Encoding::US_ASCII)
    example.run
  ensure
    with_default_external(previous)
  end

  let(:dir) { Dir.mktmpdir }
  let(:source) do
    <<~PARG
      grammar Dash version "1.0.0" {
        digit = %x30-39
        number = 1*digit
        en_dash = "–"
        stage_abbr = alt from_table "stages" column "abbr"
        identifier = stage_abbr as stage en_dash number as number
      }

      bindings identifier {
        stage -> stage (string) preprocess: stage_code
        number -> number (integer)
      }

      preprocess stage_code {
        table_lookup stages abbr -> code
      }

      entry identifier: identifier
    PARG
  end
  let(:stages_json) { JSON.generate({ "CD" => { "abbr" => "CD", "code" => "projet–20" } }) }

  after { FileUtils.rm_rf(dir) }

  def compile_with_json_table
    write_utf8(File.join(dir, "stages.json"), stages_json)
    compile_source(source, tables_dir: dir)
  end

  it "loads an artifact and its JSON table" do
    envelope = compile_with_json_table.envelope
    path = write_utf8(File.join(dir, "dash.json"), JSON.generate(envelope))

    artifact = Parsanol::PARG::Artifact.load(path)

    expect(artifact.parse_and_bind("identifier", "CD–12", mode: :ruby))
      .to eq(stage: "projet–20", number: 12)
  end

  it "skips a byte-order mark" do
    envelope = compile_with_json_table.envelope
    path = write_utf8(File.join(dir, "dash.json"), "\uFEFF#{JSON.generate(envelope)}")

    expect(Parsanol::PARG::Artifact.load(path).version).to eq("1.0.0")
  end

  it "reads a JSON table the envelope names by file" do
    envelope = compile_with_json_table.envelope
    envelope["tables"] = { "stages" => "stages.json" }
    envelope["checksum"] = Parsanol::PARG::Compiler.checksum(envelope)
    path = write_utf8(File.join(dir, "dash.json"), JSON.generate(envelope))

    artifact = Parsanol::PARG::Artifact.load(path)

    expect(artifact.table_rows("stages").first["code"]).to eq("projet–20")
  end

  it "merges a used .parg file" do
    write_utf8(File.join(dir, "dash.parg"), <<~PARG)
      grammar Dash version "1.0.0" {
        en_dash = "–"
      }
    PARG
    document = Parsanol::PARG::Parser.new(<<~PARG).parse
      use dash
      grammar Main version "1.0.0" {
        identifier = "A" dash.en_dash "1"
      }
      entry identifier: identifier
    PARG

    Parsanol::PARG::Imports.merge!(document, [dir])

    expect(document.rules).to include("dash.en_dash")
  end

  it "reads a .pgtest suite" do
    write_utf8(File.join(dir, "smoke.pgtest"), <<~PGTEST)
      # en dash in an input
      suite smoke for entry identifier {
        accept "CD–12"
      }
    PGTEST

    suites = Parsanol::PARG::Suite.load(dir)

    expect(suites.fetch("smoke").map(&:input)).to eq(["CD–12"])
  end

  it "loads the self-host artifact" do
    envelope = compile_source(<<~PARG, tables_dir: nil).envelope
      grammar Dash version "1.0.0" {
        file = "A–1"
      }
      entry file: file
    PARG
    path = write_utf8(File.join(dir, "parg.json"), JSON.generate(envelope))
    stub_const("ENV", ENV.to_h.merge("PG_ARTIFACT" => path))

    expect { Parsanol::PARG::SelfHost.validate("A–1") }.not_to raise_error
  end

  it "compiles a .parg file from the CLI" do
    write_utf8(File.join(dir, "stages.json"), stages_json)
    source_path = write_utf8(File.join(dir, "dash.parg"), source)
    out = File.join(dir, "out.json")

    status = nil
    expect { status = Parsanol::PARG::CLI.new(["compile", source_path, "-o", out, "--tables", dir]).run }
      .to output(/out\.json/).to_stdout

    expect(status).to eq(0)
    expect(JSON.parse(File.read(out, encoding: Encoding::UTF_8))["version"]).to eq("1.0.0")
  end

  context "with CLI inputs" do
    let(:artifact_path) do
      write_utf8(File.join(dir, "dash.json"), JSON.generate(compile_with_json_table.envelope))
    end

    # The native engine raises "expected utf-8, got ASCII-8BIT" on BINARY input.
    it "parses a BINARY-tagged argument as UTF-8" do
      artifact = Parsanol::PARG::Artifact.load(artifact_path)
      allow(Parsanol::PARG::Artifact).to receive(:load).and_return(artifact)
      expect(artifact).to receive(:parse)
        .with("identifier", satisfy { |input| input.encoding == Encoding::UTF_8 })
        .and_call_original
      cli = Parsanol::PARG::CLI.new(["parse", artifact_path, "--json", "CD–12".b])

      expect { cli.run }.to output(/"stage":"projet–20"/).to_stdout
    end

    it "reads repl lines as UTF-8" do
      $stdin = StringIO.new((+"CD–12\n").force_encoding(Encoding::US_ASCII))
      cli = Parsanol::PARG::CLI.new(["repl", artifact_path])

      expect { cli.run }.to output(/captures: .*number: 12/).to_stdout
    ensure
      $stdin = STDIN
    end
  end
end
