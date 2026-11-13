# frozen_string_literal: true

require "parsanol"
require "json"
require "tempfile"
require "stringio"

# rs#459 slice 2: `parg generate` — emit a render variant against a
# bound attribute map, generation without a source input. The CLI
# rides the artifact's render spec (the same wire data the Rust/TS
# engines lower); byte-identity is the engine-level gate.
RSpec.describe "PARG generate CLI" do
  def compile_artifact_file(source)
    file = Tempfile.new(["gen", ".parg"])
    file.write(source)
    file.close
    file
  end

  let(:grammar) do
    <<~PARG
      grammar Tag version "1.0.0" {
        entry main: tag
        digit = %x30-39
        number = 1*digit as number
        year = 4*digit as year
        tag = "iso" number [":" year]
      }

      render default {
        literal "TAG-"
        field number
        cond year {
          literal ":"
          field year
        }
      }
    PARG
  end

  def run_cli(argv)
    out = StringIO.new
    old = $stdout
    $stdout = out
    code = Parsanol::PARG::CLI.run(argv)
    $stdout = old
    [code, out.string]
  end

  it "emits the variant against the model map" do
    file = compile_artifact_file(grammar)
    model = Tempfile.new(["model", ".json"])
    model.write(JSON.generate({ "number" => "42", "year" => "1999" }))
    model.close
    code, out = run_cli(["generate", file.path, "--model", model.path])
    expect(code).to eq(0)
    expect(out).to eq("TAG-42:1999")
  end

  it "renders absent conditional fields as empty" do
    file = compile_artifact_file(grammar)
    model = Tempfile.new(["model", ".json"])
    model.write(JSON.generate({ "number" => "7" }))
    model.close
    code, out = run_cli(["generate", file.path, "--model", model.path])
    expect(code).to eq(0)
    expect(out).to eq("TAG-7")
  end

  it "requires --model" do
    file = compile_artifact_file(grammar)
    code, = run_cli(["generate", file.path])
    expect(code).to eq(1)
  end
end
