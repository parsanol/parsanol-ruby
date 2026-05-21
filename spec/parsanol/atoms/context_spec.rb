# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Atoms::Context do
  describe "#caching_active?" do
    it "keeps caching disabled for small atom-level parses" do
      context = described_class.new(nil)

      expect(context.caching_active?(Parsanol::Source.new("x"))).to be(false)
    end

    it "enables caching immediately for parser classes by default" do
      parser_class = Class.new(Parsanol::Parser)
      context = described_class.new(nil, parser_class: parser_class)

      expect(context.caching_active?(Parsanol::Source.new("x"))).to be(true)
    end
  end
end
