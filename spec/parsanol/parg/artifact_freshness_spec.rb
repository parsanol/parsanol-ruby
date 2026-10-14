# frozen_string_literal: true

require "parsanol/parg"
require "digest"

# Freshness (parsanol-ruby#209): artifacts record what source revision and
# compiler produced them, so loaders can detect a stale artifact and fall
# back to a reference implementation instead of failing obscurely at parse
# time.
RSpec.describe Parsanol::PARG::Artifact do
  let(:source) do
    <<~PARG
      grammar Fresh version "1.0" {
        w = "x" as w
        entry w: w
      }
    PARG
  end

  def compile_artifact
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(document).envelope
  end

  it "records the SHA-256 of the source and the compiler version" do
    envelope = compile_artifact
    expect(envelope["source_hash"]).to eq(Digest::SHA256.hexdigest(source))
    expect(envelope["compiler_version"]).to eq(Parsanol::VERSION)
  end

  it "checksums the freshness fields with the envelope" do
    envelope = compile_artifact
    expect { Parsanol::PARG::Artifact.new(envelope, nil, nil) }.not_to raise_error
    tampered = envelope.merge("source_hash" => "0" * 64)
    expect { Parsanol::PARG::Artifact.new(tampered, nil, nil) }
      .to raise_error(Parsanol::PARG::ArtifactError)
  end

  describe "#fresh_against?" do
    it "is true for the source it was compiled from" do
      artifact = Parsanol::PARG::Artifact.new(compile_artifact, nil, nil)
      expect(artifact.fresh_against?(source)).to be(true)
    end

    it "is false for a different source" do
      artifact = Parsanol::PARG::Artifact.new(compile_artifact, nil, nil)
      expect(artifact.fresh_against?(source.sub('"x"', '"y"'))).to be(false)
    end

    it "is false for pre-freshness artifacts rather than guessing" do
      envelope = compile_artifact
      envelope.delete("source_hash")
      envelope["checksum"] = Parsanol::PARG::Compiler.checksum(envelope)
      artifact = Parsanol::PARG::Artifact.new(envelope, nil, nil)
      expect(artifact.source_hash).to be_nil
      expect(artifact.fresh_against?(source)).to be(false)
    end
  end
end
