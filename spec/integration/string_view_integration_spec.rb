# frozen_string_literal: true

require "spec_helper"

describe "StringView Integration" do
  include Parsanol

  describe "basic parsing with StringView" do
    it "parses simple string" do
      parser = str("hello")
      result = parser.parse("hello")

      expect(result).to be_a(Parsanol::Slice)
      expect(result.to_s).to eq("hello")
      expect(result.offset).to eq(0)
    end

    it "parses sequences" do
      parser = str("a") >> str("b") >> str("c")
      result = parser.parse("abc")

      # Sequences get flattened to a single slice by default
      expect(result.to_s).to eq("abc")
    end

    it "parses alternatives" do
      parser = str("hello") | str("world")

      result1 = parser.parse("hello")
      expect(result1.to_s).to eq("hello")

      result2 = parser.parse("world")
      expect(result2.to_s).to eq("world")
    end

    it "parses character classes" do
      parser = match["a-z"].repeat(5, 5)
      result = parser.parse("hello")

      # Repetitions with same min/max get flattened
      expect(result.to_s).to eq("hello")
    end

    it "parses small repetitions" do
      parser = str("a").repeat(3, 3)
      result = parser.parse("aaa")

      # Repetitions with same min/max get flattened
      expect(result.to_s).to eq("aaa")
    end
  end

  describe "backward compatibility" do
    it "Slice#str materializes string from StringView" do
      parser = str("test")
      result = parser.parse("test")

      expect(result.str).to eq("test")
      expect(result.str).to be_a(String)
    end

    it "Slice#to_s works with StringView" do
      parser = str("test")
      result = parser.parse("test")

      expect(result.to_s).to eq("test")
    end

    it "Slice comparison works with StringView" do
      parser = str("test")
      result = parser.parse("test")

      expect(result).to eq("test")
      expect(result == "test").to be true
    end

    it "Slice concatenation works with StringView" do
      parser = str("a").as(:a) >> str("b").as(:b)
      result = parser.parse("ab")

      # Access via hash keys
      concatenated = result[:a] + result[:b]
      expect(concatenated.to_s).to eq("ab")
    end
  end

  describe "UTF-8 support" do
    it "handles UTF-8 strings correctly" do
      parser = str("世界")
      result = parser.parse("世界")

      expect(result.to_s).to eq("世界")
    end

    it "handles mixed ASCII and UTF-8" do
      parser = str("hello").as(:en) >> str("世界").as(:jp)
      result = parser.parse("hello世界")

      expect(result[:en].to_s).to eq("hello")
      expect(result[:jp].to_s).to eq("世界")
    end
  end

  describe "memory efficiency" do
    it "caches materialized strings" do
      parser = str("test")
      result = parser.parse("test")

      # Calling str multiple times should return same object
      str1 = result.str
      str2 = result.str
      expect(str1.object_id).to eq(str2.object_id)
    end
  end

  describe "line and column tracking" do
    it "tracks position correctly when input is provided" do
      parser = str("hello world")
      input = "hello world"
      result = parser.parse(input)

      expect(result.line_and_column).to eq([1, 1])
      expect(result.offset).to eq(0)
    end
  end
end
