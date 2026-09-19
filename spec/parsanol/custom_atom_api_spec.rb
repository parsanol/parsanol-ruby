# frozen_string_literal: true

require "spec_helper"

# GH-70: API surface for custom-atom authors.
RSpec.describe "custom atom API" do
  describe "Parsanol::Source#input" do
    it "exposes the underlying input string" do
      source = Parsanol::Source.new("héllo")
      expect(source.input).to eq("héllo")
    end
  end

  describe "Parsanol::Scope#key?" do
    it "finds bindings through the parent chain" do
      scope = Parsanol::Scope.new
      scope[:a] = 1
      scope.push
      scope[:b] = 2

      expect(scope.key?(:a)).to be(true)
      expect(scope.key?(:b)).to be(true)
      expect(scope.key?(:c)).to be(false)
    end
  end

  describe "Parsanol::Source#rewind_chars" do
    it "rewinds by characters across multibyte sequences" do
      source = Parsanol::Source.new("aébc")
      source.consume(3) # "aéb" = 4 bytes
      expect(source.bytepos).to eq(4)
      expect(source.rewind_chars(2)).to eq(1)
      expect(source.bytepos).to eq(1)
    end

    it "never rewinds past the start" do
      source = Parsanol::Source.new("abc")
      source.consume(2)
      expect(source.rewind_chars(99)).to eq(0)
    end
  end
end
