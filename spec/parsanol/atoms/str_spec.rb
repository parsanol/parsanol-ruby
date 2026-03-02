# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Atoms::Str do
  def str(s)
    described_class.new(s)
  end

  describe 'regression #1: multibyte characters' do
    it 'parses successfully (length check works)' do
      str('あああ').should parse('あああ')
    end
  end
end
