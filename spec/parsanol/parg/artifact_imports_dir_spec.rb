# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "fileutils"

# parsanol-ruby#208: qualified references into `use` imports must resolve
# on every parse surface. The ≥1.3.90 runtime recompiles an artifact's
# embedded source for the pure-Ruby path; artifacts whose source carries
# `use <name>` failed with `unknown rule "base.b"` unless the imported
# .parg happened to sit beside the artifact.
RSpec.describe "PARG Artifact imports_dir (parsanol-ruby#208)" do
  let(:base_source) do
    <<~PARG
      grammar MinBase version "1.0" {
        b = "x" as b
        entry b: b
      }
    PARG
  end

  let(:main_source) do
    <<~PARG
      use base
      grammar MinMain version "1.0" {
        c = base.b "y" as c
        entry c: c
        test {
          accept "xy"
        }
      }
    PARG
  end

  def write_schema(dir)
    File.write(File.join(dir, "base.parg"), base_source)
    File.write(File.join(dir, "main.parg"), main_source)
  end

  def compile_main(dir)
    document = Parsanol::PARG::Parser.new(File.read(File.join(dir, "main.parg"))).parse
    Parsanol::PARG::Imports.merge!(document, [dir])
    Parsanol::PARG::Compiler.compile(document, tables_dir: dir)
  end

  it "resolves imports on the in-memory surface via imports_dir" do
    Dir.mktmpdir do |dir|
      write_schema(dir)
      envelope = JSON.generate(compile_main(dir).envelope)
      artifact = Parsanol::PARG::Artifact.from_json(envelope, imports_dir: dir)
      bound = artifact.parse("c", "xy", mode: :ruby)
      expect(bound.keys).to contain_exactly(:b, :c)
      expect(bound[:c].to_s).to eq("y")
    end
  end

  it "resolves imports when the imported .parg sits beside the artifact" do
    Dir.mktmpdir do |dir|
      write_schema(dir)
      File.write(File.join(dir, "main.json"),
                 JSON.generate(compile_main(dir).envelope))
      artifact = Parsanol::PARG::Artifact.load(File.join(dir, "main.json"))
      bound = artifact.parse("c", "xy", mode: :ruby)
      expect(bound.keys).to contain_exactly(:b, :c)
      expect(bound[:c].to_s).to eq("y")
    end
  end

  it "runs the embedded test section through the imports_dir surface" do
    Dir.mktmpdir do |dir|
      write_schema(dir)
      envelope = JSON.generate(compile_main(dir).envelope)
      artifact = Parsanol::PARG::Artifact.from_json(envelope, imports_dir: dir)
      expect(artifact.run_tests(mode: :ruby)).to be_empty
    end
  end

  it "fails with the issue's signature when no import directory is given" do
    Dir.mktmpdir do |dir|
      write_schema(dir)
      envelope = JSON.generate(compile_main(dir).envelope)
      artifact = Parsanol::PARG::Artifact.from_json(envelope)
      expect { artifact.parse("c", "xy", mode: :ruby) }
        .to raise_error(Parsanol::PARG::CompileError, /base\.b/)
    end
  end
end
