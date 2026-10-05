# frozen_string_literal: true

require "spec_helper"

# The compiled-program and heavy-flag caches must not grow with every
# grammar ever parsed. They were once plain Hashes keyed by
# root.object_id: every grammar ever parsed pinned its program forever,
# and a recycled object_id could hand a fresh grammar another grammar's
# program (silent wrong parses). They are now identity-keyed Hashes
# capped at Parsanol::VM::PROGRAM_CACHE_LIMIT entries (FIFO eviction) —
# bounded retention, and cross-contamination is structurally impossible.
describe "VM program cache bounds" do
  def churn_parser(num)
    suffix = "# v#{num}"
    Class.new(Parsanol::Parser) do
      rule(:pair)     { match(/[_a-z0-9]/).repeat(1).as(:k) >> str("=") >> match(/[0-9]/).repeat(1).as(:v) }
      rule(:document) { (pair >> str("\n")).repeat(1) >> str(suffix) }
      root(:document)
    end
  end

  def cache_sizes
    programs = Parsanol::VM.instance_variable_get(:@programs)
    heavy = Parsanol::VM.instance_variable_get(:@heavy)
    [programs ? programs.size : 0, heavy ? heavy.size : 0]
  end

  it "serves a stable program per grammar across parses" do
    parser = churn_parser(0).new
    input = "k1=1\nk2=2\n# v0"
    parser.parse(input, mode: :ruby)
    first = Parsanol::VM.program_for(parser.root)
    expect(first).to be_a(Array)
    expect(Parsanol::VM.program_for(parser.root)).to equal(first)
  end

  it "never serves one grammar's program to a different grammar" do
    a_root = churn_parser(1).new.root
    b_root = churn_parser(2).new.root
    a = Parsanol::VM.program_for(a_root)
    b = Parsanol::VM.program_for(b_root)
    expect(a).to be_a(Array)
    expect(b).to be_a(Array)
    expect(a).not_to equal(b)
    expect(Parsanol::VM.program_for(a_root)).to equal(a)
    expect(Parsanol::VM.program_for(b_root)).to equal(b)
  end

  it "bounds retained programs as grammars churn" do
    GC.start
    base_programs, base_heavy = cache_sizes

    60.times { |k| churn_parser(k).new.parse("k1=1\n# v#{k}", mode: :ruby) }

    live_programs, live_heavy = cache_sizes
    # Grammars still held by this example may remain; the churn wave
    # may not add more than the cache limit allows.
    expect(live_programs).to be <= base_programs + Parsanol::VM::PROGRAM_CACHE_LIMIT + 1
    expect(live_heavy).to be <= base_heavy + Parsanol::VM::PROGRAM_CACHE_LIMIT + 1

    held = churn_parser(999).new
    held.parse("k1=1\n# v999", mode: :ruby)
    GC.start
    held_programs, = cache_sizes
    # A live grammar stays cached across GCs (no recompile per parse).
    expect(Parsanol::VM.program_for(held.root)).to be_a(Array)
    expect(held_programs).to be >= 1
  end

  it "disable_for! suppresses the VM for that grammar tree only" do
    marked = churn_parser(4).new
    Parsanol::VM.disable_for!(marked.root)
    expect(Parsanol::VM.program_for(marked.root)).to be_nil

    other_root = churn_parser(5).new.root
    expect(Parsanol::VM.program_for(other_root)).to be_a(Array)
  end
end
