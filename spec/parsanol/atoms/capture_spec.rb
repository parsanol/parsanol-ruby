# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Atoms::Capture do
  include Parsanol

  let(:context) { Parsanol::Atoms::Context.new(nil) }

  def inject(string, parser)
    source = Parsanol::Source.new(string)
    parser.apply(source, context, true)
  end

  it "captures simple results" do
    inject "a", str("a").capture(:a)
    strip_positions(context.captures[:a]).should == "a"
  end

  it "captures complex results" do
    inject "a", str("a").as(:b).capture(:a)
    strip_positions(context.captures[:a]).should == { b: "a" }
  end
end
