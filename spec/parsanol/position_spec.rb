# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Position do
  slet(:position) { described_class.new("öäüö", 4, 2) }

  it "has a charpos of 2" do
    position.charpos.should == 2
  end

  it "has a bytepos of 4" do
    position.bytepos.should == 4
  end
end
