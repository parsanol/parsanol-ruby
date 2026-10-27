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
    dir = ENV.fetch("PARG_CONFORMANCE_DIR", nil)
    # The env var is set unconditionally by CI, but the corpus checkout
    # may predate the corpus landing (parsanol-rs#234 merged after the
    # first ruby run checked out rs main). Absent corpus = skip, not
    # fail: the gate enforces when present.
    return Pathname.new(dir) if dir && File.directory?(dir)

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

  # Parity view: provenance fields are excluded. compiler_version is
  # stamped from Parsanol::VERSION, so every gem release legitimately
  # changes it (and the checksum covering it) — parity binds the
  # artifact to its SOURCE via source_hash, not to a compiler build.
  # unicode_tables is the same class of stamp (U3): the compiling
  # engine names its Unicode table source, and it moves with the
  # runner's ruby, not with the grammar.
  def parity_view(envelope)
    envelope.except("compiler_version", "checksum", "unicode_tables")
  end

  it "compile-parity: recompiling each .parg reproduces the committed envelope" do
    skip unless corpus
    # Dir.children, not Dir.glob: the CI env path carries backslashes,
    # which Dir.glob treats as escapes on Windows (the gate passed
    # vacuously there once already).
    # A .parg without a sibling .json is an import helper - it exists
    # to be referenced via `use` (resolved against its file name) and
    # has no artifact of its own. `use` grammars merge imports from
    # the corpus dir before compiling, mirroring the authoring flow.
    pargs = Dir.children(corpus.to_s)
      .select { |f| f.end_with?(".parg") && File.file?(corpus.join(f.sub(/\.parg\z/, ".json"))) }
      .sort
    expect(pargs).not_to be_empty, "conformance corpus has no .parg cases"
    pargs.each do |file|
      parg = corpus.join(file)
      name = File.basename(file, ".parg")
      committed = JSON.parse(File.read(corpus.join("#{name}.json")))
      document = Parsanol::PARG::Parser.new(File.read(parg)).parse
      Parsanol::PARG::Imports.merge!(document, [corpus.to_s])
      compiled = Parsanol::PARG::Compiler.new(document, corpus.to_s).compile.envelope
      expect(JSON.generate(parity_view(compiled))).to eq(JSON.generate(parity_view(committed))),
                                                      "#{name}: compiler drift — recompilation differs from the committed artifact"
    end
  end

  # imports_dir lets `use`-carrying sources rebuild on the Ruby path;
  # merge! is a no-op for grammars without `use`.
  def load_artifact(json)
    Parsanol::PARG::Artifact.from_json(
      File.read(json), tables_dir: corpus.to_s, imports_dir: corpus.to_s
    )
  end

  it "native engine: every embedded test section passes" do
    skip unless corpus
    Dir.glob(corpus.join("*.json")).each do |json|
      name = File.basename(json, ".json")
      failures = load_artifact(json).run_tests(mode: :native)
      expect(failures).to be_empty, "#{name}: native failures: #{failures.inspect}"
    end
  end

  it "Ruby engine: every embedded test section passes" do
    skip unless corpus
    Dir.glob(corpus.join("*.json")).each do |json|
      name = File.basename(json, ".json")
      failures = load_artifact(json).run_tests(mode: :ruby)
      expect(failures).to be_empty, "#{name}: Ruby failures: #{failures.inspect}"
    end
  end
end
