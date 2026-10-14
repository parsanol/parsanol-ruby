# frozen_string_literal: true

require "spec_helper"
require "json"
require "fileutils"

# Cross-engine conformance gate (parsanol-tree/v2): the corpus in
# parsanol-rs (corpus/conformance) pins the observable behavior every
# engine must agree on. This spec walks it three ways:
#
#   1. compile-parity — recompiling each committed .parg with the
#      current compiler reproduces the committed envelope exactly
#      (compiler drift detector)
#   2. native engine — the artifact's embedded test section passes
#   3. Ruby engine — the same tests pass on the pure-Ruby interpreter
#
# The corpus lives in parsanol-rs; point PARG_CONFORMANCE_DIR at it
# when it is not a sibling checkout.
RSpec.describe "PARG conformance corpus" do
  def conformance_dir
    dir = ENV["PARG_CONFORMANCE_DIR"]
    return Pathname.new(dir) if dir

    Pathname.new(__dir__).ascend do |ancestor|
      candidate = ancestor.join("parsanol-rs").join("corpus").join("conformance")
      return candidate if candidate.directory?
    end
    nil
  end

  let(:corpus) { conformance_dir }

  it "is present (set PARG_CONFORMANCE_DIR for the cross-engine gate)" do
    skip "conformance corpus not found (parsanol-rs checkout)" unless corpus
    expect(corpus.join("README.md")).to be_file
  end

  it "compile-parity: recompiling each .parg reproduces the committed envelope" do
    skip unless corpus
    Dir.glob(corpus.join("*.parg")).sort.each do |parg|
      name = File.basename(parg, ".parg")
      committed = JSON.parse(File.read(corpus.join("#{name}.json")))
      document = Parsanol::PARG::Parser.new(File.read(parg)).parse
      compiled = Parsanol::PARG::Compiler.new(document, corpus.to_s).compile.envelope
      expect(JSON.generate(compiled)).to eq(JSON.generate(committed)),
           "#{name}: compiler drift — recompilation differs from the committed artifact"
    end
  end

  it "native engine: every embedded test section passes" do
    skip unless corpus
    Dir.glob(corpus.join("*.json")).sort.each do |json|
      name = File.basename(json, ".json")
      artifact = Parsanol::PARG::Artifact.from_json(File.read(json), tables_dir: corpus.to_s)
      failures = artifact.run_tests(mode: :native)
      expect(failures).to be_empty, "#{name}: native failures: #{failures.inspect}"
    end
  end

  it "Ruby engine: every embedded test section passes" do
    skip unless corpus
    Dir.glob(corpus.join("*.json")).sort.each do |json|
      name = File.basename(json, ".json")
      artifact = Parsanol::PARG::Artifact.from_json(File.read(json), tables_dir: corpus.to_s)
      failures = artifact.run_tests(mode: :ruby)
      expect(failures).to be_empty, "#{name}: Ruby failures: #{failures.inspect}"
    end
  end
end
