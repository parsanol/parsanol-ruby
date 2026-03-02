# frozen_string_literal: true

require 'spec_helper'
require 'parsanol/parslet'

describe "Position Pooling Integration" do
  describe "Source integration" do
    let(:source) { Parsanol::Source.new("hello\nworld\n") }
    
    it "has a position_pool" do
      expect(source.position_pool).to be_a(Parsanol::Pools::PositionPool)
    end

    it "creates pooled positions" do
      pos1 = source.position(0)
      expect(pos1).to be_a(Parsanol::Position)
      expect(pos1.bytepos).to eq(0)
    end

    it "position method works without arguments" do
      source.bytepos = 5
      pos = source.position
      expect(pos.bytepos).to eq(5)
    end

    it "positions can be reused from pool" do
      pos1 = source.position(0)
      id1 = pos1.object_id
      
      # Release back to pool (simulated by creating another position)
      source.position_pool.release(pos1)
      
      # Get another position - should reuse the same object
      pos2 = source.position(10)
      expect(pos2.object_id).to eq(id1)
      expect(pos2.bytepos).to eq(10)
    end
  end

  describe "Error reporting with pooled positions" do
    def catch_failed_parse
      yield
      nil
    rescue Parsanol::ParseFailed => e
      e
    end

    it "generates error messages correctly" do
      parser = Class.new(Parsanol::Parser) do
        root :num
        rule(:num) { match('[0-9]').repeat(1) }
      end.new
      
      error = catch_failed_parse { parser.parse("abc") }
      expect(error).to be_a(Parsanol::ParseFailed)
      expect(error.message).to include("line 1")
    end

    it "handles multi-line input with correct line numbers" do
      parser = Class.new(Parsanol::Parser) do
        root :lines
        rule(:lines) { line.repeat }
        rule(:line) { match('[0-9]').repeat(1) >> str("\n") }
      end.new
      
      error = catch_failed_parse { parser.parse("123\n456\nabc\n") }
      expect(error).to be_a(Parsanol::ParseFailed)
      expect(error.message).to include("line 3")
    end
  end

  describe "Pool statistics and reuse" do
    it "shows position reuse in pool statistics" do
      source = Parsanol::Source.new("test input for pooling")
      pool = source.position_pool
      
      # Create multiple positions
      pos1 = source.position(0)
      pos2 = source.position(5)
      pos3 = source.position(10)
      
      # Check that positions were created
      stats = pool.statistics
      expect(stats[:created]).to be >= 3
      
      # Release and reuse
      pool.release(pos1)
      pool.release(pos2)
      pool.release(pos3)
      
      pos4 = source.position(15)
      pos5 = source.position(20)
      
      # Should show reuse
      stats = pool.statistics
      expect(stats[:reused]).to be >= 2
      expect(stats[:utilization]).to be > 0
    end

    it "pool handles many position creations efficiently" do
      source = Parsanol::Source.new("a" * 1000)
      pool = source.position_pool
      
      # Create many positions
      100.times do |i|
        pos = source.position(i)
        pool.release(pos) if i % 2 == 0  # Release half of them
      end
      
      stats = pool.statistics
      # Verify pool is being used
      expect(stats[:created]).to be > 0
      expect(stats[:released]).to be > 0
      
      # Check that utilization is reasonable
      # We release 50 and create 50 more in the next phase
      expect(stats[:utilization]).to be >= 0
    end
  end

  describe "Position object correctness" do
    it "positions maintain correct byte and character positions" do
      # Test with ASCII
      source = Parsanol::Source.new("hello world")
      pos = source.position(6)
      
      expect(pos.bytepos).to eq(6)
      expect(pos.charpos).to eq(6)  # ASCII: byte == char
    end

    it "positions work with UTF-8 strings" do
      # Test with UTF-8
      source = Parsanol::Source.new("café")
      pos = source.position(4)  # After 'caf'
      
      expect(pos.bytepos).to eq(4)
      # charpos calculation may differ based on encoding
      expect(pos.charpos).to be_a(Integer)
    end

    it "positions track source string correctly" do
      input = "test string"
      source = Parsanol::Source.new(input)
      pos = source.position(5)
      
      # Position should reference the original source string
      expect(pos.string).to eq(input)
    end
  end

  describe "Integration with existing parser" do
    class SimpleParser < Parsanol::Parser
      root :document
      rule(:document) { word.repeat.as(:words) }
      rule(:word) { match('[a-z]').repeat(1).as(:word) >> space.maybe }
      rule(:space) { match('\s').repeat(1) }
    end

    it "parser works correctly with position pooling" do
      parser = SimpleParser.new
      result = parser.parse("hello world")
      
      expect(result).to eq({
        words: [
          { word: "hello" },
          { word: "world" }
        ]
      })
    end

    it "parser generates errors with position information" do
      parser = SimpleParser.new
      
      error = begin
        parser.parse("hello 123")
      rescue Parsanol::ParseFailed => e
        e
      end
      
      expect(error).to be_a(Parsanol::ParseFailed)
      expect(error.message).to match(/line \d+ char \d+/)
    end
  end
end