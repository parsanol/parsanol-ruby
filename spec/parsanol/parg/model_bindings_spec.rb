# frozen_string_literal: true

require "parsanol"
require "stringio"
require "tmpdir"
require "json"

# coradoc#307 M4: `parg compile --model-bindings` embeds a rule -> model
# table in the artifact; `parg bindings` dumps it.
RSpec.describe Parsanol::PARG::ModelBindings do
  let(:grammar) do
    <<~PARG
      grammar Demo version "1.0.0" edition 2 {
        hr = "---" as hr
        entry hr: hr
      }
    PARG
  end

  let(:sidecar) do
    {
      "version" => 1,
      "rules" => {
        "thematic_break" => {
          "keys" => ["hr"], "model" => "HorizontalRule", "defaults" => { "style" => "---" }
        },
      },
    }
  end

  def cli(*args, dir)
    out = StringIO.new
    $stdout = out
    status = Dir.chdir(dir) { Parsanol::PARG::CLI.new(args).run }
    [status, out.string]
  ensure
    $stdout = STDOUT
  end

  def compile(dir, *flags)
    File.write(File.join(dir, "g.parg"), grammar)
    cli("compile", "g.parg", "-o", "g.json", *flags, dir)
    JSON.parse(File.read(File.join(dir, "g.json")))
  end

  it "adds no key and keeps the payload when no sidecar is given" do
    Dir.mktmpdir do |dir|
      envelope = compile(dir)
      expect(envelope).not_to have_key("model_bindings")
      expected = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(grammar).parse).envelope
      expect(envelope["checksum"]).to eq(expected["checksum"])
    end
  end

  it "embeds the sidecar as versioned metadata and leaves the rest untouched" do
    Dir.mktmpdir do |dir|
      plain = compile(dir)
      File.write(File.join(dir, "b.json"), JSON.generate(sidecar))
      bound = compile(dir, "--model-bindings", "b.json")

      expect(bound["model_bindings"]["version"]).to eq(1)
      expect(bound["model_bindings"]["rules"]["thematic_break"])
        .to include("model" => "HorizontalRule", "captures" => {}, "children" => {})
      expect(bound.except("model_bindings", "checksum", "byte_checksum"))
        .to eq(plain.except("checksum", "byte_checksum"))
      expect(bound["semantics_hash"]).to eq(plain["semantics_hash"])
      expect(bound["checksum"]).not_to eq(plain["checksum"])
      expect { Parsanol::PARG::Artifact.load(File.join(dir, "g.json")) }.not_to raise_error
    end
  end

  it "accepts a YAML sidecar" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "b.yml"), YAML.dump(sidecar))
      expect(compile(dir, "--model-bindings", "b.yml")["model_bindings"]).to eq(described_class.normalize(sidecar))
    end
  end

  it "rejects an unknown version or a rule without a model" do
    expect { described_class.normalize(sidecar.merge("version" => 9)) }
      .to raise_error(Parsanol::PARG::ArtifactError, /version/)
    bad = { "version" => 1, "rules" => { "r" => { "keys" => ["a"] } } }
    expect { described_class.normalize(bad) }.to raise_error(Parsanol::PARG::ArtifactError, /model/)
  end

  describe "parg bindings" do
    it "dumps rule -> model/captures/children as JSON" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "b.json"), JSON.generate(sidecar))
        compile(dir, "--model-bindings", "b.json")
        status, output = cli("bindings", "g.json", dir)
        expect(status).to eq(0)
        expect(JSON.parse(output)).to eq(described_class.normalize(sidecar))
      end
    end

    it "dumps an empty table for an artifact without bindings" do
      Dir.mktmpdir do |dir|
        compile(dir)
        _status, output = cli("bindings", "g.json", dir)
        expect(JSON.parse(output)).to eq("version" => 1, "rules" => {})
      end
    end

    it "refuses a tampered artifact" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "b.json"), JSON.generate(sidecar))
        envelope = compile(dir, "--model-bindings", "b.json")
        envelope["model_bindings"]["rules"]["thematic_break"]["model"] = "Other"
        File.write(File.join(dir, "g.json"), JSON.generate(envelope))
        expect(cli("bindings", "g.json", dir).first).to eq(1)
      end
    end
  end
end
