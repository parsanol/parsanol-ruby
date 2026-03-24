# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Pools::BufferPool do
  let(:pool) { described_class.new(pool_size: 10) }

  describe "#initialize" do
    it "creates pools for all size classes" do
      described_class::SIZE_CLASSES.each do |size|
        expect(pool.pools[size]).to be_a(Array)
        expect(pool.pools[size]).to be_empty
      end
    end

    it "initializes statistics for all size classes" do
      described_class::SIZE_CLASSES.each do |size|
        expect(pool.stats[size]).to include(
          created: 0,
          reused: 0,
          released: 0,
          discarded: 0,
        )
      end
    end

    it "uses custom pool size" do
      custom_pool = described_class.new(pool_size: 50)
      expect(custom_pool.instance_variable_get(:@pool_size)).to eq(50)
    end
  end

  describe "#acquire" do
    it "returns buffer with appropriate capacity" do
      buffer = pool.acquire(size: 5)

      expect(buffer).to be_a(Parsanol::Buffer)
      expect(buffer.capacity).to be >= 5
    end

    it "selects appropriate size class" do
      # Request size 5 should get size class 8
      buffer = pool.acquire(size: 5)
      expect(buffer.capacity).to eq(8)

      # Request size 10 should get size class 16
      buffer = pool.acquire(size: 10)
      expect(buffer.capacity).to eq(16)
    end

    it "creates new buffer when pool is empty" do
      pool.acquire(size: 4)

      expect(pool.stats[4][:created]).to eq(1)
      expect(pool.stats[4][:reused]).to eq(0)
    end

    it "reuses buffer when available in pool" do
      # First acquire and release
      buffer1 = pool.acquire(size: 4)
      pool.release(buffer1)

      # Second acquire should reuse
      buffer2 = pool.acquire(size: 4)

      expect(buffer2.object_id).to eq(buffer1.object_id)
      expect(pool.stats[4][:reused]).to eq(1)
    end

    it "handles power-of-2 size class selection" do
      test_cases = [
        [1, 2],
        [2, 2],
        [3, 4],
        [4, 4],
        [5, 8],
        [8, 8],
        [9, 16],
        [16, 16],
        [17, 32],
        [32, 32],
        [33, 64],
        [64, 64],
      ]

      test_cases.each do |requested, expected|
        buffer = pool.acquire(size: requested)
        expect(buffer.capacity).to eq(expected),
                                   "size #{requested} should get capacity #{expected}, got #{buffer.capacity}"
      end
    end

    it "handles sizes larger than standard classes" do
      # Size 100 should get next power of 2 (128)
      buffer = pool.acquire(size: 100)
      expect(buffer.capacity).to eq(128)
    end
  end

  describe "#release" do
    it "returns buffer to appropriate pool" do
      buffer = pool.acquire(size: 4)
      buffer.push("a")
      buffer.push("b")

      result = pool.release(buffer)

      expect(result).to be true
      expect(pool.pools[4].size).to eq(1)
      expect(pool.stats[4][:released]).to eq(1)
    end

    it "clears buffer before returning to pool" do
      buffer = pool.acquire(size: 4)
      buffer.push("a")
      buffer.push("b")

      pool.release(buffer)

      # Acquire again and verify it's cleared
      buffer2 = pool.acquire(size: 4)
      expect(buffer2.size).to eq(0)
      expect(buffer2.empty?).to be true
    end

    it "discards buffer when pool is full" do
      # Acquire 11 buffers (one more than pool size)
      buffers = []
      11.times do
        buffer = pool.acquire(size: 4)
        buffers << buffer
      end

      # Release all 11 - first 10 should succeed, 11th should be discarded
      released_count = 0
      discarded_count = 0

      buffers.each do |buffer|
        if pool.release(buffer)
          released_count += 1
        else
          discarded_count += 1
        end
      end

      expect(released_count).to eq(10)
      expect(discarded_count).to eq(1)
      expect(pool.stats[4][:discarded]).to eq(1)
    end

    it "discards buffer with non-standard size class" do
      # Create buffer with non-standard capacity
      buffer = Parsanol::Buffer.new(capacity: 100)
      result = pool.release(buffer)

      expect(result).to be false
    end
  end

  describe "#statistics" do
    before do
      # Create some activity
      3.times { pool.acquire(size: 2) }

      buffer = pool.acquire(size: 4)
      pool.release(buffer)

      pool.acquire(size: 4) # This should be reused
    end

    it "returns statistics for all size classes" do
      stats = pool.statistics

      described_class::SIZE_CLASSES.each do |size|
        expect(stats).to have_key(size)
      end
    end

    it "includes all statistic fields" do
      stats = pool.statistics[2]

      expect(stats).to include(
        :available,
        :created,
        :reused,
        :released,
        :discarded,
        :utilization,
      )
    end

    it "calculates utilization correctly" do
      stats = pool.statistics

      # Size 2: 3 created, 0 reused => 0% utilization
      expect(stats[2][:utilization]).to eq(0.0)

      # Size 4: 1 created, 1 reused => 50% utilization
      # (first acquire creates, release adds to pool, second acquire reuses)
      expect(stats[4][:utilization]).to eq(50.0)
    end

    it "shows available count" do
      stats = pool.statistics

      # Size 4 has 0 available (one released, one re-acquired)
      expect(stats[4][:available]).to eq(0)
    end

    it "tracks created count" do
      stats = pool.statistics

      expect(stats[2][:created]).to eq(3)
      expect(stats[4][:created]).to eq(1)
    end

    it "tracks reused count" do
      stats = pool.statistics

      expect(stats[2][:reused]).to eq(0)
      expect(stats[4][:reused]).to eq(1)
    end
  end

  describe "#clear!" do
    before do
      # Create some activity
      buffer = pool.acquire(size: 4)
      pool.release(buffer)

      buffer = pool.acquire(size: 8)
      pool.release(buffer)
    end

    it "clears all pools" do
      pool.clear!

      described_class::SIZE_CLASSES.each do |size|
        expect(pool.pools[size]).to be_empty
      end
    end

    it "resets all statistics" do
      pool.clear!

      described_class::SIZE_CLASSES.each do |size|
        expect(pool.stats[size]).to eq(
          created: 0,
          reused: 0,
          released: 0,
          discarded: 0,
        )
      end
    end
  end

  describe "buffer reuse lifecycle" do
    it "efficiently reuses buffers across acquire/release cycles" do
      # First cycle
      buffer1 = pool.acquire(size: 8)
      buffer1.push("a")
      pool.release(buffer1)

      # Second cycle - should reuse same buffer
      buffer2 = pool.acquire(size: 8)
      expect(buffer2.object_id).to eq(buffer1.object_id)
      expect(buffer2.empty?).to be true

      buffer2.push("b")
      pool.release(buffer2)

      # Third cycle - should still reuse
      buffer3 = pool.acquire(size: 8)
      expect(buffer3.object_id).to eq(buffer1.object_id)
      expect(buffer3.empty?).to be true

      stats = pool.statistics[8]
      expect(stats[:created]).to eq(1)
      expect(stats[:reused]).to eq(2)
    end
  end

  describe "size class selection edge cases" do
    it "handles exact size class match" do
      described_class::SIZE_CLASSES.each do |size|
        buffer = pool.acquire(size: size)
        expect(buffer.capacity).to eq(size)
      end
    end

    it "handles sizes between classes" do
      # 3 is between 2 and 4, should get 4
      buffer = pool.acquire(size: 3)
      expect(buffer.capacity).to eq(4)

      # 10 is between 8 and 16, should get 16
      buffer = pool.acquire(size: 10)
      expect(buffer.capacity).to eq(16)
    end

    it "handles zero and negative sizes" do
      buffer = pool.acquire(size: 0)
      expect(buffer.capacity).to eq(2)  # Smallest class

      buffer = pool.acquire(size: -5)
      expect(buffer.capacity).to eq(2)  # Smallest class
    end

    it "handles very large sizes" do
      buffer = pool.acquire(size: 1000)
      expect(buffer.capacity).to be >= 1000
      expect(buffer.capacity).to eq(1024) # Next power of 2
    end
  end

  describe "pool capacity management" do
    it "respects pool size limit per class" do
      buffers = []

      # Acquire and release more than pool_size
      15.times do
        buffer = pool.acquire(size: 4)
        buffers << buffer
      end

      # Release all
      released_count = 0
      discarded_count = 0

      buffers.each do |buffer|
        if pool.release(buffer)
          released_count += 1
        else
          discarded_count += 1
        end
      end

      expect(released_count).to eq(10)  # pool_size
      expect(discarded_count).to eq(5)  # overflow
      expect(pool.pools[4].size).to eq(10)
    end
  end

  describe "multiple size classes" do
    it "manages different size classes independently" do
      # Acquire from different classes
      buffer2 = pool.acquire(size: 2)
      buffer4 = pool.acquire(size: 4)
      buffer8 = pool.acquire(size: 8)

      pool.release(buffer2)
      pool.release(buffer4)
      pool.release(buffer8)

      # Each size class should have 1 buffer
      expect(pool.pools[2].size).to eq(1)
      expect(pool.pools[4].size).to eq(1)
      expect(pool.pools[8].size).to eq(1)

      # Statistics should be independent
      stats = pool.statistics
      expect(stats[2][:created]).to eq(1)
      expect(stats[4][:created]).to eq(1)
      expect(stats[8][:created]).to eq(1)
    end
  end
end
