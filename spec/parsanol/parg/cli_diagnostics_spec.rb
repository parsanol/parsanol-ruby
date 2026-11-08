# frozen_string_literal: true

require "parsanol"
require "open3"
require "tmpdir"
require "json"

# ruby#462: `parg compile` diagnostics must reach stderr regardless of
# tty-ness — bake gates and CI integrations capture pipes, and a bare
# non-zero exit tells the author nothing. These examples run the real
# executable as a subprocess (pipes, not a tty) against the two error
# classes the issue names, and lock both the stderr line and the
# machine-readable `--json` payload.
RSpec.describe "parg compile diagnostics" do
  def compile_capture(source, *flags)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "g.parg")
      File.write(path, source)
      exe = File.expand_path("../../../exe/parsanol", __dir__)
      lib = File.expand_path("../../../lib", __dir__)
      # The artifact lands beside the grammar (never the process cwd).
      Open3.capture3(RbConfig.ruby, "-I", lib, exe, "parg", "compile", path, "-o", File.join(dir, "g.artifact.json"), *flags)
    end
  end

  let(:v1_grammar) do
    <<~PARG
      grammar Bad version "1.0.0" edition "v1" {
        entry x: "a"
      }
    PARG
  end

  let(:broken_grammar) do
    <<~PARG
      grammar Bad version "1.0.0" {
        entry x: =============
      }
    PARG
  end

  it "reports an edition rejection on stderr in a piped context" do
    _out, err, status = compile_capture(v1_grammar)
    expect(status.exitstatus).to eq(1)
    expect(err).to include('edition "v1" is not supported')
  end

  it "reports a parse failure on stderr in a piped context" do
    _out, err, status = compile_capture(broken_grammar)
    expect(status.exitstatus).to eq(1)
    expect(err).not_to be_empty
    expect(err).to include("ParseError")
  end

  it "emits the machine-readable error payload on stdout with --json" do
    out, err, status = compile_capture(v1_grammar, "--json")
    expect(status.exitstatus).to eq(1)
    payload = JSON.parse(out)
    expect(payload["error"]["class"]).to eq("Parsanol::PARG::ParseError")
    expect(payload["error"]["message"]).to include("edition 1 was removed")
    expect(err).to include('edition "v1" is not supported')
  end

  it "keeps successful compiles silent on stderr" do
    good = <<~PARG
      grammar Good version "1.0.0" {
        x = "a"
        entry x: x
      }
    PARG
    _out, err, status = compile_capture(good)
    expect(status.exitstatus).to eq(0)
    expect(err).to be_empty
  end
end
