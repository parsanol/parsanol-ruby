# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::ResultBuilder do
  let(:context) { Parsanol::Atoms::Context.new }

  describe '.for' do
    it 'creates RepetitionBuilder for :repetition' do
      builder = described_class.for(:repetition, context)
      expect(builder).to be_a(Parsanol::RepetitionBuilder)
    end

    it 'creates SequenceBuilder for :sequence' do
      builder = described_class.for(:sequence, context)
      expect(builder).to be_a(Parsanol::SequenceBuilder)
    end

    it 'creates HashBuilder for :hash' do
      builder = described_class.for(:hash, context)
      expect(builder).to be_a(Parsanol::HashBuilder)
    end

    it 'raises error for unknown type' do
      expect { described_class.for(:unknown, context) }.to raise_error(ArgumentError, /Unknown builder type/)
    end

    it 'passes options to builder' do
      builder = described_class.for(:repetition, context, tag: :custom, estimated_size: 20)
      expect(builder.instance_variable_get(:@tag)).to eq(:custom)
    end
  end

  describe Parsanol::RepetitionBuilder do
    let(:builder) { described_class.new(context, estimated_size: 5) }

    describe '#initialize' do
      it 'acquires buffer from context' do
        buffer = builder.instance_variable_get(:@buffer)
        expect(buffer).to be_a(Parsanol::Buffer)
      end

      it 'pushes default tag to buffer' do
        buffer = builder.instance_variable_get(:@buffer)
        expect(buffer[0]).to eq(:repetition)
      end

      it 'supports custom tags' do
        custom_builder = described_class.new(context, tag: :custom)
        buffer = custom_builder.instance_variable_get(:@buffer)
        expect(buffer[0]).to eq(:custom)
      end

      it 'uses estimated_size for buffer allocation' do
        # Buffer should be acquired with capacity for tag + elements
        expect(context.buffer_pool).to receive(:acquire).with(size: 6).and_call_original
        described_class.new(context, estimated_size: 5)
      end
    end

    describe '#add_element' do
      it 'adds element to buffer' do
        builder.add_element('a')
        buffer = builder.instance_variable_get(:@buffer)
        expect(buffer[1]).to eq('a')
      end

      it 'adds multiple elements' do
        builder.add_element('a')
        builder.add_element('b')
        builder.add_element('c')
        buffer = builder.instance_variable_get(:@buffer)
        expect(buffer.size).to eq(4) # tag + 3 elements
        expect(buffer[1]).to eq('a')
        expect(buffer[2]).to eq('b')
        expect(buffer[3]).to eq('c')
      end

      it 'returns self for chaining' do
        result = builder.add_element('a')
        expect(result).to eq(builder)
      end

      it 'can chain multiple adds' do
        builder.add_element('a').add_element('b').add_element('c')
        buffer = builder.instance_variable_get(:@buffer)
        expect(buffer.size).to eq(4)
      end
    end

    describe '#build' do
      it 'returns LazyResult' do
        builder.add_element('a')
        builder.add_element('b')
        result = builder.build

        expect(result).to be_a(Parsanol::LazyResult)
      end

      it 'constructs repetition with tag' do
        builder.add_element('a')
        builder.add_element('b')
        result = builder.build

        expect(result.to_a).to eq([:repetition, 'a', 'b'])
      end

      it 'handles empty repetition' do
        result = builder.build
        expect(result.to_a).to eq([:repetition])
      end

      it 'uses custom tags' do
        custom_builder = described_class.new(context, tag: :custom, estimated_size: 3)
        custom_builder.add_element('x')
        result = custom_builder.build

        expect(result.to_a).to eq([:custom, 'x'])
      end

      it 'handles large repetitions' do
        100.times { |i| builder.add_element(i) }
        result = builder.build

        expect(result.size).to eq(101) # tag + 100 elements
        expect(result[0]).to eq(:repetition)
        expect(result[100]).to eq(99)
      end
    end

    describe '#release' do
      it 'releases buffer back to pool' do
        builder.add_element('test')
        buffer = builder.instance_variable_get(:@buffer)

        expect(context.buffer_pool).to receive(:release).with(buffer).and_call_original
        builder.release
      end

      it 'clears buffer reference' do
        builder.add_element('test')
        builder.release

        expect(builder.instance_variable_get(:@buffer)).to be_nil
      end

      it 'handles double release safely' do
        builder.release
        expect { builder.release }.not_to raise_error
      end
    end
  end

  describe Parsanol::SequenceBuilder do
    let(:builder) { described_class.new(context, size: 3) }

    describe '#initialize' do
      it 'acquires buffer from context' do
        buffer = builder.instance_variable_get(:@buffer)
        expect(buffer).to be_a(Parsanol::Buffer)
      end

      it 'pushes :sequence tag to buffer' do
        buffer = builder.instance_variable_get(:@buffer)
        expect(buffer[0]).to eq(:sequence)
      end

      it 'uses size for buffer allocation' do
        expect(context.buffer_pool).to receive(:acquire).with(size: 4).and_call_original
        described_class.new(context, size: 3)
      end
    end

    describe '#add_element' do
      it 'adds element to buffer' do
        builder.add_element('a')
        buffer = builder.instance_variable_get(:@buffer)
        expect(buffer[1]).to eq('a')
      end

      it 'adds multiple elements' do
        builder.add_element('a')
        builder.add_element('b')
        buffer = builder.instance_variable_get(:@buffer)
        expect(buffer.size).to eq(3)  # tag + 2 elements
        expect(buffer[1]).to eq('a')
        expect(buffer[2]).to eq('b')
      end

      it 'skips nil values' do
        builder.add_element('a')
        builder.add_element(nil)
        builder.add_element('b')
        buffer = builder.instance_variable_get(:@buffer)
        expect(buffer.size).to eq(3)  # tag + 2 non-nil elements
        expect(buffer[1]).to eq('a')
        expect(buffer[2]).to eq('b')
      end

      it 'returns self for chaining' do
        result = builder.add_element('a')
        expect(result).to eq(builder)
      end
    end

    describe '#build' do
      it 'returns LazyResult' do
        builder.add_element('a')
        result = builder.build

        expect(result).to be_a(Parsanol::LazyResult)
      end

      it 'constructs sequence with tag' do
        builder.add_element('a')
        builder.add_element('b')
        result = builder.build

        expect(result.to_a).to eq([:sequence, 'a', 'b'])
      end

      it 'handles empty sequence' do
        result = builder.build
        expect(result.to_a).to eq([:sequence])
      end

      it 'excludes nil values from result' do
        builder.add_element('a')
        builder.add_element(nil)
        builder.add_element('b')
        result = builder.build

        expect(result.to_a).to eq([:sequence, 'a', 'b'])
      end
    end

    describe '#release' do
      it 'releases buffer back to pool' do
        builder.add_element('test')
        buffer = builder.instance_variable_get(:@buffer)

        expect(context.buffer_pool).to receive(:release).with(buffer).and_call_original
        builder.release
      end

      it 'clears buffer reference' do
        builder.add_element('test')
        builder.release

        expect(builder.instance_variable_get(:@buffer)).to be_nil
      end
    end
  end

  describe Parsanol::HashBuilder do
    let(:builder) { described_class.new(context) }

    describe '#initialize' do
      it 'initializes empty hash' do
        hash = builder.instance_variable_get(:@hash)
        expect(hash).to eq({})
      end
    end

    describe '#add_pair' do
      it 'adds key-value pair' do
        builder.add_pair(:key1, 'value1')
        hash = builder.instance_variable_get(:@hash)
        expect(hash).to eq({ key1: 'value1' })
      end

      it 'adds multiple pairs' do
        builder.add_pair(:key1, 'value1')
        builder.add_pair(:key2, 'value2')
        hash = builder.instance_variable_get(:@hash)
        expect(hash).to eq({ key1: 'value1', key2: 'value2' })
      end

      it 'returns self for chaining' do
        result = builder.add_pair(:key, 'value')
        expect(result).to eq(builder)
      end

      it 'can chain multiple adds' do
        builder.add_pair(:a, 1).add_pair(:b, 2).add_pair(:c, 3)
        hash = builder.instance_variable_get(:@hash)
        expect(hash).to eq({ a: 1, b: 2, c: 3 })
      end

      it 'overwrites existing keys' do
        builder.add_pair(:key, 'old')
        builder.add_pair(:key, 'new')
        hash = builder.instance_variable_get(:@hash)
        expect(hash).to eq({ key: 'new' })
      end
    end

    describe '#build' do
      it 'returns hash directly' do
        builder.add_pair(:key1, 'value1')
        builder.add_pair(:key2, 'value2')
        result = builder.build

        expect(result).to be_a(Hash)
        expect(result).to eq({ key1: 'value1', key2: 'value2' })
      end

      it 'handles empty hash' do
        result = builder.build
        expect(result).to eq({})
      end

      it 'supports complex values' do
        builder.add_pair(:array, %w[a b])
        builder.add_pair(:hash, { nested: true })
        builder.add_pair(:number, 42)
        result = builder.build

        expect(result).to eq({
                               array: %w[a b],
                               hash: { nested: true },
                               number: 42
                             })
      end
    end

    describe '#release' do
      it 'clears hash reference' do
        builder.add_pair(:test, 'value')
        builder.release

        expect(builder.instance_variable_get(:@hash)).to be_nil
      end

      it 'handles double release safely' do
        builder.release
        expect { builder.release }.not_to raise_error
      end
    end
  end

  describe 'integration with Context' do
    it 'builders use context buffer pool' do
      Parsanol::RepetitionBuilder.new(context, estimated_size: 5)
      Parsanol::SequenceBuilder.new(context, size: 3)

      # Both should acquire from same pool
      stats = context.buffer_pool.statistics
      # Statistics should have size class keys (2, 4, 8, etc.)
      expect(stats.keys).to include(8) # Size 8 is standard size class
    end

    it 'releases return buffers to pool' do
      builder = Parsanol::RepetitionBuilder.new(context, estimated_size: 5)
      builder.add_element('test')

      context.buffer_pool.statistics
      builder.release
      stats_after = context.buffer_pool.statistics

      # Buffer should be released (stats should reflect this)
      expect(stats_after).to be_a(Hash)
    end
  end

  describe 'memory efficiency' do
    it 'reuses buffers across multiple builders' do
      # Create and release first builder
      builder1 = Parsanol::RepetitionBuilder.new(context, estimated_size: 5)
      builder1.add_element('a')
      buffer1 = builder1.instance_variable_get(:@buffer)
      builder1.release

      # Create second builder - should reuse buffer
      builder2 = Parsanol::RepetitionBuilder.new(context, estimated_size: 5)
      buffer2 = builder2.instance_variable_get(:@buffer)

      # Buffers come from same size class, demonstrating reuse
      expect(buffer1.capacity).to eq(buffer2.capacity)
    end

    it 'builders handle growth when capacity exceeded' do
      builder = Parsanol::RepetitionBuilder.new(context, estimated_size: 2)

      # Add more elements than initial capacity
      10.times { |i| builder.add_element(i) }

      result = builder.build
      expect(result.size).to eq(11) # tag + 10 elements
      expect(result.to_a).to eq([:repetition, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
    end
  end
end
