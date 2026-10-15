# frozen_string_literal: true

require "spec_helper"

# rs#166: the program cache is structure-hash-keyed in addition to
# atom identity, so fresh parser instances (or rules called on them)
# share the compiled program instead of silently recompiling the
# entire grammar per call — the fresh-parser recompile trap that
# cost coradoc 25x on table transforms (metanorma/coradoc#265).
# rubocop:disable RSpec/InstanceVariable -- the ivars read inside
# instance_exec blocks belong to Parsanol::VM, not this example.
RSpec.describe "VM program structure-hash cache" do
  def build_grammar_class
    Class.new(Parsanol::Parser) do
      rule(:word) { match("[a-z]").repeat(1).as(:w) }
      rule(:sep) { str(",") }
      rule(:list) { (word >> (sep >> word).repeat).as(:l) }
      root :list
    end
  end

  it "shares one compiled program across fresh parser instances" do
    first = build_grammar_class.new
    second = build_grammar_class.new

    program_one = nil
    program_two = nil
    Parsanol::VM.instance_exec do
      clear_program_cache
      program_one = program_for(first.root)
      program_two = program_for(second.root)
    end

    expect(program_one).not_to be_nil
    expect(program_two).to equal(program_one)
  end

  it "parses identically through a fresh instance after another parsed" do
    first = build_grammar_class.new
    second = build_grammar_class.new

    expect(first.parse("a,b,c")).to eq(second.parse("a,b,c"))
  end

  context "when a fresh root shares a program" do
    let(:parser_class) { build_grammar_class }
    let(:first_root) { parser_class.new.root }
    let(:fresh_root) { parser_class.new.root }

    before { Parsanol::VM.clear_program_cache }
    after { Parsanol::VM.clear_program_cache }

    it "hashes that root only once across repeated lookups" do
      program = Parsanol::VM.program_for(first_root)
      expect(Parsanol::Native::Parser).to receive(:public_structure_hash)
        .with(fresh_root).once.and_call_original

      3.times { expect(Parsanol::VM.program_for(fresh_root)).to equal(program) }
    end

    it "bounds identity programs and heavy flags while equivalent roots churn" do
      limit = Parsanol::VM::PROGRAM_CACHE_LIMIT
      roots = Array.new(limit + 8) { parser_class.new.root }
      program = Parsanol::VM.program_for(roots.first)
      roots.drop(1).each do |root|
        expect(Parsanol::VM.program_for(root)).to equal(program)
      end

      programs = Parsanol::VM.instance_variable_get(:@programs)
      heavy = Parsanol::VM.instance_variable_get(:@heavy)
      expect(programs.keys).to eq(roots.last(limit))
      expect(heavy.keys).to eq(roots.last(limit))
    end

    it "keeps a disabled shared root separate from other equivalent roots" do
      program = Parsanol::VM.program_for(first_root)
      expect(Parsanol::VM.program_for(fresh_root)).to equal(program)
      Parsanol::VM.disable_for!(fresh_root)

      2.times { expect(Parsanol::VM.program_for(fresh_root)).to be_nil }
      expect(Parsanol::VM.program_for(first_root)).to equal(program)
      expect(Parsanol::VM.program_for(parser_class.new.root)).to equal(program)
    end

    it "recompiles after clearing both identity and structural caches" do
      program = Parsanol::VM.program_for(first_root)
      expect(Parsanol::VM.program_for(fresh_root)).to equal(program)
      Parsanol::VM.clear_program_cache
      expect(Parsanol::VM).to receive(:compile).with(fresh_root).once.and_call_original

      rebuilt = Parsanol::VM.program_for(fresh_root)
      expect(rebuilt).to be_a(Array)
      expect(rebuilt).not_to equal(program)
      expect(Parsanol::VM.program_for(fresh_root)).to equal(rebuilt)
    end
  end

  # Order-dependent hole: a symbol verdict (:fallback / :oversize)
  # is a property of one compile attempt's path, not of the
  # structure. The share must serve only real programs — a stored
  # verdict would silently send a compile-capable grammar to the
  # interpreter, unseeded (the vm_fail_dispatch order-dependent CI
  # failure).
  it "never serves stored fallback or oversize verdicts as programs" do
    root = build_grammar_class.new.root

    results = %i[fallback oversize].map do |verdict|
      Parsanol::VM.instance_exec do
        clear_program_cache
        key = Parsanol::Native::Parser.public_structure_hash(root)
        (@programs_by_hash ||= {})[key] = verdict
        program_for(root)
      end
    end

    expect(results).to all(be_a(Array))
  end

  # The share hit must mirror the shared program's compile-time
  # heavy-memo seed onto the fresh root (the vm_fail_dispatch:55
  # contract): the inherited grammar memoizes on its very first
  # parse instead of running a doomed unmemoized cold start.
  it "seeds and inherits heavy-memo across a fresh same-structure instance" do
    first_root = build_grammar_class.new.root
    fresh_root = build_grammar_class.new.root

    states = Parsanol::VM.instance_exec do
      clear_program_cache
      program_for(first_root)
      first_heavy = @heavy[first_root]
      first_prone = @last_compile_prone
      program_for(fresh_root)
      [first_heavy, first_prone, @heavy[fresh_root]]
    end

    expect(states).to eq([true, true, true])
  end
end
# rubocop:enable RSpec/InstanceVariable
