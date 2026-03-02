# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::RubyTransform do
  let(:parser_class) do
    Class.new(Parsanol::Parser) do
      include Parsanol::RubyTransform

      rule(:number) { match('[0-9]').repeat(1).as(:int) }
      rule(:space?) { match('\s').repeat }
      rule(:add_op) { space? >> match('[+-]').as(:op) >> space? }
      rule(:expression) { (number.as(:left) >> add_op.as(:op) >> expression.as(:right)).as(:binop) | number }
      root(:expression)
    end
  end

  let(:parser) { parser_class.new }

  describe '.parse_backend' do
    it 'defaults to :ruby' do
      expect(parser_class.parse_backend).to eq(:ruby)
    end

    it 'can be set to :rust' do
      parser_class.parse_backend = :rust
      expect(parser_class.parse_backend).to eq(:rust)
    end
  end

  describe '.use_rust_backend!' do
    context 'when native extension is not available' do
      before do
        allow(Parsanol::Native).to receive(:available?).and_return(false)
      end

      it 'raises LoadError' do
        expect { parser_class.use_rust_backend! }.to raise_error(LoadError, /Rust backend requested/)
      end
    end
  end

  describe '#parse' do
    it 'parses input and returns a tree' do
      result = parser.parse('42')
      expect(result).to eq({ int: '42' })
    end

    it 'parses complex expressions' do
      result = parser.parse('1 + 2')
      expect(result).to be_a(Hash)
      expect(result[:binop][:left]).to eq({ int: '1' })
    end
  end

  describe '#parse_with_transform' do
    let(:transform) do
      Class.new(Parsanol::Transform) do
        rule(int: simple(:n)) { Integer(n) }
        rule(left: simple(:l), op: { op: simple(:o) }, right: simple(:r)) { { left: l, op: o, right: r } }
        rule(binop: simple(:b)) { b }
      end.new
    end

    it 'parses and transforms in one step' do
      result = parser.parse_with_transform('42', transform)
      expect(result).to eq(42)
    end
  end
end
