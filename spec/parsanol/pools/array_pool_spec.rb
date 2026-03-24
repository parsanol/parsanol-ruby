# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Pools::ArrayPool do
  describe "#initialize" do
    it "creates a pool with default size" do
      pool = described_class.new
      expect(pool.size).to eq(1000)
    end

    it "creates a pool with specified size" do
      pool = described_class.new(size: 500)
      expect(pool.size).to eq(500)
    end

    it "pre-allocates Array objects by default" do
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
    it "returns an Array instance" do
      pool = described_class.new(size: 10, preallocate: false)
      array = pool.acquire
      expect(array).to be_a(Array)
    end

    it "returns an empty array" do
      pool = described_class.new(size: 10, preallocate: true)
      array = pool.acquire
      expect(array).to be_empty
    end

    it "reuses arrays from the pool" do
      pool = described_class.new(size: 10, preallocate: true)
      array1 = pool.acquire
      array1_id = array1.object_id
      pool.release(array1)

      array2 = pool.acquire
      expect(array2.object_id).to eq(array1_id)
    end

    it "creates new arrays when pool is empty" do
      pool = described_class.new(size: 2, preallocate: false)
      pool.acquire
      pool.acquire

      stats = pool.statistics
      expect(stats[:created]).to eq(2)
    end
  end

  describe "#release" do
    it "returns array to pool" do
      pool = described_class.new(size: 10, preallocate: false)
      array = pool.acquire

      pool.release(array)

      stats = pool.statistics
      expect(stats[:available]).to eq(1)
    end

    it "clears array before pooling" do
      pool = described_class.new(size: 10, preallocate: false)
      array = pool.acquire
      array << 1 << 2 << 3

      pool.release(array)

      # Array should be empty
      expect(array).to be_empty
    end

    it "ensures released arrays are reused empty" do
      pool = described_class.new(size: 10, preallocate: false)

      # First use
      array1 = pool.acquire
      array1 << "a" << "b" << "c"
      pool.release(array1)

      # Reuse - should be empty
      array2 = pool.acquire
      expect(array2).to be_empty
      expect(array2.object_id).to eq(array1.object_id)
    end

    it "discards arrays when pool is full" do
      pool = described_class.new(size: 1, preallocate: true)

      new_array = [1, 2, 3]
      result = pool.release(new_array)

      expect(result).to be false
      stats = pool.statistics
      expect(stats[:discarded]).to eq(1)
    end

    it "handles arrays with mixed content types" do
      pool = described_class.new(size: 10, preallocate: false)

      array = pool.acquire
      array << 1 << "string" << :symbol << { key: "value" }

      pool.release(array)

      expect(array).to be_empty
    end
  end

  describe "integration with parsing patterns" do
    it "works for collecting repetition results" do
      pool = described_class.new(size: 5, preallocate: false)

      # Simulate repetition collection
      result = pool.acquire
      5.times { |i| result << "item#{i}" }

      expect(result.size).to eq(5)
      expect(result.first).to eq("item0")
      expect(result.last).to eq("item4")

      pool.release(result)

      stats = pool.statistics
      expect(stats[:available]).to eq(1)
    end

    it "works for building sequence results" do
      pool = described_class.new(size: 5, preallocate: false)

      # Simulate sequence building
      sequence = pool.acquire
      sequence << { a: 1 }
      sequence << { b: 2 }
      sequence << { c: 3 }

      expect(sequence).to eq([{ a: 1 }, { b: 2 }, { c: 3 }])

      pool.release(sequence)
    end

    it "works for accumulating alternatives" do
      pool = described_class.new(size: 5, preallocate: false)

      # Simulate alternative accumulation
      alternatives = pool.acquire
      alternatives << :choice1
      alternatives << :choice2

      expect(alternatives).to eq(%i[choice1 choice2])

      pool.release(alternatives)
    end
  end

  describe "performance characteristics" do
    it "shows high reuse rate with pooling" do
      pool = described_class.new(size: 50, preallocate: false)

      # Create initial arrays
      arrays = Array.new(30) do |i|
        arr = pool.acquire
        arr << i
        arr
      end

      # Release all
      arrays.each { |a| pool.release(a) }

      # Acquire again - should all be reused
      30.times { pool.acquire }

      stats = pool.statistics
      expect(stats[:created]).to eq(30)
      expect(stats[:reused]).to eq(30)
      expect(stats[:utilization]).to eq(50.0)
    end

    it "handles rapid acquire/release cycles" do
      pool = described_class.new(size: 10, preallocate: false)

      100.times do |i|
        array = pool.acquire
        array << i
        pool.release(array)
      end

      stats = pool.statistics
      # Should have high reuse, low creation
      expect(stats[:created]).to be <= 10
      expect(stats[:reused]).to be >= 90
    end

    it "minimizes allocations with pre-allocation" do
      pool = described_class.new(size: 50, preallocate: true)

      # Use pre-allocated arrays
      50.times { pool.acquire }

      stats = pool.statistics
      expect(stats[:created]).to eq(0)  # No new allocations
      expect(stats[:reused]).to eq(50)  # All from pool
    end
  end

  describe "memory efficiency" do
    it "reuses array memory for different contents" do
      pool = described_class.new(size: 5, preallocate: false)

      # First use
      array1 = pool.acquire
      array1 << 1 << 2 << 3
      original_id = array1.object_id
      pool.release(array1)

      # Second use - different content
      array2 = pool.acquire
      array2 << "a" << "b"

      expect(array2.object_id).to eq(original_id)
      expect(array2).to eq(%w[a b])
    end

    it "prevents memory leaks from unreleased arrays" do
      pool = described_class.new(size: 5, preallocate: false)

      # Simulate forgetting to release
      10.times { pool.acquire }

      stats = pool.statistics
      expect(stats[:created]).to eq(10)
      expect(stats[:available]).to eq(0)

      # Pool size unchanged (no leak in pool itself)
      expect(pool.size).to eq(5)
    end
  end

  describe "statistics" do
    it "tracks array-specific operations" do
      pool = described_class.new(size: 5, preallocate: false)

      # Create 3 arrays
      a1 = pool.acquire
      a2 = pool.acquire
      a3 = pool.acquire

      # Add content
      a1 << 1
      a2 << 2
      a3 << 3

      # Release 2
      pool.release(a1)
      pool.release(a2)

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
    it "handles empty arrays" do
      pool = described_class.new(size: 5, preallocate: false)
      array = pool.acquire

      expect(array).to be_empty
      pool.release(array)
      expect(array).to be_empty
    end

    it "handles large arrays" do
      pool = described_class.new(size: 5, preallocate: false)
      array = pool.acquire

      1000.times { |i| array << i }
      expect(array.size).to eq(1000)

      pool.release(array)
      expect(array).to be_empty
    end

    it "handles nested arrays" do
      pool = described_class.new(size: 5, preallocate: false)
      array = pool.acquire

      array << [1, 2, 3]
      array << [4, 5, 6]

      expect(array).to eq([[1, 2, 3], [4, 5, 6]])

      pool.release(array)
      expect(array).to be_empty
    end

    it "handles arrays with nil values" do
      pool = described_class.new(size: 5, preallocate: false)
      array = pool.acquire

      array << nil << nil << 1

      expect(array).to eq([nil, nil, 1])

      pool.release(array)
      expect(array).to be_empty
    end
  end

  describe "concurrent usage simulation" do
    it "handles multiple acquire/release patterns" do
      pool = described_class.new(size: 10, preallocate: false)

      # Pattern 1: Short-lived arrays
      5.times do
        arr = pool.acquire
        arr << :temp
        pool.release(arr)
      end

      # Pattern 2: Long-lived arrays
      long_lived = Array.new(3) { pool.acquire }

      # Pattern 3: More short-lived
      5.times do
        arr = pool.acquire
        arr << :temp2
        pool.release(arr)
      end

      # Release long-lived
      long_lived.each { |arr| pool.release(arr) }

      stats = pool.statistics
      expect(stats[:created]).to be <= 10
      expect(stats[:reused]).to be > 0
    end
  end
end
