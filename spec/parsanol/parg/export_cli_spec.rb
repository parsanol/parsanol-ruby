# frozen_string_literal: true

require "parsanol"
require "stringio"
require "tmpdir"

# `parg export` — the decoder-facing lowering through the CLI: both
# targets, and --recovery lowering a declared resync as the escape
# alternative.
RSpec.describe "parg export command" do
  def export_output(source, *flags)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "g.parg")
      File.write(path, source)
      $stdout = StringIO.new
      begin
        status = Parsanol::PARG::CLI.new(["export", path, *flags]).run
        [status, $stdout.string]
      ensure
        $stdout = STDOUT
      end
    end
  end

  let(:source) do
    <<~PARG
      grammar Demo version "1.0.0" edition "v2" {
        digit = %x30-39
        pair = ( 1*( digit ) ) "=" ( 1*( digit ) ) ";"
        document = 1*( pair )
        resync document = 1*( %x21-2E ) ";"
        entry main: document
      }
    PARG
  end

  it "lowers to the xgrammar dialect by default" do
    status, out = export_output(source)
    expect(status).to eq(0)
    expect(out).to include("main_entry ::=")
  end

  it "lowers to the llguidance dialect with the start prologue" do
    status, out = export_output(source, "--target", "llguidance")
    expect(status).to eq(0)
    expect(out).to start_with("start: main_entry")
    expect(out).to include("main_entry:")
  end

  it "wraps a declared resync as the recovery alternative with --recovery" do
    status, out = export_output(source, "--recovery")
    expect(status).to eq(0)
    # the spine body | ( junk ) ( body )? — junk lowers from the
    # declared resync pattern
    expect(out).to include("( ( ")
    expect(out).to end_with(")? )*\n")
  end

  it "leaves the plain grammar intact with --recovery when none is declared" do
    plain = <<~PARG
      grammar Plain version "1.0.0" edition "v2" {
        entry main: word
        word = %x61-7A
      }
    PARG
    status, out = export_output(plain, "--recovery")
    expect(status).to eq(0)
    expect(out).to eq("main_entry ::= [\\x61-\\x7a]\n")
  end
end
