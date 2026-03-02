# frozen_string_literal: true

require "spec_helper"
require "parsanol/lexer"

RSpec.describe Parsanol::Lexer do
  describe "basic tokenization" do
    before do
      class TestLexer < Parsanol::Lexer
        token :word, /[a-z]+/
        token :number, /[0-9]+/
        ignore /\s+/
      end
    end

    let(:lexer) { TestLexer.new }

    it "tokenizes words" do
      tokens = lexer.tokenize("hello world")
      expect(tokens.size).to eq(3) # 2 words + eof
      expect(tokens[0]["type"]).to eq("word")
      expect(tokens[0]["value"]).to eq("hello")
      expect(tokens[1]["type"]).to eq("word")
      expect(tokens[1]["value"]).to eq("world")
    end

    it "tokenizes numbers" do
      tokens = lexer.tokenize("123 456")
      expect(tokens.size).to eq(3)
      expect(tokens[0]["type"]).to eq("number")
      expect(tokens[0]["value"]).to eq("123")
      expect(tokens[1]["type"]).to eq("number")
      expect(tokens[1]["value"]).to eq("456")
    end

    it "ignores whitespace" do
      tokens = lexer.tokenize("hello   world")
      expect(tokens.size).to eq(3)
    end

    it "includes location information" do
      tokens = lexer.tokenize("hello")
      expect(tokens[0]["location"]["line"]).to eq(1)
      expect(tokens[0]["location"]["column"]).to eq(1)
      expect(tokens[0]["location"]["offset"]).to eq(0)
    end

    it "tracks line and column correctly" do
      tokens = lexer.tokenize("hello\nworld")
      expect(tokens[0]["location"]["line"]).to eq(1)
      expect(tokens[0]["location"]["column"]).to eq(1)
      expect(tokens[1]["location"]["line"]).to eq(2)
      expect(tokens[1]["location"]["column"]).to eq(1)
    end

    it "adds eof token at the end" do
      tokens = lexer.tokenize("hello")
      expect(tokens.last["type"]).to eq("eof")
    end
  end

  describe "priority handling" do
    before do
      class PriorityLexer < Parsanol::Lexer
        token :keyword, /if|else|while/, priority: 100
        token :identifier, /[a-z]+/, priority: 1
        ignore /\s+/
      end
    end

    let(:lexer) { PriorityLexer.new }

    it "matches higher priority patterns first" do
      tokens = lexer.tokenize("if else while")
      expect(tokens[0]["type"]).to eq("keyword")
      expect(tokens[0]["value"]).to eq("if")
      expect(tokens[1]["type"]).to eq("keyword")
      expect(tokens[1]["value"]).to eq("else")
      expect(tokens[2]["type"]).to eq("keyword")
      expect(tokens[2]["value"]).to eq("while")
    end

    it "falls back to lower priority when no match" do
      tokens = lexer.tokenize("if variable else")
      expect(tokens[0]["type"]).to eq("keyword")
      expect(tokens[1]["type"]).to eq("identifier")
      expect(tokens[1]["value"]).to eq("variable")
      expect(tokens[2]["type"]).to eq("keyword")
    end
  end

  describe "keyword helper" do
    before do
      class KeywordLexer < Parsanol::Lexer
        keyword :if, :then, :else, priority: 50
        token :identifier, /[a-z]+/, priority: 1
        ignore /\s+/
      end
    end

    let(:lexer) { KeywordLexer.new }

    it "creates keyword tokens with high priority" do
      tokens = lexer.tokenize("if x then y")
      expect(tokens[0]["type"]).to eq("IF")
      expect(tokens[1]["type"]).to eq("identifier")
      expect(tokens[2]["type"]).to eq("THEN")
    end
  end

  describe "longest match rule" do
    before do
      class LongestMatchLexer < Parsanol::Lexer
        token :string, /"[^"]*"/
        token :quote, /"/
        ignore /\s+/
      end
    end

    let(:lexer) { LongestMatchLexer.new }

    it "prefers longer matches" do
      tokens = lexer.tokenize('"hello"')
      expect(tokens.size).to eq(2) # string + eof
      expect(tokens[0]["type"]).to eq("string")
      expect(tokens[0]["value"]).to eq('"hello"')
    end
  end

  describe "inheritance" do
    before do
      class BaseLexer < Parsanol::Lexer
        token :word, /[a-z]+/
        ignore /\s+/
      end

      class ExtendedLexer < BaseLexer
        token :number, /[0-9]+/
      end
    end

    let(:base_lexer) { BaseLexer.new }
    let(:extended_lexer) { ExtendedLexer.new }

    it "inherits tokens from parent class" do
      tokens = extended_lexer.tokenize("hello 123")
      # word + number + eof = 3 tokens
      expect(tokens.size).to eq(3)
      expect(tokens[0]["type"]).to eq("word")
      expect(tokens[0]["value"]).to eq("hello")
      expect(tokens[1]["type"]).to eq("number")
      expect(tokens[1]["value"]).to eq("123")
    end

    it "does not modify parent class" do
      tokens = base_lexer.tokenize("hello world")
      # Base lexer should only match words
      expect(tokens.size).to eq(3) # word + word + eof
      expect(tokens[0]["type"]).to eq("word")
      expect(tokens[0]["value"]).to eq("hello")
      expect(tokens[1]["type"]).to eq("word")
      expect(tokens[1]["value"]).to eq("world")
    end
  end

  describe "error handling" do
    before do
      class ErrorLexer < Parsanol::Lexer
        token :word, /[a-z]+/
        ignore /\s+/
      end
    end

    let(:lexer) { ErrorLexer.new }

    it "produces error token for unrecognized input" do
      tokens = lexer.tokenize("hello 123 world")
      # 123 should produce error tokens (1, 2, 3)
      error_tokens = tokens.select { |t| t["type"] == "error" }
      expect(error_tokens.size).to be >= 1
    end
  end

  describe "JSON example" do
    before do
      class JsonLexer < Parsanol::Lexer
        token :string, /"[^"]*"/
        token :number, /-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?/
        token :true, /true/
        token :false, /false/
        token :null, /null/
        token :lbrace, /\{/
        token :rbrace, /\}/
        token :lbracket, /\[/
        token :rbracket, /\]/
        token :colon, /:/
        token :comma, /,/
        ignore /\s+/
      end
    end

    let(:lexer) { JsonLexer.new }

    it "tokenizes simple JSON object" do
      tokens = lexer.tokenize('{"name": "test"}')
      types = tokens.map { |t| t["type"] }
      expect(types).to eq(%w[lbrace string colon string rbrace eof])
    end

    it "tokenizes JSON with numbers" do
      tokens = lexer.tokenize('{"count": 42}')
      types = tokens.map { |t| t["type"] }
      expect(types).to eq(%w[lbrace string colon number rbrace eof])
    end

    it "tokenizes JSON with boolean" do
      tokens = lexer.tokenize('{"active": true}')
      types = tokens.map { |t| t["type"] }
      expect(types).to eq(%w[lbrace string colon true rbrace eof])
    end

    it "tokenizes complex JSON" do
      tokens = lexer.tokenize('{"items": [1, 2, 3], "nested": {"x": true}}')
      types = tokens.map { |t| t["type"] }
      expect(types).to eq(%w[
        lbrace string colon lbracket number comma number comma number rbracket
        comma string colon lbrace string colon true rbrace rbrace eof
      ])
    end
  end
end
