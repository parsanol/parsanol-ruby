# frozen_string_literal: true

require "parsanol"
require "stringio"
require "tmpdir"
require "json"

# F9 v1.1 (rs#147 ruling + grow-with-minor): the declarative
# preprocessing vocabulary gains const_map, default_when_absent, and
# rename beside table_lookup; artifacts using a post-v1 op declare
# binding_version 2 so engines that only know v1 refuse loudly.
RSpec.describe "PARG preprocess v1.1" do
  describe "Parser" do
    def document_with_preprocess(block)
      Parsanol::PARG::Parser.new(<<~PARG).parse
                grammar Demo version "1.0.0" edition "v2" {
                  letter = %x41-5A
                  main = letter as code
                  entry main: main
                }

                preprocess steps {
        #{block}
                }
      PARG
    end

    it "parses table_lookup (v1, unchanged)" do
      document = document_with_preprocess("  table_lookup stages abbr -> code")
      expect(document.preprocess["steps"]).to eq(
        [{ "op" => "table_lookup", "table" => "stages", "from" => "abbr", "to" => "code" }],
      )
    end

    it "parses const_map pairs" do
      document = document_with_preprocess(
        '  const_map "draft" -> "Draft", "international-standard" -> "Full standard", WD -> "working-draft"',
      )
      expect(document.preprocess["steps"]).to eq(
        [{ "op" => "const_map", "pairs" => { "draft" => "Draft", "international-standard" => "Full standard", "WD" => "working-draft" } }],
      )
    end

    it "parses default_when_absent" do
      document = document_with_preprocess('  default_when_absent "UNKNOWN"')
      expect(document.preprocess["steps"]).to eq(
        [{ "op" => "default_when_absent", "value" => "UNKNOWN" }],
      )
    end

    it "parses rename" do
      document = document_with_preprocess("  rename sub -> supplement")
      expect(document.preprocess["steps"]).to eq(
        [{ "op" => "rename", "from" => "sub", "to" => "supplement" }],
      )
    end

    it "rejects an unknown op" do
      source = <<~PARG
        grammar Demo version "1.0.0" edition "v2" {
          letter = %x41-5A
          main = letter as code
          entry main: main
        }

        preprocess steps {
          gsub_value "x" -> "y"
        }
      PARG
      expect { Parsanol::PARG::Parser.new(source).parse }
        .to raise_error(Parsanol::PARG::ParseError, /unknown preprocess op/)
    end
  end

  describe "Preprocess.apply" do
    def apply(step, value, source: nil)
      Parsanol::PARG::Preprocess.apply(step, value, source)
    end

    it "maps through const_map and passes unmapped values through" do
      step = { "op" => "const_map", "pairs" => { "draft" => "Draft" } }
      expect(apply(step, "draft")).to eq("Draft")
      expect(apply(step, "mystery")).to eq("mystery")
    end

    it "fills absent data: a top nil, and nil members of hash values" do
      step = { "op" => "default_when_absent", "value" => "-" }
      expect(apply(step, nil)).to eq("-")
      expect(apply(step, { "sub" => nil, "code" => "DIS" }))
        .to eq({ "sub" => "-", "code" => "DIS" })
      expect(apply(step, { "sub" => "A", "code" => "DIS" }))
        .to eq({ "sub" => "A", "code" => "DIS" })
      expect(apply(step, "")).to eq("")
      expect(apply(step, "x")).to eq("x")
    end

    it "renames the hash key in place and leaves other values alone" do
      step = { "op" => "rename", "from" => "sub", "to" => "supplement" }
      expect(apply(step, { "sub" => "A", "code" => "DIS" }))
        .to eq({ "supplement" => "A", "code" => "DIS" })
      expect(apply(step, { "code" => "DIS" })).to eq({ "code" => "DIS" })
      expect(apply(step, "scalar")).to eq("scalar")
    end
  end

  describe "binding_version (grow-with-minor)" do
    def compiled_envelope(preprocess_block, bindings_block)
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "stages.yaml"), <<~YAML)
          - abbr: DIS
            code: draft
          - abbr: IS
            code: international-standard
        YAML
        path = File.join(dir, "g.parg")
        File.write(path, <<~PARG)
                    grammar Demo version "1.0.0" edition "v2" {
                      stage_abbr = alt from_table "stages" column "abbr"
                      optional = [ "-" stage_abbr as sub ]
                      main = stage_abbr as code optional
                      entry main: main

                      bindings main {
          #{bindings_block}
                      }

                      preprocess chain {
          #{preprocess_block}
                      }
                    }
        PARG
        output = File.join(dir, "g.json")
        $stdout = StringIO.new
        begin
          Dir.chdir(dir) do
            Parsanol::PARG::CLI.new(["compile", path, "-o", output]).run
          end
        ensure
          $stdout = STDOUT
        end
        JSON.parse(File.read(output))
      end
    end

    it "stays 1 for v1-only preprocess" do
      envelope = compiled_envelope(
        "    table_lookup stages abbr -> code",
        "    code -> code (string) preprocess: chain",
      )
      expect(envelope["binding_version"]).to eq(1)
    end

    it "is 2 when any post-v1 op is used" do
      envelope = compiled_envelope(
        "    table_lookup stages abbr -> code\n    const_map \"draft\" -> \"Draft\"",
        "    code -> code (string) preprocess: chain",
      )
      expect(envelope["binding_version"]).to eq(2)
    end
  end

  describe "artifact load" do
    it "refuses a binding_version this runtime does not know" do
      envelope = {
        "shape" => Parsanol::PARG::Artifact::SUPPORTED_SHAPE,
        "binding_version" => 3,
      }
      expect { Parsanol::PARG::Artifact.from_json(JSON.generate(envelope)) }
        .to raise_error(Parsanol::PARG::ArtifactError, /binding_version/)
    end

    it "accepts the shipped levels" do
      [1, 2, nil].each do |version|
        envelope = {
          "shape" => Parsanol::PARG::Artifact::SUPPORTED_SHAPE,
          "binding_version" => version,
        }.compact
        envelope["checksum"] = Parsanol::PARG::Compiler.checksum(envelope)
        expect { Parsanol::PARG::Artifact.from_json(JSON.generate(envelope)) }
          .not_to raise_error
      end
    end
  end
end
