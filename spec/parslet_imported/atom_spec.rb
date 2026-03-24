# frozen_string_literal: true

# Imported from Parslet test suite
# Original: https://github.com/kschiess/parslet/blob/main/spec/atom_spec.rb
#
# These tests verify that Parsanol::Parslet behaves identically to Parslet
# for the core atom operations.

require_relative "spec_helper"

RSpec.describe "Parslet Atoms" do
  # Get the appropriate module based on environment
  let(:parslet) do
    if ENV["PARSANOL_BACKEND"] == "parslet"
      Parslet
    else
      Parsanol::Parslet
    end
  end

  describe "str() atom" do
    it "matches a literal string" do
      parser = parslet.str("hello")
      expect(parser.parse("hello")).to eq("hello")
    end

    it "fails on non-matching input" do
      parser = parslet.str("hello")
      expect { parser.parse("world") }.to raise_error(parslet::ParseFailed)
    end

    it "fails on partial match" do
      parser = parslet.str("hello")
      expect { parser.parse("hell") }.to raise_error(parslet::ParseFailed)
    end

    it "fails on extra input" do
      parser = parslet.str("hello")
      expect do
        parser.parse("hello world")
      end.to raise_error(parslet::ParseFailed)
    end

    it "matches empty string" do
      parser = parslet.str("")
      expect(parser.parse("")).to eq("")
    end
  end

  describe "match() atom" do
    it "matches character classes" do
      parser = parslet.match("[a-z]")
      expect(parser.parse("x")).to eq("x")
    end

    it "matches digits" do
      parser = parslet.match("[0-9]")
      expect(parser.parse("5")).to eq("5")
    end

    it "fails on non-matching character" do
      parser = parslet.match("[a-z]")
      expect { parser.parse("5") }.to raise_error(parslet::ParseFailed)
    end

    it "matches only one character" do
      parser = parslet.match("[a-z]")
      expect { parser.parse("abc") }.to raise_error(parslet::ParseFailed)
    end

    it "matches multiple character classes" do
      parser = parslet.match("[a-zA-Z]")
      expect(parser.parse("X")).to eq("X")
    end
  end

  describe "any atom" do
    it "matches any single character" do
      parser = parslet.any
      expect(parser.parse("x")).to eq("x")
      expect(parser.parse("5")).to eq("5")
      expect(parser.parse(" ")).to eq(" ")
    end

    it "fails on empty input" do
      parser = parslet.any
      expect { parser.parse("") }.to raise_error(parslet::ParseFailed)
    end

    it "matches only one character" do
      parser = parslet.any
      expect { parser.parse("ab") }.to raise_error(parslet::ParseFailed)
    end
  end
end
