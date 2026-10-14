# frozen_string_literal: true

require "spec_helper"
require "json"

# parsanol-ts#5: artifact provenance — a stale artifact (compiled from
# an older .parg revision) used to be undetectable at load time. The
# envelope now embeds the source text's SHA-256 and the compiler
# version, both inside the checksum, and the load API exposes them
# with a compiled_from? freshness check.
RSpec.describe "Parsanol::PARG::Artifact provenance" do
  let(:grammar_source) do
    <<~PARG
      grammar Provenance version "1.0" {
        word = 1*( ALPHA )
        entry main: word
      }
    PARG
  end

  let(:envelope) do
    document = Parsanol::PARG::Parser.new(grammar_source).parse
    Parsanol::PARG::Compiler.new(document, nil).compile.envelope
  end

  let(:artifact) do
    Parsanol::PARG::Artifact.new(JSON.parse(JSON.generate(envelope)), nil, nil)
  end

  it "embeds the source hash and compiler version inside the checksum" do
    expect(artifact.source_hash)
      .to eq("sha256:#{Digest::SHA256.hexdigest(grammar_source)}")
    expect(artifact.compiler_version).to eq(Parsanol::VERSION)
    expect(artifact.source).to eq(grammar_source)
    # the fields are checksum-covered: a verifier recomputes over the
    # whole envelope minus "checksum", so tampering with either field
    # breaks the load
    tampered = JSON.parse(JSON.generate(envelope))
    tampered["source_hash"] = "sha256:#{"0" * 64}"
    tampered["checksum"] = Parsanol::PARG::Compiler.checksum(tampered)
    expect(tampered["checksum"]).not_to eq(envelope["checksum"])
  end

  it "answers compiled_from? for the current and stale revisions" do
    expect(artifact.compiled_from?(grammar_source)).to be(true)
    expect(artifact.compiled_from?(grammar_source.sub("1*(", "2*("))).to be(false)
  end

  it "reports pre-provenance artifacts as unverifiable, not stale" do
    env = JSON.parse(JSON.generate(envelope))
    env.delete("source_hash")
    env["checksum"] = Parsanol::PARG::Compiler.checksum(env)
    legacy = Parsanol::PARG::Artifact.new(env, nil, nil)
    expect(legacy.source_hash).to be_nil
    expect(legacy.compiled_from?(grammar_source)).to be_nil
  end

  it "exposes the wire-format shape" do
    expect(artifact.shape).to eq("parsanol-tree/v2")
  end

  it "round-trips through from_json with the fields intact" do
    loaded = Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
    expect(loaded.compiler_version).to eq(Parsanol::VERSION)
    expect(loaded.compiled_from?(grammar_source)).to be(true)
  end
end
