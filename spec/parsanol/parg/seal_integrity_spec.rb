# frozen_string_literal: true

require "parsanol"
require "json"
require "tmpdir"

# parsanol-ruby#435-format: inline dual integrity. `Compiler.seal_json`
# stamps a byte-exact digest (zero-hole sha256 over the file's own bytes)
# inside the envelope — no sidecar — and `Artifact.from_json/load` verify
# it as the fast tier before the canonical deep tier. The bake receipt
# (`validated`) travels inside the envelope, covered by both digests.
RSpec.describe "inline byte integrity and the validation receipt" do
  def compile_demo
    source = <<~PARG
      grammar Demo version "1.0.0" edition 2 {
        word = 1*( %x41-5A / %x61-7A )
        digit = 1*( %x30-39 )
        marker = ( "!" ) as bang
        identifier = ( ( word ) as code [ ( "-" ( digit ) as revision ) ] )
        entry identifier: identifier
        bindings identifier {
          code -> code (string)
          revision -> revision (string)
        }
        test {
          accept "AB-3"
        }
      }
    PARG
    Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse)
  end

  def write_sealed(dir, name, envelope)
    path = File.join(dir, name)
    File.write(path, Parsanol::PARG::Compiler.seal_json(envelope.envelope), encoding: Encoding::UTF_8)
    path
  end

  describe "the validated receipt" do
    it "records what the bake checked, inside the envelope" do
      envelope = compile_demo.envelope
      expect(envelope["validated"]).to include(
        "lint_errors" => 0,
        "lint_warnings" => a_value >= 0,
        "tests_total" => 1,
        "tests_failures" => 0,
      )
      expect(envelope["validated"]["self_test"]).to be(true).or be(false)
    end

    it "is covered by the canonical checksum (tamper is rejected)" do
      envelope = compile_demo.envelope
      tampered = deep_dup(envelope)
      tampered["validated"]["tests_failures"] = 99
      tampered.delete("byte_checksum")

      expect do
        Parsanol::PARG::Artifact.from_json(JSON.generate(tampered))
      end.to raise_error(Parsanol::PARG::ArtifactError, /checksum mismatch/)
    end
  end

  describe "the byte checksum" do
    it "seals deterministically and loads through the fast tier" do
      compiled = compile_demo
      text_a = Parsanol::PARG::Compiler.seal_json(compiled.envelope)
      text_b = Parsanol::PARG::Compiler.seal_json(compiled.envelope)
      expect(text_a).to eq(text_b)

      envelope = JSON.parse(text_a)
      expect(envelope["byte_checksum"]).to match(%r{\Asha256:[0-9a-f]{64}\z})
      expect(text_a).to include(envelope["byte_checksum"])

      Dir.mktmpdir do |dir|
        path = File.join(dir, "sealed.json")
        File.write(path, text_a)
        expect { Parsanol::PARG::Artifact.load(path) }.not_to raise_error
      end
    end

    it "rejects any flipped byte before parse work" do
      compiled = compile_demo
      sealed = Parsanol::PARG::Compiler.seal_json(compiled.envelope)
      # Flip one byte inside the source payload (not the digest region).
      tampered = sealed.sub('"source":"', '"source ":"')
      expect(tampered).not_to eq(sealed)

      expect do
        Parsanol::PARG::Artifact.from_json(tampered)
      end.to raise_error(
        Parsanol::PARG::ArtifactError,
        /byte checksum mismatch.*not the .*sealed bake output/m,
      )
    end

    it "keeps the byte digest out of the canonical payload (parity)" do
      compiled = compile_demo
      sealed = JSON.parse(Parsanol::PARG::Compiler.seal_json(compiled.envelope))
      # The same content re-serialized by a different producer would have
      # a different byte digest; the canonical checksum must be identical.
      resealed = deep_dup(sealed)
      resealed["byte_checksum"] = "sha256:#{'f' * 64}"

      expect(Parsanol::PARG::Compiler.checksum(resealed))
        .to eq(Parsanol::PARG::Compiler.checksum(sealed))
      expect(Parsanol::PARG::Compiler.checksum(sealed))
        .to eq(compiled.envelope["checksum"])
    end
  end

  describe "old artifacts (no byte checksum)" do
    it "load through the canonical tier unchanged" do
      compiled = compile_demo
      legacy = deep_dup(compiled.envelope)
      legacy.delete("byte_checksum")

      expect do
        Parsanol::PARG::Artifact.from_json(JSON.generate(legacy))
      end.not_to raise_error
    end
  end

  def deep_dup(obj)
    JSON.parse(JSON.generate(obj))
  end
end
