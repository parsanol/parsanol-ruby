# frozen_string_literal: true

require "parsanol/parg"

# The semantics hash (parsanol-ruby#377): a behavior fingerprint beside
# the checksum. The checksum pins the exact producer — every gem release
# legitimately re-bakes every artifact. The semantics hash skips producer
# metadata, so freshness gates can tell "re-baked by a newer compiler"
# from "the grammar's behavior changed".
RSpec.describe "the PARG envelope semantics hash (ruby#377)" do
  let(:source) do
    <<~PARG
      grammar Fresh version "1.0" {
        w = "x" as w
        entry w: w
      }
    PARG
  end

  def compile_envelope(source_text = source)
    document = Parsanol::PARG::Parser.new(source_text).parse
    Parsanol::PARG::Compiler.compile(document).envelope
  end

  it "ships beside the checksum in every compiled envelope" do
    envelope = compile_envelope
    expect(envelope["semantics_hash"]).to match(/\Asha256:[0-9a-f]{64}\z/)
    expect(envelope["checksum"]).to match(/\Asha256:[0-9a-f]{64}\z/)
    expect(envelope["semantics_hash"]).not_to eq(envelope["checksum"])
  end

  it "is deterministic for the same source" do
    first = compile_envelope
    second = compile_envelope
    expect(first["semantics_hash"]).to eq(second["semantics_hash"])
  end

  it "survives producer-metadata churn that changes the checksum" do
    envelope = compile_envelope
    rebaked = envelope.merge(
      "compiler_version" => "9.9.999",
      "unicode_tables" => "onigmo (Ruby 9.9.9)",
    )
    expect(Parsanol::PARG::Compiler.semantics_hash(rebaked)).to eq(envelope["semantics_hash"])
    expect(Parsanol::PARG::Compiler.checksum(rebaked)).not_to eq(envelope["checksum"])
  end

  it "changes when the grammar's behavior changes" do
    changed = compile_envelope(source.sub('"x"', '"y"'))
    expect(changed["semantics_hash"]).not_to eq(compile_envelope["semantics_hash"])
  end

  describe "the artifact reader" do
    it "exposes the field and stays nil for pre-377 artifacts" do
      envelope = compile_envelope
      artifact = Parsanol::PARG::Artifact.new(envelope, nil, nil)
      expect(artifact.semantics_hash).to eq(envelope["semantics_hash"])

      legacy_envelope = envelope.except("semantics_hash")
      legacy_envelope["checksum"] = Parsanol::PARG::Compiler.checksum(legacy_envelope)
      legacy = Parsanol::PARG::Artifact.new(legacy_envelope, nil, nil)
      expect(legacy.semantics_hash).to be_nil
    end
  end
end
