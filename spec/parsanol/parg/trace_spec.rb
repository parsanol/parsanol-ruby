# frozen_string_literal: true

require "parsanol"
require "stringio"
require "tmpdir"
require "json"

# C5 --trace: `parg parse --trace` runs the pure-Ruby tier and streams
# one pc/pos/op line per VM dispatch step to stderr. The native tier has
# no Ruby VM to trace, so the flag forces mode: :ruby.
RSpec.describe "parg parse --trace" do
  def traced_parse(input, trace: true)
    out = StringIO.new
    err = StringIO.new
    result = nil
    Dir.mktmpdir do |dir|
      path = File.join(dir, "g.parg")
      File.write(path, <<~PARG)
        grammar Demo version "1.0.0" edition "v2" {
          publisher = %i"ISO" / %i"IEEE"
          digit = 1*( %x30-39 )
          identifier = ( ( publisher ) as publisher ) ":" ( digit as number )
          entry identifier: identifier
        }
      PARG
      output = File.join(dir, "g.json")
      $stdout = out
      $stderr = err
      begin
        Dir.chdir(dir) do
          Parsanol::PARG::CLI.new(["compile", path, "-o", output]).run
          argv = ["parse", output]
          argv << "--trace" if trace
          argv << input
          status = Parsanol::PARG::CLI.new(argv).run
          result = [status, File.read(output)]
        end
      ensure
        $stdout = STDOUT
        $stderr = STDERR
      end
    end
    [result.first, out, err]
  end

  it "streams pc/pos/op dispatch lines to stderr and parses" do
    status, out, err = traced_parse("ISO:42")
    expect(status).to eq(0)
    expect(err.string).to match(%r{pc=\d+\s+pos=\d+\s+STR})
    expect(err.string).to include("HALT")
    # The result itself is unaffected.
    expect(out.string).to include("captures")
  end

  it "leaves the hot path untouched when not tracing" do
    expect(Parsanol::VM.trace_destination).to be_nil
    status, _, err = traced_parse("IEEE:7", trace: false)
    expect(status).to eq(0)
    expect(err.string).not_to match(/pc=\d+/)
    expect(Parsanol::VM.trace_destination).to be_nil
  end
end
