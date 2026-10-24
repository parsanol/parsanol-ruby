# frozen_string_literal: true

require "parsanol"
require "stringio"
require "tmpdir"

# ruby#307 B5: `parg lint` — errors, warnings, and the
# --suggest-upgrades surface.
RSpec.describe "parg lint command" do
  def lint_output(source, *flags)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "g.parg")
      File.write(path, source)
      $stdout = StringIO.new
      begin
        status = Parsanol::PARG::CLI.new(["lint", path, *flags]).run
        [status, $stdout.string]
      ensure
        $stdout = STDOUT
      end
    end
  end

  let(:hand_rolled) do
    <<~PARG
      grammar Demo version "1.0.0" {
        digit = %x30-39
        pair = 1*digit "-" 1*ALPHA
        entry document: pair
      }
    PARG
  end

  it "prints warnings and exits 0 on a clean grammar" do
    status, out = lint_output(hand_rolled)
    expect(status).to eq(0)
    expect(out).to include("warning:")
  end

  it "prints errors and exits 1 on a lint error" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        tag = "iso" / "iso/iec"
        entry document: tag
      }
    PARG
    status, out = lint_output(source)
    expect(status).to eq(1)
    expect(out).to include("error:")
  end

  it "suggests core-rule upgrades with the flag" do
    status, out = lint_output(hand_rolled, "--suggest-upgrades")
    expect(status).to eq(0)
    expect(out).to include('upgrade: rule "digit" duplicates the core rule DIGIT')
  end

  it "stays silent on upgrades without the flag" do
    _status, out = lint_output(hand_rolled)
    expect(out).not_to include("upgrade:")
  end

  it "suggests CRLF for the hand-rolled byte sequence" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        crlf = %x0D %x0A
        line = 1*ALPHA crlf
        entry document: line
      }
    PARG
    _status, out = lint_output(source, "--suggest-upgrades")
    expect(out).to include("core rule CRLF")
  end
end
