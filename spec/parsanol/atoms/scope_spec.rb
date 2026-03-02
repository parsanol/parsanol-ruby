require 'spec_helper'

describe Parsanol::Atoms::Scope do
  include Parsanol
  include Parsanol::Atoms::DSL
  
  
  let(:context) { Parsanol::Atoms::Context.new(nil) }
  let(:captures) { context.captures }
  
  def inject string, parser
    source = Parsanol::Source.new(string)
    parser.apply(source, context, true)
  end
  
  let(:aabb) { 
    scope {
      match['ab'].capture(:f) >> dynamic { |s,c| str(c.captures[:f]) }
    }
  }
  it "keeps values of captures outside" do
    captures[:f] = 'old_value'
    inject 'aa', aabb
    captures[:f].should == 'old_value'
  end 
end