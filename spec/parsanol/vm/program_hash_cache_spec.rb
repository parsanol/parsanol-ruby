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

  # Order-dependent hole: a symbol verdict (:fallback / :oversize)
  # is a property of one compile attempt's path, not of the
  # structure. The share must serve only real programs — a stored
  # verdict would silently send a compile-capable grammar to the
  # interpreter, unseeded (the vm_fail_dispatch order-dependent CI
  # failure).
  it "never serves a stored symbol verdict as a program" do
    root = build_grammar_class.new.root

    result = Parsanol::VM.instance_exec do
      clear_program_cache
      key = Parsanol::Native::Parser.public_structure_hash(root)
      (@programs_by_hash ||= {})[key] = :fallback
      program_for(root)
    end

    expect(result).to be_a(Array)
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
