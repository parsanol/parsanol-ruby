# frozen_string_literal: true

require "spec_helper"

describe "ResultBuilder Integration" do
  include Parsanol

  let(:context) { Parsanol::Atoms::Context.new }

  describe "RepetitionBuilder infrastructure" do
    it "constructs repetition results using buffers" do
      builder = Parsanol::RepetitionBuilder.new(context, estimated_size: 3)
      builder.add_element("a")
      builder.add_element("b")
      builder.add_element("c")
      result = builder.build

      # Should be a LazyResult
      expect(result).to be_a(Parsanol::LazyResult)
      expect(result.to_a).to eq([:repetition, "a", "b", "c"])
    end

    it "handles variable length results" do
      builder = Parsanol::RepetitionBuilder.new(context, estimated_size: 2)

      # Add more than estimated
      10.times { |i| builder.add_element(i) }
      result = builder.build

      expect(result.size).to eq(11) # tag + 10 elements
      expect(result.to_a[0]).to eq(:repetition)
      expect(result.to_a[10]).to eq(9)
    end

    it "builds empty repetitions" do
      builder = Parsanol::RepetitionBuilder.new(context)
      result = builder.build

      expect(result.to_a).to eq([:repetition])
    end

    it "supports custom tags" do
      builder = Parsanol::RepetitionBuilder.new(context, tag: :my_list)
      builder.add_element("x")
      result = builder.build

      expect(result.to_a).to eq([:my_list, "x"])
    end
  end

  describe "SequenceBuilder infrastructure" do
    it "constructs sequence results using buffers" do
      builder = Parsanol::SequenceBuilder.new(context, size: 3)
      builder.add_element("a")
      builder.add_element("b")
      builder.add_element("c")
      result = builder.build

      expect(result).to be_a(Parsanol::LazyResult)
      expect(result.to_a).to eq([:sequence, "a", "b", "c"])
    end

    it "filters nil values automatically" do
      builder = Parsanol::SequenceBuilder.new(context, size: 4)
      builder.add_element("a")
      builder.add_element(nil)
      builder.add_element("b")
      builder.add_element(nil)
      builder.add_element("c")
      result = builder.build

      # Nils should be excluded
      expect(result.to_a).to eq([:sequence, "a", "b", "c"])
    end

    it "handles empty sequences" do
      builder = Parsanol::SequenceBuilder.new(context)
      result = builder.build

      expect(result.to_a).to eq([:sequence])
    end
  end

  describe "HashBuilder infrastructure" do
    it "constructs hash directly without arrays" do
      builder = Parsanol::HashBuilder.new(context)
      builder.add_pair(:name, "John")
      builder.add_pair(:age, 30)
      result = builder.build

      expect(result).to be_a(Hash)
      expect(result).to eq({ name: "John", age: 30 })
    end

    it "handles complex values" do
      builder = Parsanol::HashBuilder.new(context)
      builder.add_pair(:array, %w[a b c])
      builder.add_pair(:nested, { key: "value" })
      result = builder.build

      expect(result[:array]).to eq(%w[a b c])
      expect(result[:nested]).to eq({ key: "value" })
    end

    it "overwrites duplicate keys" do
      builder = Parsanol::HashBuilder.new(context)
      builder.add_pair(:key, "old")
      builder.add_pair(:key, "new")
      result = builder.build

      expect(result).to eq({ key: "new" })
    end
  end

  describe "nested builder usage" do
    it "builds nested repetition-sequence structures" do
      # Outer repetition
      outer_builder = Parsanol::RepetitionBuilder.new(context,
                                                      estimated_size: 3)

      # Inner sequences
      3.times do
        inner_builder = Parsanol::SequenceBuilder.new(context, size: 2)
        inner_builder.add_element("a")
        inner_builder.add_element("b")
        outer_builder.add_element(inner_builder.build)
      end

      result = outer_builder.build
      expect(result.size).to eq(4) # tag + 3 sequences
      expect(result[0]).to eq(:repetition)

      # Each element should be a sequence
      result.to_a[1..3].each do |elem|
        expect(elem).to be_a(Parsanol::LazyResult)
        expect(elem.to_a).to eq([:sequence, "a", "b"])
      end
    end

    it "builds repetition with hash elements" do
      builder = Parsanol::RepetitionBuilder.new(context, estimated_size: 2)

      hash_builder1 = Parsanol::HashBuilder.new(context)
      hash_builder1.add_pair(:x, 1)
      builder.add_element(hash_builder1.build)

      hash_builder2 = Parsanol::HashBuilder.new(context)
      hash_builder2.add_pair(:x, 2)
      builder.add_element(hash_builder2.build)

      result = builder.build
      expect(result.to_a).to eq([:repetition, { x: 1 }, { x: 2 }])
    end
  end

  describe "buffer lifecycle management" do
    it "releases buffers properly" do
      builder = Parsanol::RepetitionBuilder.new(context, estimated_size: 5)
      builder.add_element("test")

      # Get buffer reference
      buffer = builder.instance_variable_get(:@buffer)
      expect(buffer).not_to be_nil

      # Release should clear reference
      builder.release
      expect(builder.instance_variable_get(:@buffer)).to be_nil
    end

    it "buffers are reused from pool" do
      # Create and release first builder
      builder1 = Parsanol::RepetitionBuilder.new(context, estimated_size: 8)
      builder1.add_element("a")
      buffer1_capacity = builder1.instance_variable_get(:@buffer).capacity
      builder1.release

      # Create second builder with same size
      builder2 = Parsanol::RepetitionBuilder.new(context, estimated_size: 8)
      buffer2_capacity = builder2.instance_variable_get(:@buffer).capacity

      # Should get buffer from same size class
      expect(buffer2_capacity).to eq(buffer1_capacity)
    end

    it "handles builder release on failure" do
      builder = Parsanol::RepetitionBuilder.new(context, estimated_size: 3)
      builder.add_element("test")

      # Simulate failure scenario - release should work
      expect { builder.release }.not_to raise_error

      # Buffer should be cleared
      expect(builder.instance_variable_get(:@buffer)).to be_nil
    end
  end

  describe "performance characteristics" do
    it "defers materialization with LazyResult" do
      builder = Parsanol::RepetitionBuilder.new(context, estimated_size: 100)
      100.times { |i| builder.add_element(i) }
      result = builder.build

      # Result is lazy
      expect(result).to be_a(Parsanol::LazyResult)
      expect(result.instance_variable_get(:@materialized)).to be_nil

      # Accessing size doesn't materialize
      expect(result.size).to eq(101)
      expect(result.instance_variable_get(:@materialized)).to be_nil

      # Accessing array materializes
      result.to_a
      expect(result.instance_variable_get(:@materialized)).not_to be_nil
    end

    it "handles large structures efficiently" do
      builder = Parsanol::RepetitionBuilder.new(context, estimated_size: 1000)

      1000.times { |i| builder.add_element(i) }
      result = builder.build

      expect(result.size).to eq(1001)
      expect(result.to_a[0]).to eq(:repetition)
      expect(result.to_a[-1]).to eq(999)
    end

    it "caches materialized results" do
      builder = Parsanol::RepetitionBuilder.new(context, estimated_size: 50)
      50.times { |i| builder.add_element(i) }
      result = builder.build

      # First materialization
      array1 = result.to_a

      # Second call returns cached
      array2 = result.to_a
      expect(array2.object_id).to eq(array1.object_id)
    end
  end

  describe "factory method" do
    it "creates appropriate builder types" do
      rep_builder = Parsanol::ResultBuilder.for(:repetition, context,
                                                estimated_size: 5)
      expect(rep_builder).to be_a(Parsanol::RepetitionBuilder)

      seq_builder = Parsanol::ResultBuilder.for(:sequence, context, size: 3)
      expect(seq_builder).to be_a(Parsanol::SequenceBuilder)

      hash_builder = Parsanol::ResultBuilder.for(:hash, context)
      expect(hash_builder).to be_a(Parsanol::HashBuilder)
    end

    it "passes options correctly" do
      builder = Parsanol::ResultBuilder.for(:repetition, context, tag: :custom,
                                                                  estimated_size: 10)
      expect(builder.instance_variable_get(:@tag)).to eq(:custom)
    end
  end

  describe "compatibility with LazyResult" do
    it "builders produce results compatible with existing code" do
      builder = Parsanol::RepetitionBuilder.new(context, estimated_size: 3)
      builder.add_element("a")
      builder.add_element("b")
      result = builder.build

      # Should work as array
      expect(result.size).to eq(3)
      expect(result[0]).to eq(:repetition)
      expect(result.empty?).to be false

      # Should support enumerable
      mapped = result.map { |x| x }
      expect(mapped).to be_a(Array)
    end

    it "results are comparable to arrays" do
      builder = Parsanol::RepetitionBuilder.new(context, estimated_size: 2)
      builder.add_element("x")
      result = builder.build

      expect(result).to eq([:repetition, "x"])
      expect(result).to eq([:repetition, "x"])
    end
  end
end
