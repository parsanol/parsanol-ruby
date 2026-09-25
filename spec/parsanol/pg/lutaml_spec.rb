# frozen_string_literal: true

require "parsanol"
require "fileutils"
require "json"
require "tmpdir"

begin
  require "lutaml/model"
rescue LoadError => e
  warn "lutaml-model load failed: #{e.class}: #{e.message}"
end

RSpec.describe Parsanol::PG::Lutaml do
  let(:source) do
    <<~PG
      grammar Demo version "1.0.0" {
        digit = %x30-39
        number = 1*digit
        space = " "
        publisher = %i"iso" / %i"ieee"
        stage_abbr = alt from_table "stages" column "abbr"
        stage_seq = stage_abbr as stage space
        iso_identifier = publisher as publisher space [stage_seq] number as number
      }

      bindings iso_identifier {
        publisher -> publisher (string)
        stage -> stage (string) preprocess: stage_code
        number -> number (integer)
      }

      preprocess stage_code {
        table_lookup stages abbr -> code
      }

      entry identifier: iso_identifier
    PG
  end

  let(:tables_dir) do
    dir = Dir.mktmpdir
    File.write(File.join(dir, "stages.yaml"), "CD: { abbr: CD, code: draft20 }\n")
    dir
  end

  let(:artifact_path) do
    document = Parsanol::PG::Parser.new(source).parse
    env = Parsanol::PG::Compiler.compile(document, tables_dir: tables_dir).envelope
    file = File.join(tables_dir, "demo.json")
    File.write(file, JSON.generate(env))
    file
  end

  after do
    FileUtils.rm_rf(tables_dir)
    if defined?(Lutaml::Model) && described_class.respond_to?(:register)
      Lutaml::Model::FormatRegistry.instance_variable_get(:@registered_formats)&.delete(:pg_demo)
    end
  end

  it "registers the artifact as a lutaml-model string format", skip: !defined?(Lutaml::Model) do
    described_class.register(
      PgLutamlDemoIdentifier,
      format_name: :pg_demo,
      artifact: artifact_path,
      entry: "identifier",
      tables_dir: tables_dir,
    )

    model = PgLutamlDemoIdentifier.from_pg_demo("ISO CD 12345")
    expect(model.publisher).to eq("ISO")
    expect(model.number).to eq(12_345)
    expect(model.stage).to eq("draft20")
  end

  it "raises loudly without lutaml-model" do
    unless defined?(Lutaml::Model)
      expect do
        described_class.register(Object, format_name: :pg_demo, artifact: artifact_path, entry: "identifier")
      end.to raise_error(Parsanol::PG::Error, /lutaml-model/)
    end
  end
end

if defined?(Lutaml::Model)
  class PgLutamlDemoIdentifier
    include Lutaml::Model::Serialize

    attribute :publisher, :string
    attribute :number, :integer
    attribute :stage, :string
  end
end
