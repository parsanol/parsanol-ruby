# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Atoms::Re do
  describe 'construction' do
    include Parsanol

    it 'should allow match(str) form' do
      match('[a]').should be_a(Parsanol::Atoms::Re)
    end
    it 'should allow match[str] form' do
      match['a'].should be_a(Parsanol::Atoms::Re)
    end
  end
end
