# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Source::RangeSearch do
  describe "<- #lbound" do
    context "for a simple array" do
      let(:ary) { [10, 20, 30, 40, 50] }

      before { ary.extend described_class }

      it "returns correct answers for numbers not in the array" do
        ary.lbound(5).should
        ary.lbound(15).should
        ary.lbound(25).should
        ary.lbound(35).should
        ary.lbound(45).should == 4
      end

      it "returns correct answers for numbers in the array" do
        ary.lbound(10).should
        ary.lbound(20).should
        ary.lbound(30).should
        ary.lbound(40).should == 4
      end

      it "covers right edge case" do
        ary.lbound(50).should be_nil
        ary.lbound(51).should be_nil
      end

      it "covers left edge case" do
        ary.lbound(0).should == 0
      end
    end

    context "for an empty array" do
      let(:ary) { [] }

      before { ary.extend described_class }

      it "returns nil" do
        ary.lbound(1).should be_nil
      end
    end
  end
end

describe Parsanol::Source::LineCache do
  describe "<- scan_for_line_endings" do
    context "calculating the line_and_columns" do
      let(:str) { "foo\nbar\nbazd" }

      it "returns the first line if we have no line ends" do
        subject.scan_for_line_endings(0, nil)
        subject.line_and_column(3).should

        subject.scan_for_line_endings(0, "")
        subject.line_and_column(5).should == [1, 6]
      end

      it "finds the right line starting from pos 0" do
        subject.scan_for_line_endings(0, str)
        subject.line_and_column(5).should
        subject.line_and_column(9).should == [3, 2]
      end

      it "finds the right line starting from pos 5" do
        subject.scan_for_line_endings(5, str)
        subject.line_and_column(11).should == [2, 3]
      end

      it "finds the right line if scannning the string multiple times" do
        subject.scan_for_line_endings(0, str)
        subject.scan_for_line_endings(0, "#{str}\nthe quick\nbrown fox")
        subject.line_and_column(10).should
        subject.line_and_column(24).should == [5, 2]
      end
    end
  end
end
