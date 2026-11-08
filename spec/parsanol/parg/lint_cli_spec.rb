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

# ruby#461: --captures is the dead-capture report — the converse of the
# compile-time binding validation (binding-without-capture fails the
# build; capture-without-binding becomes visible on demand, scoped to
# the rule whose bindings section can reference it).
RSpec.describe "parg lint --captures" do
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

  let(:dead_capture) do
    <<~PARG
      grammar Demo version "1.0.0" {
        digit = %x30-39
        num = 1*digit as num
        pair = num "-" num as left
        entry document: pair

        bindings pair {
          left -> left (string)
        }
      }
    PARG
  end

  let(:fully_bound) do
    <<~PARG
      grammar Demo version "1.0.0" {
        digit = %x30-39
        num = 1*digit as num
        pair = num "-" num as left
        entry document: pair

        bindings pair {
          left -> left (string)
        }

        bindings num {
          num -> num (string)
        }
      }
    PARG
  end

  let(:opt_out) do
    <<~PARG
      grammar Demo version "1.0.0" {
        digit = %x30-39
        pair = 1*digit as count
        entry document: pair
      }
    PARG
  end

  it "reports the dead capture scoped to its rule" do
    _status, out = lint_output(dead_capture, "--captures")
    expect(out).to include('rule num: capture "num" is not referenced by any bindings path')
  end

  it "reports nothing when every capture is bound" do
    _status, out = lint_output(fully_bound, "--captures")
    expect(out).not_to include("is not referenced by any bindings path")
  end

  it "reports every capture on a grammar that opted out of binding" do
    _status, out = lint_output(opt_out, "--captures")
    expect(out).to include('rule pair: capture "count" is not referenced by any bindings path')
  end

  it "stays silent without the flag" do
    _status, out = lint_output(dead_capture)
    expect(out).not_to include("is not referenced by any bindings path")
  end

  it "attributes captures to their own rule, not to referencing rules" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        digit = %x30-39
        inner = 1*digit as n
        outer = inner "-" 1*digit as tail
        entry document: outer

        bindings inner {
          n -> n (string)
        }
      }
    PARG
    _status, out = lint_output(source, "--captures")
    expect(out).not_to include('rule outer: capture "n"')
  end
end
