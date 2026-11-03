# frozen_string_literal: true

require "parsanol"
require "json"

# The declared per-target binding artifact (parsanol-ruby#432): from one
# compiled grammar the toolchain emits one checksummed bindings artifact
# per target (ruby / rs / ts / python), pinned to its grammar by source
# hash. Declared and diffable, not baked; boundary — AST construction
# records only, semantics live in the model layer, preprocess resources
# resolve from the paired parse artifact.
RSpec.describe Parsanol::PARG::Bindings::Artifact do
  def compiled
    source = <<~PARG
      grammar BindArt version "1.2.0" edition 2 {
        word = 1*( %x41-5A / %x61-7A )
        digit = 1*( %x30-39 )
        part = ( word ) as part_code
        num = ( digit ) as number
        item = ( part [ ( "-" num ) ] )
        identifier = ( ( 1*( item ) ) as items )
        entry identifier: identifier
        bindings identifier {
          part_code -> items[].part_code (string)
          number -> items[].number (string)
        }
      }
    PARG
    envelope = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse).envelope
    Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
  end

  describe "emission" do
    it "emits one artifact per declared target, identical except target and checksum" do
      payloads = described_class::TARGETS.to_h do |target|
        [target, JSON.parse(compiled.bindings_artifact_json(target))]
      end

      expect(payloads.keys).to eq(%w[ruby rs ts python])
      stripped = payloads.transform_values do |payload|
        payload.except("target", "checksum")
      end
      expect(stripped.values.uniq.size).to eq(1)

      base = payloads.fetch("ruby")
      expect(base["artifact_kind"]).to eq("parg-bindings")
      expect(base["grammar"]).to eq("BindArt")
      expect(base["grammar_version"]).to eq("1.2.0")
      expect(base["grammar_source_hash"]).to eq(compiled.source_hash)
      expect(base["binding_version"]).to eq(1)
    end

    it "carries the grammar's declared binding records verbatim" do
      artifact = compiled.bindings_artifact("ruby")
      records = artifact.bindings("identifier")

      expect(records.map { |r| [r["capture"], r["path"], r["type"]] }).to eq(
        [["part_code", "items[].part_code", "string"],
         ["number", "items[].number", "string"]],
      )
    end

    it "rejects an unknown target" do
      expect { compiled.bindings_artifact("wasm") }
        .to raise_error(Parsanol::PARG::ArtifactError, /unknown binding target "wasm"/)
    end
  end

  describe "verification on load" do
    it "round-trips an emitted artifact" do
      json = compiled.bindings_artifact_json("rs")
      artifact = described_class.from_json(json, target: "rs")

      expect(artifact.target).to eq("rs")
      expect(artifact.grammar).to eq("BindArt")
      expect(artifact.grammar_source_hash).to eq(compiled.source_hash)
      expect(artifact.entry_names).to eq(["identifier"])
    end

    it "rejects tampered records (checksum mismatch)" do
      payload = JSON.parse(compiled.bindings_artifact_json("ruby"))
      payload["entries"]["identifier"]["bindings"][0]["path"] = "smuggled"

      expect { described_class.from_json(JSON.generate(payload)) }
        .to raise_error(Parsanol::PARG::ArtifactError, /checksum mismatch/)
    end

    it "rejects a foreign artifact_kind" do
      payload = JSON.parse(compiled.bindings_artifact_json("ruby"))
      payload["artifact_kind"] = "parg-tree"

      expect { described_class.from_json(JSON.generate(payload)) }
        .to raise_error(Parsanol::PARG::ArtifactError, /not a parg-bindings artifact/)
    end

    it "rejects an unsupported binding_version" do
      json = compiled.bindings_artifact_json("ruby")
      payload = JSON.parse(json)
      payload["binding_version"] = 2

      # Re-checksum so ONLY the version check fires, not the checksum one.
      payload["checksum"] = Parsanol::PARG::Compiler.checksum(payload)
      expect { described_class.from_json(JSON.generate(payload)) }
        .to raise_error(Parsanol::PARG::ArtifactError, /unsupported binding_version 2/)
    end

    it "rejects a payload with no entries map" do
      json = compiled.bindings_artifact_json("ruby")
      payload = JSON.parse(json)
      payload.delete("entries")
      payload["checksum"] = Parsanol::PARG::Compiler.checksum(payload)

      expect { described_class.from_json(JSON.generate(payload)) }
        .to raise_error(Parsanol::PARG::ArtifactError, /no entries map/)
    end

    it "pins the expected target on load" do
      json = compiled.bindings_artifact_json("ts")
      expect { described_class.from_json(json, target: "ruby") }
        .to raise_error(Parsanol::PARG::ArtifactError, /targets "ts", not "ruby"/)
    end
  end

  describe "pairing with the parse artifact" do
    it "pairs when grammar, version and source hash all match" do
      expect { compiled.bindings_artifact("ruby").pair_with!(compiled) }
        .not_to raise_error
    end

    it "rejects a pair whose grammar source differs" do
      other_source = <<~PARG
        grammar BindArt version "1.2.0" edition 2 {
          word = 1*( %x41-5A / %x61-7A )
          identifier = ( word )
          entry identifier: identifier
        }
      PARG
      other = Parsanol::PARG::Artifact.from_json(
        JSON.generate(
          Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(other_source).parse).envelope,
        ),
      )
      bindings = compiled.bindings_artifact("ruby")

      expect { bindings.pair_with!(other) }
        .to raise_error(Parsanol::PARG::ArtifactError, /source_hash/)
    end
  end

  describe "apply through the declared artifact" do
    it "produces the same bound map as the artifact's embedded records" do
      artifact = compiled
      bindings = artifact.bindings_artifact("ruby").pair_with!(artifact)

      ["AB-12CD-34", "AB-7", "AB"].each do |input|
        shape = artifact.parse("identifier", input)
        expect(bindings.apply("identifier", shape))
          .to eq(artifact.apply_bindings("identifier", shape))
      end
    end

    it "keeps the phantom-row and sparse contracts through the declared records" do
      artifact = compiled
      bindings = artifact.bindings_artifact("ts").pair_with!(artifact)
      shape = artifact.parse("identifier", "AB-12")

      expect(bindings.apply("identifier", shape)).to eq(
        items: [{ part_code: "AB", number: "12" }],
      )

      # The number capture is absent when its optional group does not
      # fire — the row keeps only the part (rs#370 absence reading).
      sparse = artifact.parse("identifier", "AB")
      expect(bindings.apply("identifier", sparse)).to eq(
        items: [{ part_code: "AB" }],
      )
    end

    it "refuses to apply before pairing" do
      bindings = compiled.bindings_artifact("ruby")

      expect { bindings.apply("identifier", {}) }
        .to raise_error(Parsanol::PARG::ArtifactError, /pair_with! the parse artifact before applying/)
    end
  end
end
