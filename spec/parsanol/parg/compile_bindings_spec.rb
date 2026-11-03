# frozen_string_literal: true

require "parsanol"
require "stringio"
require "tmpdir"
require "json"

# parsanol-ruby#432: `parg compile --bindings TARGET` — the bake surface
# for the declared per-target binding artifacts. One checksummed
# bindings payload per target, written beside the artifact; `all`
# expands to the full target set.
RSpec.describe "parg compile --bindings" do
  def compile_with(*flags)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "g.parg")
      File.write(path, <<~PARG)
        grammar Demo version "1.0.0" edition 2 {
          word = 1*( %x41-5A / %x61-7A )
          digit = 1*( %x30-39 )
          identifier = ( ( word ) as code [ ( "-" ( digit ) as revision ) ] )
          entry identifier: identifier
          bindings identifier {
            code -> code (string)
            revision -> revision (string)
          }
        }
      PARG
      $stdout = StringIO.new
      begin
        # The CLI writes -o targets relative to the working directory;
        # run inside the tmpdir so outputs land where the assertions read.
        status = Dir.chdir(dir) do
          Parsanol::PARG::CLI.new(["compile", path, *flags]).run
        end
        outputs = Dir.glob(File.join(dir, "*.json")).to_h do |file|
          [File.basename(file), JSON.parse(File.read(file))]
        end
        [status, $stdout.string, outputs]
      ensure
        $stdout = STDOUT
      end
    end
  end

  it "emits no binding artifacts without the flag" do
    status, _output, outputs = compile_with("-o", "artifact.json")
    expect(status).to eq(0)
    expect(outputs.keys).to eq(["artifact.json"])
  end

  it "emits one verified payload per requested target" do
    status, output, outputs = compile_with("-o", "artifact.json", "--bindings", "ts")
    expect(status).to eq(0)
    expect(outputs.keys).to contain_exactly("artifact.json", "artifact.bindings.ts.json")

    artifact = Parsanol::PARG::Bindings::Artifact.from_json(
      JSON.generate(outputs.fetch("artifact.bindings.ts.json")), target: "ts"
    )
    expect(artifact.target).to eq("ts")
    expect(artifact.bindings("identifier").map { |r| [r["capture"], r["path"]] }).to eq(
      [["code", "code"], ["revision", "revision"]],
    )
    expect(output).to include("artifact.bindings.ts.json  sha256:")
  end

  it "expands --bindings all to the full target set" do
    _status, _output, outputs = compile_with("--bindings", "all")
    expect(outputs.keys).to contain_exactly(
      "g.artifact.json",
      "g.artifact.bindings.ruby.json",
      "g.artifact.bindings.rs.json",
      "g.artifact.bindings.ts.json",
      "g.artifact.bindings.python.json",
    )
    Parsanol::PARG::Bindings::Artifact::TARGETS.each do |target|
      expect do
        Parsanol::PARG::Bindings::Artifact.from_json(
          JSON.generate(outputs.fetch("g.artifact.bindings.#{target}.json")), target: target
        )
      end.not_to raise_error
    end
  end

  it "rejects an unknown target" do
    status, _output, outputs = compile_with("--bindings", "wasm")
    # The compile itself succeeds (the artifact is written); the
    # unknown target raises at emission and the run exits 1 with the
    # fix named.
    expect(status).to eq(1)
    expect(outputs.keys).to eq(["g.artifact.json"])
    # The unknown target raises at emission; the CLI surfaces the error
    # through the run's normal error handling (the compile itself is
    # untouched), so assert via a direct emission here.
    envelope = outputs.fetch("g.artifact.json")
    expect do
      Parsanol::PARG::Bindings::Artifact.emit(envelope, "wasm")
    end.to raise_error(Parsanol::PARG::ArtifactError, /unknown binding target "wasm"/)
  end
end
