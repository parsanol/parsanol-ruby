# frozen_string_literal: true

require "spec_helper"

# parsanol-ruby#162: dynamic-flagged PARG artifacts (state atoms) must
# parse on the native engine, not fall back to the interpreter. The
# wire has carried StateSet/StateMatch since #129; the walker
# evaluates them (rs native-state-machine), riding the capture store's
# rollback discipline for slot writes.
RSpec.describe "PARG artifact state atoms parse natively" do
  let(:grammar) do
    <<~PARG
      grammar F version "1.0.0" {
        newline = %x0A
        state fence: string
        entry code: code_block
        code_block = ((set fence = (3*%x60)) as open newline (1*(fence_line)) as lines (state fence) newline)
        fence_line = (1*(!(newline / (state fence)) %x2E) newline)
      }
    PARG
  end

  let(:artifact) do
    document = Parsanol::PARG::Parser.new(grammar).parse
    Parsanol::PARG::Artifact.new(
      Parsanol::PARG::Compiler.compile(document).envelope, nil, nil
    )
  end

  let(:input) { "```\n...\n```\n" }

  it "flags the envelope dynamic and parses both modes tree-identically" do
    expect(artifact.envelope["dynamic"]).to be(true)

    native = artifact.parse("code", input)
    ruby = artifact.parse("code", input, mode: :ruby)
    expect(native.inspect).to eq(ruby.inspect)
    expect(native.inspect).to include("...")
  end

  it "routes native mode through the native engine" do
    skip "native engine unavailable" unless Parsanol::Native.available?

    artifact.parse("code", input)
    # The lane registers the grammar by handle: a second parse reuses
    # it (handle cache size stays 1) instead of falling back to the
    # interpreter per call.
    artifact.parse("code", input)
    stats = Parsanol::Native::Parser.cache_stats
    expect(stats[:handle_cache_size]).to be >= 1
  end

  it "rejects a broken fence at the state match" do
    expect { artifact.parse("code", "```\n...\n~~~\n") }
      .to raise_error(Parsanol::ParseFailed)
  end
end
