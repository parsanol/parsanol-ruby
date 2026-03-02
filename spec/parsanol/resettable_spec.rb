# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Resettable do
  describe 'pooled classes' do
    it 'Slice includes Resettable' do
      expect(Parsanol::Slice.ancestors).to include(Parsanol::Resettable)
    end

    it 'Position includes Resettable' do
      expect(Parsanol::Position.ancestors).to include(Parsanol::Resettable)
    end

    it 'Buffer includes Resettable' do
      expect(Parsanol::Buffer.ancestors).to include(Parsanol::Resettable)
    end

    it 'StringView includes Resettable' do
      expect(Parsanol::StringView.ancestors).to include(Parsanol::Resettable)
    end
  end

  describe '#reset!' do
    it 'raises NotImplementedError by default' do
      klass = Class.new { include Parsanol::Resettable }
      instance = klass.new
      expect { instance.reset! }.to raise_error(NotImplementedError)
    end

    it 'returns self when implemented (Slice)' do
      slice = Parsanol::Slice.new(0, 'test', nil)
      result = slice.reset!(5, 'new', nil)
      expect(result).to eq(slice)
      expect(slice.content).to eq('new')
      expect(slice.offset).to eq(5)
    end

    it 'returns self when implemented (Position)' do
      position = Parsanol::Position.new('test', 0, 0)
      result = position.reset!('new', 5, 3)
      expect(result).to eq(position)
      expect(position.string).to eq('new')
      expect(position.bytepos).to eq(5)
      expect(position.charpos).to eq(3)
    end

    it 'returns self when implemented (Buffer)' do
      buffer = Parsanol::Buffer.new(capacity: 10)
      buffer.push('a')
      buffer.push('b')
      result = buffer.reset!
      expect(result).to eq(buffer)
      expect(buffer.size).to eq(0)
      expect(buffer.empty?).to be true
    end

    it 'returns self when implemented (StringView)' do
      view = Parsanol::StringView.new('test', offset: 0, length: 4)
      result = view.reset!('new string', 4, 3)
      expect(result).to eq(view)
      expect(view.string).to eq('new string')
      expect(view.offset).to eq(4)
      expect(view.length).to eq(3)
    end
  end

  describe 'explicit contract' do
    it 'provides a clear interface for object pooling' do
      # All resettable classes should respond to reset!
      expect(Parsanol::Slice.new).to respond_to(:reset!)
      expect(Parsanol::Position.new('test', 0)).to respond_to(:reset!)
      expect(Parsanol::Buffer.new).to respond_to(:reset!)
      expect(Parsanol::StringView.new('test')).to respond_to(:reset!)
    end

    it 'avoids duck-typing with respond_to? checks' do
      # The Resettable module provides an explicit contract
      # so code can use is_a?(Resettable) instead of respond_to?(:reset!)
      slice = Parsanol::Slice.new
      expect(slice.is_a?(Parsanol::Resettable)).to be true

      position = Parsanol::Position.new('test', 0)
      expect(position.is_a?(Parsanol::Resettable)).to be true

      buffer = Parsanol::Buffer.new
      expect(buffer.is_a?(Parsanol::Resettable)).to be true

      view = Parsanol::StringView.new('test')
      expect(view.is_a?(Parsanol::Resettable)).to be true
    end
  end
end
