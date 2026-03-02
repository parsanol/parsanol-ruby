# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Parsanol::BuilderCallbacks do
  let(:builder_class) do
    Class.new do
      include Parsanol::BuilderCallbacks

      attr_reader :events

      def initialize
        @events = []
      end

      def on_start(input)
        @events << [:start, input]
      end

      def on_success
        @events << [:success]
      end

      def on_error(message)
        @events << [:error, message]
      end

      def on_string(value, offset, length)
        @events << [:string, value, offset, length]
      end

      def on_int(value)
        @events << [:int, value]
      end

      def on_float(value)
        @events << [:float, value]
      end

      def on_bool(value)
        @events << [:bool, value]
      end

      def on_nil
        @events << [:nil]
      end

      def on_hash_start(size = nil)
        @events << [:hash_start, size]
      end

      def on_hash_end(size)
        @events << [:hash_end, size]
      end

      def on_hash_key(key)
        @events << [:hash_key, key]
      end

      def on_hash_value(key)
        @events << [:hash_value, key]
      end

      def on_array_start(size = nil)
        @events << [:array_start, size]
      end

      def on_array_element(index)
        @events << [:array_element, index]
      end

      def on_array_end(size)
        @events << [:array_end, size]
      end

      def on_named_start(name)
        @events << [:named_start, name]
      end

      def on_named_end(name)
        @events << [:named_end, name]
      end

      def finish
        @events
      end
    end
  end

  let(:builder) { builder_class.new }

  describe 'included methods' do
    it 'provides default no-op implementations' do
      noop_builder = Class.new { include Parsanol::BuilderCallbacks }.new

      expect { noop_builder.on_string('test', 0, 4) }.not_to raise_error
      expect { noop_builder.on_int(42) }.not_to raise_error
      expect { noop_builder.on_float(3.14) }.not_to raise_error
      expect { noop_builder.on_bool(true) }.not_to raise_error
      expect { noop_builder.on_nil }.not_to raise_error
      expect { noop_builder.on_hash_start(nil) }.not_to raise_error
      expect { noop_builder.on_hash_end(0) }.not_to raise_error
      expect { noop_builder.on_hash_key('name') }.not_to raise_error
      expect { noop_builder.on_array_start(nil) }.not_to raise_error
      expect { noop_builder.on_array_element(0) }.not_to raise_error
      expect { noop_builder.on_array_end(0) }.not_to raise_error
      expect { noop_builder.on_named_start('test') }.not_to raise_error
      expect { noop_builder.on_named_end('test') }.not_to raise_error
      expect { noop_builder.on_start('input') }.not_to raise_error
      expect { noop_builder.on_success }.not_to raise_error
      expect { noop_builder.on_error('msg') }.not_to raise_error
      expect { noop_builder.finish }.not_to raise_error
    end
  end

  describe 'callback invocations' do
    it 'records string callbacks' do
      builder.on_string('hello', 0, 5)
      expect(builder.events).to eq([[:string, 'hello', 0, 5]])
    end

    it 'records int callbacks' do
      builder.on_int(42)
      expect(builder.events).to eq([[:int, 42]])
    end

    it 'records float callbacks' do
      builder.on_float(3.14)
      expect(builder.events).to eq([[:float, 3.14]])
    end

    it 'records bool callbacks' do
      builder.on_bool(true)
      expect(builder.events).to eq([[:bool, true]])
    end

    it 'records nil callbacks' do
      builder.on_nil
      expect(builder.events).to eq([[:nil]])
    end

    it 'records hash callbacks' do
      builder.on_hash_start(nil)
      builder.on_hash_key('name')
      builder.on_string('John', 0, 4)
      builder.on_hash_end(1)

      expect(builder.events).to eq([
                                     [:hash_start, nil],
                                     [:hash_key, 'name'],
                                     [:string, 'John', 0, 4],
                                     [:hash_end, 1]
                                   ])
    end

    it 'records array callbacks' do
      builder.on_array_start(nil)
      builder.on_array_element(0)
      builder.on_int(1)
      builder.on_array_element(1)
      builder.on_int(2)
      builder.on_array_element(2)
      builder.on_int(3)
      builder.on_array_end(3)

      expect(builder.events).to eq([
                                     [:array_start, nil],
                                     [:array_element, 0],
                                     [:int, 1],
                                     [:array_element, 1],
                                     [:int, 2],
                                     [:array_element, 2],
                                     [:int, 3],
                                     [:array_end, 3]
                                   ])
    end

    it 'returns events from finish' do
      builder.on_string('test', 0, 4)
      expect(builder.finish).to eq([[:string, 'test', 0, 4]])
    end
  end
end

RSpec.describe Parsanol::Builders::DebugBuilder do
  let(:builder) { Parsanol::Builders::DebugBuilder.new }

  describe '#events' do
    it 'collects all event types' do
      builder.on_string('hello', 0, 5)
      builder.on_int(42)
      builder.on_float(3.14)
      builder.on_bool(true)
      builder.on_nil
      builder.on_hash_start(nil)
      builder.on_hash_key('name')
      builder.on_hash_end(1)
      builder.on_array_start(nil)
      builder.on_array_end(0)

      result = builder.finish

      expect(result).to include('string: "hello" @ 0(5)')
      expect(result).to include('int: 42')
      expect(result).to include('float: 3.14')
      expect(result).to include('bool: true')
      expect(result).to include('nil')
      expect(result).to include('hash_start(nil)')
      expect(result).to include('hash_end(1)')
      expect(result).to include('hash_key: "name"')
      expect(result).to include('array_start(nil)')
      expect(result).to include('array_end(0)')
    end
  end
end

RSpec.describe Parsanol::Builders::StringCollector do
  let(:builder) { Parsanol::Builders::StringCollector.new }

  describe '#strings' do
    it 'collects only string values' do
      builder.on_string('hello', 0, 5)
      builder.on_int(42)
      builder.on_string('world', 6, 5)

      expect(builder.strings).to eq(%w[hello world])
    end

    it 'returns strings from finish' do
      builder.on_string('test', 0, 4)
      expect(builder.finish).to eq(['test'])
    end
  end
end

RSpec.describe Parsanol::Builders::NodeCounter do
  let(:builder) { Parsanol::Builders::NodeCounter.new }

  describe '#counts' do
    it 'counts nodes by type' do
      builder.on_string('a', 0, 1)
      builder.on_string('b', 1, 1)
      builder.on_int(1)
      builder.on_int(2)
      builder.on_int(3)
      builder.on_float(1.0)
      builder.on_bool(true)
      builder.on_nil
      builder.on_hash_start(nil)
      builder.on_array_start(nil)
      builder.on_array_start(nil)

      expect(builder.counts[:string]).to eq(2)
      expect(builder.counts[:int]).to eq(3)
      expect(builder.counts[:float]).to eq(1)
      expect(builder.counts[:bool]).to eq(1)
      expect(builder.counts[:nil]).to eq(1)
      expect(builder.counts[:hash]).to eq(1)
      expect(builder.counts[:array]).to eq(2)
    end

    it 'returns counts from finish' do
      builder.on_string('test', 0, 4)
      builder.on_int(42)

      result = builder.finish
      expect(result[:string]).to eq(1)
      expect(result[:int]).to eq(1)
    end
  end
end

RSpec.describe Parsanol::Parallel do
  describe Parsanol::Parallel::Config do
    let(:config) { Parsanol::Parallel::Config.new }

    it 'has default values' do
      expect(config.num_threads).to be_nil
      expect(config.min_chunk_size).to eq(10)
    end

    it 'supports chaining' do
      result = config.with_num_threads(8).with_min_chunk_size(50)

      expect(result.num_threads).to eq(8)
      expect(result.min_chunk_size).to eq(50)
      expect(result).to eq(config)
    end
  end

  describe '.available_cores' do
    it 'returns an integer' do
      result = Parsanol::Parallel.available_cores
      expect(result).to be_a(Integer)
      expect(result).to be >= 1
    end
  end

  describe '.optimal_threads' do
    it 'returns minimum of cores and input count' do
      cores = Parsanol::Parallel.available_cores

      # Small input count
      expect(Parsanol::Parallel.optimal_threads(2)).to eq([2, cores].min)

      # Large input count
      expect(Parsanol::Parallel.optimal_threads(1000)).to eq(cores)
    end
  end

  describe '.parse_batch' do
    context 'when native extension is not available' do
      before do
        allow(Parsanol::Native).to receive(:available?).and_return(false)
      end

      it 'raises LoadError' do
        expect do
          Parsanol::Parallel.parse_batch('{}', ['input'])
        end.to raise_error(LoadError, /requires native extension/)
      end
    end
  end
end

RSpec.describe 'Native parse_with_builder integration', :native do
  # Define a simple parser for testing - captures only words, not spaces
  let(:simple_parser) do
    Class.new(Parsanol::Parser) do
      rule(:word) { match('[a-z]+').as(:word) }
      rule(:words) { word >> (match('\s') >> word).repeat }
      root(:words)
    end
  end

  describe 'Parsanol::Native.parse_with_builder' do
    context 'when native extension is available' do
      before do
        skip 'Native extension not available' unless Parsanol::Native.available?
      end

      it 'parses input using a custom builder callback' do
        grammar = Parsanol::Native.serialize_grammar(simple_parser.new.root)
        input = 'hello world'

        builder = Parsanol::Builders::StringCollector.new
        result = Parsanol::Native.parse_with_builder(grammar, input, builder)

        # The parser captures all matches including spaces
        expect(result).to include('hello', 'world')
      end

      it 'works with DebugBuilder' do
        grammar = Parsanol::Native.serialize_grammar(simple_parser.new.root)
        input = 'a b'

        builder = Parsanol::Builders::DebugBuilder.new
        result = Parsanol::Native.parse_with_builder(grammar, input, builder)

        expect(result).to be_a(String)
        expect(result).to include('string:')
      end

      it 'works with NodeCounter' do
        grammar = Parsanol::Native.serialize_grammar(simple_parser.new.root)
        input = 'one two three'

        builder = Parsanol::Builders::NodeCounter.new
        result = Parsanol::Native.parse_with_builder(grammar, input, builder)

        expect(result).to be_a(Hash)
        # At minimum we have 3 words, plus spaces (5 total matches)
        expect(result[:string]).to be >= 3
      end
    end
  end
end
