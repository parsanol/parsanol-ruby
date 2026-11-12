# frozen_string_literal: true

require "parsanol"
require "stringio"
require "tmpdir"
require "fileutils"

# ruby#494: `parg fmt` on the command line — in place by default,
# --check never writes (exit 1 + a note when not canonical), --stdin
# reads and prints, and an unparseable file fails without touching it.
RSpec.describe "parg fmt command" do
  let(:source) do
    <<~PARG
      grammar Demo version "1.0.0" {
        item=1* %x30-39 as n
        main = item * ("," item)
        entry main: main
        bindings main { n->n (integer) }
      }
    PARG
  end

  let(:canonical) do
    <<~PARG
      grammar Demo version "1.0.0" {
        item = 1* %x30-39 as n
        main = item * ("," item)

        entry main: main

        bindings main {
          n -> n (integer)
        }
      }
    PARG
  end

  def with_file(contents)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "g.parg")
      File.write(path, contents)
      yield path
    end
  end

  it "rewrites the file in place to the canonical form" do
    with_file(source) do |path|
      status = Parsanol::PARG::CLI.new(["fmt", path]).run
      expect(status).to be_zero
      expect(File.read(path)).to eq(canonical)
    end
  end

  it "--check exits 0 on canonical input and writes nothing" do
    with_file(canonical) do |path|
      status = Parsanol::PARG::CLI.new(["fmt", path, "--check"]).run
      expect(status).to be_zero
      expect(File.read(path)).to eq(canonical)
    end
  end

  it "--check exits 1 on non-canonical input and leaves the file alone" do
    with_file(source) do |path|
      status = nil
      expect do
        status = Parsanol::PARG::CLI.new(["fmt", path, "--check"]).run
      end.not_to(change { File.read(path) })
      expect(status).to eq(1)
    end
  end

  it "--stdin reads the source and prints the canonical form" do
    input = StringIO.new(source)
    out = StringIO.new
    $stdin = input
    $stdout = out
    begin
      status = Parsanol::PARG::CLI.new(["fmt", "--stdin"]).run
    ensure
      $stdin = STDIN
      $stdout = STDOUT
    end
    expect(status).to be_zero
    expect(out.string).to eq(canonical)
  end

  it "fails on an unparseable file without rewriting it" do
    # the CLI wraps the parser's error into a non-zero exit; the file
    # must be untouched either way
    with_file("grammar Broken { main = ( }\n") do |path|
      before = File.read(path)
      status = Parsanol::PARG::CLI.new(["fmt", path]).run
      expect(status).not_to be_zero
      expect(File.read(path)).to eq(before)
    end
  end
end
