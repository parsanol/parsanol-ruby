# frozen_string_literal: true

require 'spec_helper'
require 'json'

describe Parsanol::Serialized do
  let(:parser_class) do
    Class.new(Parsanol::Parser) do
      include Parsanol::Serialized

      rule(:number) { match('[0-9]').repeat(1).as(:int) }
      rule(:space) { match('\s').repeat }
      rule(:add_op) { match('[+-]').as(:op) >> space }
      rule(:expression) { (number.as(:left) >> add_op.as(:op) >> expression.as(:right)).as(:binop) | number }
      root(:expression)
    end
  end

  let(:parser) { parser_class.new }

  describe '#parse_to_json' do
    context 'when native extension is not available' do
      before do
        allow(Parsanol::Native).to receive(:available?).and_return(false)
      end

      it 'raises LoadError' do
        expect { parser.parse_to_json('42') }.to raise_error(LoadError, /Serialized mode requires native extension/)
      end
    end
  end

  describe '#parse_to_struct' do
    context 'when native extension is not available' do
      before do
        allow(Parsanol::Native).to receive(:available?).and_return(false)
      end

      it 'raises LoadError' do
        deserializer = Class.new do
          def self.from_json(json); JSON.parse(json); end
        end
        expect { parser.parse_to_struct('42', deserializer) }.to raise_error(LoadError)
      end
    end
  end

  describe '#parse' do
    context 'when native extension is not available' do
      before do
        allow(Parsanol::Native).to receive(:available?).and_return(false)
      end

      it 'raises LoadError' do
        expect { parser.parse('42') }.to raise_error(LoadError, /Serialized mode requires native extension/)
      end
    end
  end

  describe '.output_schema' do
    it 'allows defining output schema' do
      parser_class.output_schema(
        number: { type: :integer },
        binop: { type: :object, properties: [:left, :op, :right] }
      )
      expect(parser_class.output_schema).to be_a(Hash)
    end
  end
end
