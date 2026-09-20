# frozen_string_literal: true

require "spec_helper"

describe Parsanol::IncrementalSession do
  let(:parser_class) do
    Class.new(Parsanol::Parser) do
      rule(:pair) { key >> str("=") >> value >> str("\n") }
      rule(:key) { match("[a-z][a-z0-9]*").repeat(1) }
      rule(:value) { match("[0-9]").repeat(1) }
      rule(:doc) { pair.repeat(0) }
      root(:doc)

      def self.name
        "IncrementalKvParser"
      end
    end
  end

  let(:doc) { (1..200).map { |i| "key#{i}=#{i * 3}\n" }.join }

  it "parses the full document identically to a one-shot native parse" do
    session = described_class.new(parser_class.new.root)
    expect(session.parse(doc)).to eq(parser_class.new.parse(doc))
    session.release
  end

  it "re-parses edits to the same tree as a full parse" do
    session = described_class.new(parser_class.new.root)
    session.parse(doc)

    edited = doc.sub("key50=150\n", "zed=9\n")
    offset = doc.index("key50=150\n")
    result = session.parse_with_edit(
      edited, offset: offset, old_length: "key50=150\n".length, new_length: "zed=9\n".length
    )
    expect(result).to eq(parser_class.new.parse(edited))
    session.release
  end

  it "keeps acceptance in sync with a full parse on a broken edit" do
    session = described_class.new(parser_class.new.root)
    session.parse(doc)

    broken = doc.sub("key50=150\n", "key50=\n")
    offset = doc.index("key50=150\n")
    expect do
      session.parse_with_edit(
        broken, offset: offset, old_length: "key50=150\n".length, new_length: "key50=\n".length
      )
    end.to raise_error(RuntimeError)
    session.release
  end

  it "reports cache stats" do
    session = described_class.new(parser_class.new.root)
    session.parse(doc)
    expect(session.stats).to be_an(Array)
    session.release
  end

  it "rejects use of an unknown session" do
    expect do
      Parsanol::Native._incremental_parse(999_999_999, "x", -1, 0, 0)
    end.to raise_error(ArgumentError)
  end
end
