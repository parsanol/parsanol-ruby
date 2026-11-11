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

    it "parses const_map pairs as sequential steps" do
      document = document_with_preprocess(
        '  const_map "draft" -> "Draft", "international-standard" -> "Full standard", WD -> "working-draft"',
      )
      expect(document.preprocess["steps"]).to eq(
        [
          { "op" => "const_map", "table" => "", "from" => "draft", "to" => "Draft" },
          { "op" => "const_map", "table" => "", "from" => "international-standard", "to" => "Full standard" },
          { "op" => "const_map", "table" => "", "from" => "WD", "to" => "working-draft" },
        ],
      )
    end

    it "parses default_when_absent" do
      document = document_with_preprocess('  default_when_absent "UNKNOWN"')
      expect(document.preprocess["steps"]).to eq(
        [{ "op" => "default_when_absent", "table" => "", "from" => "", "to" => "UNKNOWN" }],
      )
    end

    it "parses rename" do
      document = document_with_preprocess("  rename sub -> supplement")
      expect(document.preprocess["steps"]).to eq(
        [{ "op" => "rename", "table" => "", "from" => "sub", "to" => "supplement" }],
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
      step = { "op" => "const_map", "table" => "", "from" => "draft", "to" => "Draft" }
      expect(apply(step, "draft")).to eq("Draft")
      expect(apply(step, "mystery")).to eq("mystery")
    end

    it "fills absent data: a top nil, and nil members of hash values" do
      step = { "op" => "default_when_absent", "table" => "", "from" => "", "to" => "-" }
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
            Parsanol::PARG::CLI.new(["compile", path, "--tables", dir, "-o", output]).run
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

  describe "parse_and_bind end to end (ruby#487)" do
    # The Bindings.apply path must dispatch through the Preprocess
    # registry: a grammar that compiles green must also BIND green.
    # ruby#487: the inline table_lookup case in Bindings shadowed the
    # registry, so v1.1 ops raised unknown-op at first bind while the
    # rs/wasm executor applied them.
    def bound_artifact
      Dir.mktmpdir do |dir|
        path = File.join(dir, "g.parg")
        File.write(path, <<~PARG)
          grammar Demo version "1.0.0" edition "v2" {
            publisher = %i"ISO" / %i"IEEE"
            digit = 1*( %x30-39 )
            identifier = ( ( publisher ) as publisher ) ":" ( digit as number )
            entry identifier: identifier

            bindings identifier {
              publisher -> publisher (string) preprocess: stage_code
              number -> number (integer)
            }

            preprocess stage_code {
              const_map "ISO" -> "iso", "IEEE" -> "ieee"
            }
          }
        PARG
        output = File.join(dir, "g.json")
        $stdout = StringIO.new
        begin
          Dir.chdir(dir) do
            Parsanol::PARG::CLI.new(["compile", path, "--tables", dir, "-o", output]).run
          end
        ensure
          $stdout = STDOUT
        end
        Parsanol::PARG::Artifact.from_json(File.read(output))
      end
    end

    it "applies const_map at bind time" do
      artifact = bound_artifact
      # parse_and_bind returns symbol-keyed hashes (the leaf-key contract).
      expect(artifact.parse_and_bind("identifier", "ISO:42"))
        .to eq({ publisher: "iso", number: 42 })
      expect(artifact.parse_and_bind("identifier", "IEEE:7"))
        .to eq({ publisher: "ieee", number: 7 })
    end

    it "applies the full v1.1 chain at bind time" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "stages.yaml"), <<~YAML)
          - abbr: DIS
            code: draft
        YAML
        path = File.join(dir, "g.parg")
        File.write(path, <<~PARG)
          grammar Demo version "1.0.0" edition "v2" {
            letter = %x41-5A
            stage_abbr = alt from_table "stages" column "abbr"
            optional = [ "-" ( letter as letter ) ] as optional
            main = stage_abbr as code optional
            entry main: main

            bindings main {
              code -> code (string) preprocess: resolve
              optional -> supplement (raw) preprocess: align
            }

            preprocess resolve {
              table_lookup stages abbr -> code
              const_map "draft" -> "Draft"
            }

            preprocess align {
              default_when_absent "-"
              rename letter -> part
            }
          }
        PARG
        output = File.join(dir, "g.json")
        $stdout = StringIO.new
        begin
          Dir.chdir(dir) do
            Parsanol::PARG::CLI.new(["compile", path, "--tables", dir, "-o", output]).run
          end
        ensure
          $stdout = STDOUT
        end
        # The from_table rule resolves rows from the artifact's dir at
        # the ruby-tier re-compile (pre-existing v1 behavior; the
        # envelope's embedded rows feed the engine tiers).
        artifact = Parsanol::PARG::Artifact.from_json(File.read(output), tables_dir: dir)
        # table_lookup -> const_map on the code; the absent optional
        # binds nothing (the null-capture contract). The present case
        # exercises the full chain: default fills the nil member of the
        # group hash, then rename aligns the key.
        expect(artifact.parse_and_bind("main", "DIS"))
          .to eq({ code: "Draft" })
        expect(artifact.parse_and_bind("main", "DIS-A"))
          .to eq({ code: "Draft", supplement: { part: "A" } })
      end
    end
  end
end
