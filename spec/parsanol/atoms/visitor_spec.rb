# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Atoms do
  include Parsanol

  let(:visitor) { double(:visitor) }

  describe Parsanol::Atoms::Str do
    let(:parslet) { str('foo') }

    it 'calls back visitor' do
      expect(visitor).to receive(:visit_str).with('foo').once

      parslet.accept(visitor)
    end
  end

  describe Parsanol::Atoms::Re do
    let(:parslet) { match['abc'] }

    it 'calls back visitor' do
      expect(visitor).to receive(:visit_re).with('[abc]').once

      parslet.accept(visitor)
    end
  end

  describe Parsanol::Atoms::Sequence do
    let(:parslet) { str('a') >> str('b') }

    it 'calls back visitor' do
      expect(visitor).to receive(:visit_sequence).with(Array).once

      parslet.accept(visitor)
    end
  end

  describe Parsanol::Atoms::Repetition do
    let(:parslet) { str('a').repeat(1, 2) }

    it 'calls back visitor' do
      expect(visitor).to receive(:visit_repetition).with(:repetition, 1, 2, Parsanol::Atoms::Base).once

      parslet.accept(visitor)
    end
  end

  describe Parsanol::Atoms::Alternative do
    let(:parslet) { str('a') | str('b') }

    it 'calls back visitor' do
      expect(visitor).to receive(:visit_alternative).with(Array).once

      parslet.accept(visitor)
    end
  end

  describe Parsanol::Atoms::Named do
    let(:parslet) { str('a').as(:a) }

    it 'calls back visitor' do
      expect(visitor).to receive(:visit_named).with(:a, Parsanol::Atoms::Base).once

      parslet.accept(visitor)
    end
  end

  describe Parsanol::Atoms::Entity do
    let(:parslet) { Parsanol::Atoms::Entity.new('foo', &-> {}) }

    it 'calls back visitor' do
      expect(visitor).to receive(:visit_entity).with('foo', Proc).once

      parslet.accept(visitor)
    end
  end

  describe Parsanol::Atoms::Lookahead do
    let(:parslet) { str('a').absent? }

    it 'calls back visitor' do
      expect(visitor).to receive(:visit_lookahead).with(false, Parsanol::Atoms::Base).once

      parslet.accept(visitor)
    end
  end

  describe '< Parsanol::Parser' do
    let(:parslet) do
      Class.new(Parsanol::Parser) do
        rule(:test_rule) { str('test') }
        root(:test_rule)
      end.new
    end

    it 'calls back to visitor' do
      expect(visitor).to receive(:visit_parser).with(Parsanol::Atoms::Base).once

      parslet.accept(visitor)
    end
  end
end
