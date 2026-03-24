# frozen_string_literal: true

require "spec_helper"

describe Parsanol::ErrorReporter::Contextual do
  let(:reporter) { described_class.new }
  let(:fake_source) { double("source") }
  let(:fake_atom) { double("atom") }
  let(:fake_cause) { double("cause") }

  describe "#err" do
    before do
      allow(fake_source).to receive_messages(pos: 13, line_and_column: [1, 1])
    end

    it "returns the deepest cause" do
      expect(reporter).to receive(:deepest).and_return(:deepest)
      expect(reporter.err("parslet", fake_source, "message")).to eq(:deepest)
    end
  end

  describe "#err_at" do
    before do
      allow(fake_source).to receive_messages(pos: 13, line_and_column: [1, 1])
    end

    it "returns the deepest cause" do
      expect(reporter).to receive(:deepest).and_return(:deepest)
      expect(reporter.err("parslet", fake_source, "message",
                          13)).to eq(:deepest)
    end
  end

  describe "#deepest(cause)" do
    def fake_cause(pos = 13, children = nil)
      double("cause#{pos}", pos: pos, children: children)
    end

    context "when there is no deepest cause yet" do
      let(:cause) { fake_cause }

      it "returns the given cause" do
        reporter.deepest(cause).should == cause
      end
    end

    context "when the previous cause is deeper (no relationship)" do
      let(:previous) { fake_cause }

      before do
        reporter.deepest(previous)
      end

      it "returns the previous cause" do
        reporter.deepest(fake_cause(12))
          .should == previous
      end
    end

    context "when the previous cause is deeper (child)" do
      let(:previous) { fake_cause }

      before do
        reporter.deepest(previous)
      end

      it "returns the given cause" do
        given = fake_cause(12, [previous])
        reporter.deepest(given).should == given
      end
    end

    context "when the previous cause is shallower" do
      before do
        reporter.deepest(fake_cause)
      end

      it "stores the cause as deepest" do
        deeper = fake_cause(14)
        reporter.deepest(deeper)
        reporter.deepest_cause.should == deeper
      end
    end
  end

  describe "#reset" do
    before do
      allow(fake_source).to receive_messages(pos: Parsanol::Position.new(
        "source", 13, 13
      ), line_and_column: [1, 1])
    end

    it "resets deepest cause on success of sibling expression" do
      expect(reporter).to receive(:deepest).and_return(:deepest)
      expect(reporter.err("parslet", fake_source, "message")).to eq(:deepest)
      expect(reporter).to receive(:reset).once
      reporter.succ(fake_source)
    end
  end

  describe "label" do
    before do
      allow(fake_source).to receive_messages(pos: Parsanol::Position.new(
        "source", 13, 13
      ), line_and_column: [1, 1])
    end

    it "sets label if atom has one" do
      expect(fake_atom).to receive(:label).once.and_return("label")
      expect(fake_cause).to receive(:set_label).once
      expect(reporter).to receive(:deepest).and_return(fake_cause)
      expect(reporter.err(fake_atom, fake_source, "message")).to eq(fake_cause)
    end

    it "does not set label if atom does not have one" do
      expect(reporter).to receive(:deepest).and_return(:deepest)
      expect(fake_atom).not_to receive(:update_label)
      expect(reporter.err(fake_atom, fake_source, "message")).to eq(:deepest)
    end
  end
end
