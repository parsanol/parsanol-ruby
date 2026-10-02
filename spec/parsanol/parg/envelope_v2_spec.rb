# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Parsanol::PARG::Artifact envelope v2 phase 1" do
  let(:grammar_source) do
    <<~PARG
      grammar Repro version "0.0.1" {
        any_char = %x00-10FFFF
        escape = "\\\\" (("\\"" as dquote) / ("n" as newline))
        raw = 1*(!("\\\\" / "\\"") any_char)
        dq = "\\"" ((*(escape / (raw as run))) as string) "\\""
        entry main: dq
      }
    PARG
  end

  let(:envelope) do
    document = Parsanol::PARG::Parser.new(grammar_source).parse
    Parsanol::PARG::Compiler.new(document, nil).compile.envelope
  end

  let(:artifact) { Parsanol::PARG::Artifact.new(JSON.parse(JSON.generate(envelope)), nil, nil) }

  describe "the bindings section (parsanol-rs#143)" do
    it "validates and exposes a well-formed section" do
      env = JSON.parse(JSON.generate(envelope))
      env["bindings"] = {
        "version" => 1,
        "captures" => { "string" => { "path" => "quoted.body" } },
      }
      env["checksum"] = Parsanol::PARG::Compiler.checksum(env)
      loaded = Parsanol::PARG::Artifact.new(env, nil, nil)
      expect(loaded.bindings.dig("captures", "string", "path")).to eq("quoted.body")
    end

    it "rejects unknown section keys" do
      env = JSON.parse(JSON.generate(envelope))
      env["bindings"] = { "bogus" => 1 }
      env["checksum"] = Parsanol::PARG::Compiler.checksum(env)
      expect { Parsanol::PARG::Artifact.new(env, nil, nil) }
        .to raise_error(Parsanol::PARG::ArtifactError, /unknown keys/)
    end

    it "rejects a capture spec without a path" do
      env = JSON.parse(JSON.generate(envelope))
      env["bindings"] = { "captures" => { "string" => { "card" => "1" } } }
      env["checksum"] = Parsanol::PARG::Compiler.checksum(env)
      expect { Parsanol::PARG::Artifact.new(env, nil, nil) }
        .to raise_error(Parsanol::PARG::ArtifactError, /must declare a string :path/)
    end

    it "bakes through the compiler into the checksummed envelope" do
      document = Parsanol::PARG::Parser.new(grammar_source).parse
      bindings = { "version" => 1, "captures" => { "string" => { "path" => "quoted.body" } } }
      compiled = Parsanol::PARG::Compiler.new(document, nil, bindings: bindings).compile
      baked = Parsanol::PARG::Artifact.from_json(JSON.generate(compiled.envelope))
      expect(baked.bindings.dig("captures", "string", "path")).to eq("quoted.body")
    end
  end

  describe "the flat error wire format (parsanol-rs#145)" do
    it "carries the expected-symbol list out-of-band" do
      diag = artifact.parse_with_diagnostics("main", "\"unterminated")
      expect(diag["ok"]).to be(false)
      expect(diag.keys)
        .to contain_exactly("ok", "offset", "expected", "message", "shape")
      expect(diag["expected"]).to be_an(Array)
    end

    it "pays nothing on success paths" do
      diag = artifact.parse_with_diagnostics("main", "\"hello\"")
      expect(diag["ok"]).to be(true)
      expect(diag["expected"]).to eq([])
      expect(diag["shape"]).not_to be_nil
    end
  end

  describe "shape negotiation (parsanol-rs#146)" do
    it "names the frozen contract on mismatch" do
      env = JSON.parse(JSON.generate(envelope))
      env["shape"] = "parsanol-tree/v3"
      env.delete("checksum")
      expect { Parsanol::PARG::Artifact.new(env, nil, nil) }
        .to raise_error(Parsanol::PARG::ArtifactError, /PARSANOL-SHAPE-v2/)
    end
  end
end
