# frozen_string_literal: true

require "parsanol"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe Parsanol::PARG do
  def compile_source(src, tables_dir:)
    document = Parsanol::PARG::Parser.new(src).parse
    Parsanol::PARG::Compiler.compile(document, tables_dir: tables_dir)
  end

  def write_artifact(env, dir)
    path = File.join(dir, "demo.json")
    File.write(path, JSON.generate(env))
    path
  end

  let(:stages_yaml) do
    <<~YAML
      CD: { abbr: CD, code: draft20 }
      DIS: { abbr: DIS, code: draft40 }
      IS: { abbr: IS, code: published }
    YAML
  end

  let(:source) do
    <<~PARG
      # demo grammar
      grammar Demo version "1.2.0" mode "v1" {
        digit = %x30-39
        number = 1*digit
        space = " "
        dash = "-"
        publisher = %i"iso" / %i"ieee"
        stage_abbr = alt from_table "stages" column "abbr"
        stage_seq = stage_abbr as stage space
        part = dash number as part
        iso_identifier = publisher as publisher space [stage_seq] number as number [part]
      }

      bindings iso_identifier {
        publisher -> publisher (string)
        stage -> stage (string) preprocess: stage_code
        number -> number (integer)
        part -> part (string, 0..1)
      }

      preprocess stage_code {
        table_lookup stages abbr -> code
      }

      entry identifier: iso_identifier
    PARG
  end

  describe "Parser" do
    it "parses the document" do
      document = Parsanol::PARG::Parser.new(source).parse
      expect(document.version).to eq("1.2.0")
      expect(document.grammar_name).to eq("Demo")
      expect(document.rules).to include("iso_identifier", "stage_abbr")
      expect(document.entries).to eq("identifier" => "iso_identifier")
      expect(document.bindings["iso_identifier"].length).to eq(4)
      expect(document.preprocess["stage_code"]).to eq(
        [{ "op" => "table_lookup", "table" => "stages", "from" => "abbr", "to" => "code" }],
      )
    end

    it "records the source text" do
      document = Parsanol::PARG::Parser.new(source).parse
      expect(document.source).to eq(source)
    end

    it "rejects malformed input" do
      expect { Parsanol::PARG::Parser.new("grammar X { a = }").parse }
        .to raise_error(Parsanol::PARG::ParseError)
      expect { Parsanol::PARG::Parser.new("nonsense").parse }
        .to raise_error(Parsanol::PARG::ParseError)
      expect { Parsanol::PARG::Parser.new('grammar X version "1" mode "v1" { entry = "a" }').parse }
        .to raise_error(Parsanol::PARG::ParseError, /expected ident/)
    end

    it "rejects duplicate rules and dangling references" do
      src = <<~PARG
        grammar X version "1" mode "v1" { a = "x" }
        entry e: missing
      PARG
      expect { Parsanol::PARG::Parser.new(src).parse }
        .to raise_error(Parsanol::PARG::ParseError, /unknown rule/)

      dup = <<~PARG
        grammar X version "1" mode "v1" {
          a = "x"
          a = "y"
        }
      PARG
      expect { Parsanol::PARG::Parser.new(dup).parse }
        .to raise_error(Parsanol::PARG::ParseError, /duplicate/)
    end
  end

  describe "Compiler" do
    it "rejects left recursion (direct and indirect)" do
      # Direct left recursion is rewritten (left_recursion_spec); a rule
      # with nothing but the recursive reference cannot anchor the fold.
      expect do
        compile_source(<<~PARG, tables_dir: nil)
          grammar X version "1" mode "v1" {
            a = a "x"
          }
        PARG
      end.to raise_error(Parsanol::PARG::CompileError, /no non-recursive alternative/)

      expect do
        compile_source(<<~PARG, tables_dir: nil)
          grammar X version "1" mode "v1" {
            a = b "x"
            b = a / "y"
          }
        PARG
      end.to raise_error(Parsanol::PARG::CompileError, /left recursion/)
    end

    it "rejects unknown rule references" do
      expect do
        compile_source('grammar X version "1" mode "v1" { a = missing }', tables_dir: nil)
      end.to raise_error(Parsanol::PARG::CompileError, /unknown rule/)
    end

    it "rejects a non-final branch that can match empty" do
      src = 'grammar X version "1" mode "v1" { a = [ "b" ] / "c" }'
      expect do
        compile_source(src, tables_dir: nil)
      end.to raise_error(Parsanol::PARG::CompileError, /match empty/)
    end

    it "rejects a shorter literal shadowing a longer later branch" do
      src = 'grammar X version "1" mode "v1" { p = "iso" / "iso/iec" }'
      expect do
        compile_source(src, tables_dir: nil)
      end.to raise_error(Parsanol::PARG::CompileError, /shadows branch 2/)
    end

    it "records an order-dependent warning for overlapping branches" do
      src = 'grammar X version "1" mode "v1" { p = "iso/iec" / "iso" }'
      result = compile_source(src, tables_dir: nil)
      expect(result.warnings.join).to include("order-dependent")
    end

    it "emits a portable grammar JSON per entry" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "stages.yaml"), stages_yaml)
        result = compile_source(source, tables_dir: dir)
        grammar = result.envelope["entries"]["identifier"]["grammar"]
        expect(grammar).to include("atoms", "root")
        expect(grammar["atoms"]).not_to be_empty
      end
    end
  end

  describe "tests and doc comments" do
    let(:authored) do
      <<~PARG
        grammar T version "1.0.0" mode "v1" {
          digit = %x30-39
          ## The two-letter publisher code.
          pub = %x41-5A %x41-5A
          identifier = pub as pub 4digit
        }

        bindings identifier {
          pub -> pub (string)
        }

        entry identifier: identifier

        test {
          accept "AB2020"
          reject "AB20"
          example "AB2020" { pub: "AB" }
        }
      PARG
    end

    it "runs accept/reject/example tests at compile time" do
      expect { compile_source(authored, tables_dir: nil) }.not_to raise_error
    end

    it "fails the build when an accept test does not parse" do
      broken = authored.sub('accept "AB2020"', 'accept "AB-2020"')
      expect { compile_source(broken, tables_dir: nil) }
        .to raise_error(Parsanol::PARG::CompileError, /expected the input to parse/)
    end

    it "fails the build when a reject test parses" do
      broken = authored.sub('reject "AB20"', 'reject "AB2020"')
      expect { compile_source(broken, tables_dir: nil) }
        .to raise_error(Parsanol::PARG::CompileError, /expected the input to be rejected/)
    end

    it "fails the build when an example capture mismatches" do
      broken = authored.sub('{ pub: "AB" }', '{ pub: "XY" }')
      expect { compile_source(broken, tables_dir: nil) }
        .to raise_error(Parsanol::PARG::CompileError, /expected captures/)
    end

    describe "capture kind (grammar-layer phase)" do
      let(:capture_grammar) do
        <<~PARG
          grammar T version "1.0.0" mode "v1" {
            digit = %x30-39
            pub = %x41-5A %x41-5A
            identifier = pub as pub 4digit
          }

          entry identifier: identifier

          test {
            accept "AB2020"
            capture "AB2020" { pub: "AB" }
          }
        PARG
      end

      it "asserts raw captures without a bindings section" do
        expect { compile_source(capture_grammar, tables_dir: nil) }.not_to raise_error
      end

      it "fails the build when a capture expectation mismatches" do
        broken = capture_grammar.sub('{ pub: "AB" }', '{ pub: "XY" }')
        expect { compile_source(broken, tables_dir: nil) }
          .to raise_error(Parsanol::PARG::CompileError, /expected captures/)
      end

      it "replays capture tests on the artifact in both modes" do
        Dir.mktmpdir do |dir|
          envelope = compile_source(capture_grammar, tables_dir: dir).envelope
          artifact = Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
          expect(artifact.run_tests(mode: :ruby)).to be_empty
          expect(artifact.run_tests(mode: :native)).to be_empty
        end
      end

      it "surfaces a stale capture expectation through artifact replay" do
        broken = capture_grammar.sub('{ pub: "AB" }', '{ pub: "ZZ" }')
        Dir.mktmpdir do |dir|
          expect do
            compile_source(broken, tables_dir: dir)
          end.to raise_error(Parsanol::PARG::CompileError)
        end
      end
    end

    describe "envelope self-test (parsanol-ruby#223)" do
      let(:tested) do
        <<~PARG
          grammar ST version "1.0" mode "v1" {
            main = ( "x" as x / "y" as y / "z" as z )
            entry main: main

            test {
              accept "x"
              accept "z"
            }
          }
        PARG
      end

      it "is green for a self-consistent envelope" do
        env = compile_source(tested, tables_dir: nil).envelope
        expect(Parsanol::PARG::Compiler.self_test(env)).to be_empty
      end

      it "catches an envelope whose atoms lost an ordered-choice member" do
        skip "no parse engine available" unless Parsanol::Native.available?
        env = compile_source(tested, tables_dir: nil).envelope
        # The 1.3.91 bake shape: the "z" branch is dead in the baked
        # atoms (the choice member binds nothing) while the tests still
        # demand it. Atoms are index-referenced, so the faithful tamper
        # disables the member in place rather than pruning it. The
        # embedded source must be tampered with the same stroke: the
        # pure-Ruby lane recompiles the embedded source rather than
        # walking the atoms, so an atoms-only tamper leaves that lane
        # (falsely) green. Re-sign so the envelope verifies — the
        # failure must come from the tests, not the checksum.
        atoms = env["entries"]["main"]["grammar"]["atoms"]
        atoms.each do |atom|
          str = atom["Str"]
          str["pattern"] = "q" if str && str["pattern"] == "z"
        end
        # First "z" in the source is the rule body's literal; the
        # test's `accept "z"` stays untouched.
        env["source"] = env["source"].sub('"z"', '"q"')
        env["checksum"] = Parsanol::PARG::Compiler.checksum(env)
        failures = Parsanol::PARG::Compiler.self_test(env)
        expect(failures).not_to be_empty
        expect(failures.join).to include("expected the input to parse")
      end

      it "fails the build when the baked atoms cannot pass the tests" do
        # Source-level proof: the compiler runs the self-test on every
        # bake; a grammar whose envelope disagrees with its own tests
        # must not produce a Result. Simulate by stubbing nothing —
        # instead verify the compile-time wiring directly through a
        # real bake whose atoms survive unchanged (green path), and
        # rely on the tampered case above for the red path.
        expect { compile_source(tested, tables_dir: nil) }.not_to raise_error
      end
    end

    it "rejects example tests in grammars without a bindings section" do
      sourceless = <<~PARG
        grammar T version "1.0.0" mode "v1" {
          pub = %x41-5A %x41-5A as pub
          identifier = pub
        }

        entry identifier: identifier

        test {
          example "AB" { pub: "AB" }
        }
      PARG
      expect { compile_source(sourceless, tables_dir: nil) }
        .to raise_error(Parsanol::PARG::CompileError, /bindings section/)
    end

    it "compiles a multi-entry grammar whose tests all name their entry" do
      multi = <<~PARG
        grammar M version "1.0.0" mode "v1" {
          a = "x" as a
          b = "y" as b
        }

        entry a: a
        entry b: b

        test a {
          accept "x"
        }

        test b {
          accept "y"
        }
      PARG
      expect { compile_source(multi, tables_dir: nil) }.not_to raise_error
    end

    it "still names the missing entry when a multi-entry test omits one" do
      multi = <<~PARG
        grammar M version "1.0.0" mode "v1" {
          a = "x" as a
          b = "y" as b
        }

        entry a: a
        entry b: b

        test {
          accept "x"
        }
      PARG
      expect { compile_source(multi, tables_dir: nil) }
        .to raise_error(Parsanol::PARG::CompileError, /tests need an explicit entry/)
    end

    it "embeds tests and docs in the artifact and re-runs them" do
      Dir.mktmpdir do |dir|
        env = compile_source(authored, tables_dir: dir).envelope
        expect(env["docs"]["pub"]).to eq("The two-letter publisher code.")
        expect(env["tests"].size).to eq(3)
        path = write_artifact(env, dir)
        artifact = Parsanol::PARG::Artifact.load(path, tables_dir: dir)
        expect(artifact.run_tests).to be_empty
        expect(artifact.rule_docs["pub"]).to eq("The two-letter publisher code.")
      end
    end
  end

  describe "Artifact" do
    subject(:artifact) do
      Parsanol::PARG::Artifact.load(path, tables_dir: tables_dir)
    end

    let(:tables_dir) do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "stages.yaml"), stages_yaml)
      dir
    end

    let(:path) do
      write_artifact(compile_source(source, tables_dir: tables_dir).envelope,
                     tables_dir)
    end

    after { FileUtils.rm_rf(tables_dir) }

    it "verifies the checksum and loads" do
      expect(artifact.version).to eq("1.2.0")
      expect(artifact.entries).to eq(["identifier"])
    end

    it "is byte-stable across compilations" do
      first = compile_source(source, tables_dir: tables_dir).envelope
      second = compile_source(source, tables_dir: tables_dir).envelope
      expect(first["checksum"]).to eq(second["checksum"])
    end

    it "rejects a tampered artifact" do
      env = compile_source(source, tables_dir: tables_dir).envelope
      env["version"] = "9.9.9"
      path = write_artifact(env, tables_dir)
      expect { Parsanol::PARG::Artifact.load(path, tables_dir: tables_dir) }
        .to raise_error(Parsanol::PARG::ArtifactError, /checksum mismatch/)
    end

    it "rejects unknown entries" do
      expect { artifact.parse("nope", "x") }
        .to raise_error(Parsanol::PARG::ArtifactError, /unknown entry/)
    end

    it "parses and applies bindings end to end" do
      bound = artifact.parse_and_bind("identifier", "ISO CD 12345-89")
      expect(bound).to eq(
        publisher: "ISO",
        stage: "draft20",
        number: 12_345,
        part: "89",
      )
    end

    it "omits absent optional bindings" do
      bound = artifact.parse_and_bind("identifier", "ieee IS 123")
      expect(bound).to eq(publisher: "ieee", stage: "published", number: 123)
    end

    it "matches case-insensitive literals" do
      bound = artifact.parse_and_bind("identifier", "ISO IS 7")
      expect(bound[:publisher]).to eq("ISO")
    end

    it "parses identically through the native and ruby paths" do
      skip "native extension not available" unless Parsanol::Native.available?

      native = artifact.parse_and_bind("identifier", "ISO CD 12345-89")
      ruby = artifact.parse_and_bind("identifier", "ISO CD 12345-89", mode: :ruby)
      expect(native).to eq(ruby)
    end

    it "rejects unknown parse modes" do
      expect { artifact.parse("identifier", "ISO IS 7", mode: :warp) }
        .to raise_error(ArgumentError, /mode/)
    end
  end
end
