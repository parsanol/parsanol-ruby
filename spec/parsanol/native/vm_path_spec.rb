# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Inputs of 8 KB or more (the engine's VM_INPUT_THRESHOLD) run on the
# bytecode VM; smaller ones on the tree-walker. These pin the VM path to
# the interpreter's answers.
RSpec.describe "native VM path (inputs of 8 KB or more)" do
  before { skip "native backend unavailable" unless Parsanol::Native.available? }

  let(:vm_size) { 8 * 1024 }

  def outcome(parse, input, mode)
    parse.call(input, mode)
  rescue Parsanol::ParseFailed
    :rejected
  end

  it "rejects trailing input the grammar does not match" do
    atom = Parsanol.str("ab").repeat(1)
    parse = ->(input, mode) { mode == :ruby ? atom.parse(input, mode: :ruby) : Parsanol::Native.parse(atom, input) }
    input = "#{'ab' * (vm_size / 2)}!!"

    expect(outcome(parse, input, :native)).to eq(:rejected)
    expect(outcome(parse, input, :ruby)).to eq(:rejected)
  end

  it "matches escaped character classes the way PARG emits them" do
    document = Parsanol::PARG::Parser.new(<<~PARG).parse
      grammar Words version "1.0.0" mode "v1" {
        word = 1*%x61-7A
        ws = %x20 / %x0A
        doc = 0*( ws / word as word )
        entry main: doc
      }
    PARG
    envelope = Parsanol::PARG::Compiler.new(document, nil).compile.envelope
    artifact = Parsanol::PARG::Artifact.new(JSON.parse(JSON.generate(envelope)), nil, nil)
    parse = ->(input, mode) { artifact.parse("main", input, mode: mode) }
    input = "abc xyz\n" * ((vm_size / 8) + 1)

    native = outcome(parse, input, :native)
    expect(native).to eq(outcome(parse, input, :ruby))
    expect(native.size).to eq(input.split.size)
  end

  it "keys the compiled-program cache on the gem version" do
    skip "extension predates the cache version hook" unless Parsanol::Native.respond_to?(:_set_cache_version)

    previous_dir = ENV.fetch("PARSANOL_CACHE_DIR", nil)
    Dir.mktmpdir do |dir|
      ENV["PARSANOL_CACHE_DIR"] = dir
      json = Parsanol::Native::Parser.serialize_grammar(Parsanol.str("cache-version"))

      Parsanol::Native._set_cache_version("parsanol-ruby spec-a")
      Parsanol::Native._register_grammar(json)
      Parsanol::Native._set_cache_version("parsanol-ruby spec-b")
      Parsanol::Native._register_grammar(json)

      expect(Dir.children(dir).size).to eq(2)
    ensure
      ENV["PARSANOL_CACHE_DIR"] = previous_dir
      Parsanol::Native._set_cache_version("parsanol-ruby #{Parsanol::VERSION}")
    end
  end
end
