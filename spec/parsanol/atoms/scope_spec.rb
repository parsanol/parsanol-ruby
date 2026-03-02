# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Atoms::Scope do
  include Parsanol
  include Parsanol::Atoms::DSL

  let(:context) { Parsanol::Atoms::Context.new(nil) }
  let(:captures) { context.captures }

  def inject(string, parser)
    source = Parsanol::Source.new(string)
    parser.apply(source, context, true)
  end

  let(:aabb) do
    scope do
      match['ab'].capture(:f) >> dynamic { |_s, c| str(c.captures[:f]) }
    end
  end
  it 'keeps values of captures outside' do
    captures[:f] = 'old_value'
    inject 'aa', aabb
    captures[:f].should == 'old_value'
  end
end
