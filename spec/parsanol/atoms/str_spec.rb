# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Atoms::Str do
  def str(s)
    described_class.new(s)
  end

  describe "regression #1: multibyte characters" do
    it "parses successfully (length check works)" do
      str("あああ").should parse("あああ")
    end

    it "advances by byte length after a successful match" do
      source = Parsanol::Source.new("あx")
      context = Parsanol::Atoms::Context.new(nil)

      success, value = str("あ").apply(source, context, false)

      expect(success).to be(true)
      expect(value.to_s).to eq("あ")
      expect(source.bytepos).to eq("あ".bytesize)
    end
  end

  it "does not consume input on a failed match without error reporting" do
    source = Parsanol::Source.new("xbc")
    context = Parsanol::Atoms::Context.new(nil)

    success, = str("abc").apply(source, context, false)

    expect(success).to be(false)
    expect(source.bytepos).to eq(0)
  end
end
