# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::ZeroCopy do
  # Define test AST classes
  before(:all) do
    module TestCalculator
      class Expr
        def eval
          raise NotImplementedError
        end
      end

      class Number < Expr
        attr_reader :value

        def initialize(value)
          @value = value
        end

        def eval = @value
      end

      class BinOp < Expr
        attr_reader :left, :op, :right

        def initialize(left:, op:, right:)
          @left = left
          @op = op
          @right = right
        end

        def eval
          case @op
          when '+' then @left.eval + @right.eval
          when '-' then @left.eval - @right.eval
          end
        end
      end
    end
  end

  let(:parser_class) do
    Class.new(Parsanol::Parser) do
      include Parsanol::ZeroCopy

      rule(:number) { match('[0-9]').repeat(1).as(:int) }
      rule(:space) { match('\s').repeat }
      rule(:add_op) { match('[+-]').as(:op) >> space }
      rule(:expression) { (number.as(:left) >> add_op.as(:op) >> expression.as(:right)).as(:binop) | number }
      root(:expression)
    end
  end

  let(:parser) { parser_class.new }

  describe '.output_types' do
    it 'allows defining output types' do
      parser_class.output_types(
        number: TestCalculator::Number,
        binop: TestCalculator::BinOp
      )
      expect(parser_class.output_types[:number]).to eq(TestCalculator::Number)
      expect(parser_class.output_types[:binop]).to eq(TestCalculator::BinOp)
    end

    it 'returns empty hash by default' do
      fresh_parser_class = Class.new(Parsanol::Parser) do
        include Parsanol::ZeroCopy
      end
      expect(fresh_parser_class.output_types).to eq({})
    end
  end

  describe '.output_type' do
    it 'allows defining a single output type' do
      parser_class.output_type(:number, TestCalculator::Number)
      expect(parser_class.output_types[:number]).to eq(TestCalculator::Number)
    end
  end

  describe '.output_types_for_ffi' do
    it 'converts types to FFI-compatible format' do
      parser_class.output_types(
        number: TestCalculator::Number,
        binop: TestCalculator::BinOp
      )
      ffi_types = parser_class.output_types_for_ffi
      expect(ffi_types['number']).to eq('TestCalculator::Number')
      expect(ffi_types['binop']).to eq('TestCalculator::BinOp')
    end
  end

  describe '#parse' do
    context 'when native extension is not available' do
      before do
        allow(Parsanol::Native).to receive(:available?).and_return(false)
      end

      it 'raises LoadError' do
        expect { parser.parse('42') }.to raise_error(LoadError, /ZeroCopy mode requires native extension/)
      end
    end

    context 'when output_types is not defined' do
      before do
        allow(Parsanol::Native).to receive(:available?).and_return(true)
        allow(Parsanol::Native).to receive(:serialize_grammar).and_return('{}')
      end

      it 'raises ArgumentError' do
        fresh_parser_class = Class.new(Parsanol::Parser) do
          include Parsanol::ZeroCopy

          rule(:test) { str('a') }
          root(:test)
        end
        fresh_parser = fresh_parser_class.new
        expect { fresh_parser.parse('a') }.to raise_error(ArgumentError, /ZeroCopy mode requires output_types/)
      end
    end
  end

  describe '#parse_with_types' do
    context 'when native extension is not available' do
      before do
        allow(Parsanol::Native).to receive(:available?).and_return(false)
      end

      it 'raises LoadError' do
        expect { parser.parse_with_types('42', {}) }.to raise_error(LoadError, /ZeroCopy mode requires native extension/)
      end
    end
  end

  # Tests for parse_to_ruby_objects FFI function
  # These tests verify that the new FFI function directly constructs
  # Parsanol::Slice objects without intermediate Hash markers.
  describe 'parse_to_ruby_objects FFI' do
    # Simple string match grammar
    let(:string_grammar) do
      {
        atoms: [{ Str: { pattern: 'hello' } }],
        root: 0
      }.to_json
    end

    # Named capture grammar
    let(:named_grammar) do
      {
        atoms: [
          { Str: { pattern: 'hello' } },
          { Named: { name: 'greeting', atom: 0 } }
        ],
        root: 1
      }.to_json
    end

    # Sequence grammar
    let(:sequence_grammar) do
      {
        atoms: [
          { Str: { pattern: 'hello' } },
          { Str: { pattern: ' ' } },
          { Str: { pattern: 'world' } },
          { Sequence: { atoms: [0, 1, 2] } }
        ],
        root: 3
      }.to_json
    end

    context 'with native extension available' do
      before do
        skip 'Native extension not available' unless Parsanol::Native.available?
      end

      it 'returns Slice object for simple string match' do
        result = Parsanol::Native.parse(string_grammar, 'hello')
        expect(result).to be_a(Parsanol::Slice)
        expect(result.to_s).to eq('hello')
        expect(result.offset).to eq(0)
      end

      it 'returns Hash with Slice values for named captures' do
        result = Parsanol::Native.parse(named_grammar, 'hello')
        expect(result).to be_a(Hash)
        expect(result.keys).to eq([:greeting])

        greeting = result[:greeting]
        expect(greeting).to be_a(Parsanol::Slice)
        expect(greeting.to_s).to eq('hello')
        expect(greeting.offset).to eq(0)
      end

      it 'returns joined Slice for sequences (matches Ruby parser)' do
        result = Parsanol::Native.parse(sequence_grammar, 'hello world')

        # Both Ruby and Native parsers join consecutive strings into a single Slice
        expect(result).to be_a(Parsanol::Slice)
        expect(result.to_s).to eq('hello world')
        expect(result.offset).to eq(0)
      end

      it 'preserves correct byte offsets for multi-byte characters' do
        # Test with input containing UTF-8 characters
        utf8_grammar = {
          atoms: [{ Str: { pattern: '日本語' } }],
          root: 0
        }.to_json

        result = Parsanol::Native.parse(utf8_grammar, '日本語')
        expect(result).to be_a(Parsanol::Slice)
        expect(result.to_s).to eq('日本語')
        expect(result.offset).to eq(0)
      end
    end
  end
end
