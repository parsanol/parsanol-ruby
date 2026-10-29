# frozen_string_literal: true

require "spec_helper"

RSpec.describe Parsanol::VM::Compiler do
  def literal(text)
    Parsanol::Atoms::Str.new(text)
  end

  it "bounds lead-byte analysis of a shared grammar graph" do
    leaf = literal("a")
    graph = leaf
    8.times { graph = Parsanol::Atoms::Alternative.new(graph, graph) }
    expect(leaf).to receive(:str).at_most(4).times.and_call_original

    table = described_class.new.first_byte_table(graph)

    expect(table.each_index.select { |i| table[i] }).to eq(["a".ord])
  end

  it "keeps a child's lead bytes separate from its alternative's union" do
    a = literal("a")
    compiler = described_class.new
    combined = compiler.first_byte_table(Parsanol::Atoms::Alternative.new(a, literal("b")))

    expect(combined["b".ord]).to be(true)
    expect(compiler.first_byte_table(a)["b".ord]).to be(false)
  end

  it "keeps depth-limited unknown lead bytes separate from shallower analysis" do
    wrapped = literal("a").as(:a)
    compiler = described_class.new

    expect(compiler.first_byte_table(wrapped, 10)).to be_nil
    expect(compiler.first_byte_table(wrapped)["a".ord]).to be(true)
  end

  it "bounds nullability analysis of shared nonnullable alternatives" do
    leaf = literal("a")
    graph = leaf
    8.times { graph = Parsanol::Atoms::Alternative.new(graph, graph) }
    expect(leaf).to receive(:str).at_most(4).times.and_call_original

    expect(described_class.new.nullable?(graph)).to be(false)
  end

  it "keeps depth-limited nullability separate from shallower analysis" do
    wrapped = literal("").as(:empty)
    compiler = described_class.new

    expect(compiler.nullable?(wrapped, 10)).to be(false)
    expect(compiler.nullable?(wrapped)).to be(true)
  end

  it "does not reuse a scoped analysis across compiler instances" do
    text = "a"
    scoped = Parsanol.scope { literal(text) }
    first = described_class.new.first_byte_table(scoped)
    text = "b"
    second = described_class.new.first_byte_table(scoped)

    expect(first["a".ord]).to be(true)
    expect(first["b".ord]).to be(false)
    expect(second["a".ord]).to be(false)
    expect(second["b".ord]).to be(true)
  end
end
