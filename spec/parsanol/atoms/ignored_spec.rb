# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Atoms::Ignored do
  include Parsanol

  describe "ignore" do
    it "ignores parts of the input" do
      str("a").ignore.parse("a").should
      nil
      (str("a") >> str("b").ignore >> str("c")).parse("abc").should
      (str("a") >> str("b").as(:name).ignore >> str("c")).parse("abc").should
      (str("a") >> str("b").maybe.ignore >> str("c")).parse("abc").should
      (str("a") >> str("b").maybe.ignore >> str("c")).parse("ac").should == "ac"
    end
  end
end
