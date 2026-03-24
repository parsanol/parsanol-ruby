# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Pools::SlicePool do
  describe "#initialize" do
    it "creates a pool with default size" do
      pool = described_class.new
      expect(pool.size).to eq(1000)
    end

    it "creates a pool with specified size" do
      pool = described_class.new(size: 500)
      expect(pool.size).to eq(500)
    end

    it "pre-allocates Slice objects by default" do
      pool = described_class.new(size: 10)
      stats = pool.statistics
      expect(stats[:available]).to eq(10)
    end

    it "can disable pre-allocation" do
      pool = described_class.new(size: 10, preallocate: false)
      stats = pool.statistics
      expect(stats[:available]).to eq(0)
    end
  end

  describe "#acquire" do
    it "returns a Slice instance" do
      pool = described_class.new(size: 10, preallocate: false)
      slice = pool.acquire
      expect(slice).to be_a(Parsanol::Slice)
    end

    it "reuses slices from the pool" do
      pool = described_class.new(size: 10, preallocate: true)
      slice1 = pool.acquire
      slice1_id = slice1.object_id
      pool.release(slice1)

      slice2 = pool.acquire
      expect(slice2.object_id).to eq(slice1_id)
    end

    it "creates new slices when pool is empty" do
      pool = described_class.new(size: 2, preallocate: false)
      pool.acquire
      pool.acquire

      stats = pool.statistics
      expect(stats[:created]).to eq(2)
    end
  end

  describe "#acquire_with" do
    it "acquires and initializes slice in one step" do
      pool = described_class.new(size: 10, preallocate: false)
      slice = pool.acquire_with(42, "hello")

      expect(slice).to be_a(Parsanol::Slice)
      expect(slice.offset).to eq(42)
      expect(slice.to_s).to eq("hello")
    end

    it "accepts optional input string for lazy line/column" do
      pool = described_class.new(size: 10, preallocate: false)
      input = "hello\nworld"
      slice = pool.acquire_with(0, "hello", input)

      expect(slice).to be_a(Parsanol::Slice)
      expect(slice.line_and_column).to eq([1, 1])
    end

    it "reuses slices with new values" do
      pool = described_class.new(size: 10, preallocate: false)

      # First use
      slice1 = pool.acquire_with(0, "first")
      expect(slice1.to_s).to eq("first")
      slice1_id = slice1.object_id

      # Return to pool
      pool.release(slice1)

      # Reuse with different values
      slice2 = pool.acquire_with(10, "second")
      expect(slice2.object_id).to eq(slice1_id) # Same object
      expect(slice2.to_s).to eq("second")       # Different content
      expect(slice2.offset).to eq(10)           # Different position
    end

    it "properly initializes all slice attributes" do
      pool = described_class.new(size: 10, preallocate: false)
      input = "test content here"

      slice = pool.acquire_with(5, "content", input)

      expect(slice.offset).to eq(5)
      expect(slice.to_s).to eq("content")
      expect(slice.line_and_column).to eq([1, 6]) # Line 1, column 6 (offset 5 + 1)
    end
  end

  describe "#release" do
    it "returns slice to pool" do
      pool = described_class.new(size: 10, preallocate: false)
      slice = pool.acquire

      pool.release(slice)

      stats = pool.statistics
      expect(stats[:available]).to eq(1)
    end

    it "resets slice before pooling" do
      pool = described_class.new(size: 10, preallocate: false)
      slice = pool.acquire_with(99, "original")

      pool.release(slice)

      # Slice should be reset to defaults
      expect(slice.offset).to eq(0)
      expect(slice.to_s).to eq("")
      expect(slice.input).to be_nil
    end

    it "discards slices when pool is full" do
      pool = described_class.new(size: 1, preallocate: true)

      new_slice = Parsanol::Slice.new(0, "extra")
      result = pool.release(new_slice)

      expect(result).to be false
      stats = pool.statistics
      expect(stats[:discarded]).to eq(1)
    end
  end

  describe "integration with Slice" do
    it "works with real parsing scenario" do
      pool = described_class.new(size: 5, preallocate: false)

      # Simulate parsing multiple tokens
      slices = []

      # Parse "hello world"
      slices << pool.acquire_with(0, "hello")
      slices << pool.acquire_with(6, "world")

      expect(slices[0].to_s).to eq("hello")
      expect(slices[1].to_s).to eq("world")

      # Release all slices
      slices.each { |s| pool.release(s) }

      # Pool should have 2 slices available
      stats = pool.statistics
      expect(stats[:available]).to eq(2)
      expect(stats[:created]).to eq(2)
      expect(stats[:reused]).to eq(0)
    end

    it "maintains slice equality after pooling" do
      pool = described_class.new(size: 5, preallocate: false)

      slice1 = pool.acquire_with(0, "test")
      pool.release(slice1)

      slice2 = pool.acquire_with(0, "test")

      # Should be same object
      expect(slice1.object_id).to eq(slice2.object_id)
      # Should be equal
      expect(slice1).to eq(slice2)
    end
  end

  describe "performance characteristics" do
    it "shows high reuse rate with pooling" do
      pool = described_class.new(size: 100, preallocate: false)

      # Create initial slices
      slices = Array.new(50) { |i| pool.acquire_with(i, "slice#{i}") }

      # Release all
      slices.each { |s| pool.release(s) }

      # Acquire again - should all be reused
      50.times { pool.acquire }

      stats = pool.statistics
      expect(stats[:created]).to eq(50)
      expect(stats[:reused]).to eq(50)
      expect(stats[:utilization]).to eq(50.0)
    end

    it "handles rapid acquire/release cycles" do
      pool = described_class.new(size: 10, preallocate: false)

      100.times do |i|
        slice = pool.acquire_with(i, "test#{i}")
        pool.release(slice)
      end

      stats = pool.statistics
      # Should have high reuse, low creation
      expect(stats[:created]).to be <= 10
      expect(stats[:reused]).to be >= 90
    end
  end

  describe "statistics" do
    it "tracks slice-specific operations" do
      pool = described_class.new(size: 5, preallocate: false)

      # Create 3 slices
      s1 = pool.acquire_with(0, "a")
      s2 = pool.acquire_with(1, "b")
      pool.acquire_with(2, "c")

      # Release 2
      pool.release(s1)
      pool.release(s2)

      # Reuse 1
      pool.acquire

      stats = pool.statistics
      expect(stats[:created]).to eq(3)
      expect(stats[:reused]).to eq(1)
      expect(stats[:released]).to eq(2)
      expect(stats[:available]).to eq(1)
    end
  end

  describe "edge cases" do
    it "handles empty string slices" do
      pool = described_class.new(size: 5, preallocate: false)
      slice = pool.acquire_with(0, "")

      expect(slice.to_s).to eq("")
      expect(slice.size).to eq(0)
    end

    it "handles large string slices" do
      pool = described_class.new(size: 5, preallocate: false)
      large_str = "x" * 10_000
      slice = pool.acquire_with(0, large_str)

      expect(slice.to_s).to eq(large_str)
      expect(slice.size).to eq(10_000)
    end

    it "handles unicode content" do
      pool = described_class.new(size: 5, preallocate: false)
      slice = pool.acquire_with(0, "hello 世界 мир")

      expect(slice.to_s).to eq("hello 世界 мир")
    end
  end
end
