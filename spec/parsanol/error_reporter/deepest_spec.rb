# frozen_string_literal: true

require "spec_helper"

describe Parsanol::ErrorReporter::Deepest do
  let(:reporter) { described_class.new }
  let(:fake_source) { double("source") }

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

  describe "shared cause subtrees" do
    def cause(pos, children = nil)
      Struct.new(:pos, :children).new(pos, children)
    end

    # The walk before memoisation, kept as the reference answer.
    def reference_leaf(node, rank = 0)
      return [rank, node] if node.nil?

      best = [rank, node]
      (node.children || []).each do |kid|
        next if kid.nil?

        kid_best = reference_leaf(kid, rank + 1)
        best = kid_best if kid_best.first > best.first
      end
      best
    end

    it "keeps the first deepest leaf in child order, as the recursive walk did" do
      leaf_a = cause(1)
      leaf_b = cause(2)
      root = cause(0, [cause(3, [leaf_a]), nil, cause(4, [leaf_b])])

      expect(reporter.send(:find_deepest_leaf, root, 2)).to eq([4, leaf_a])
      expect(reporter.send(:find_deepest_leaf, root, 2)).to eq(reference_leaf(root, 2))
    end

    it "matches the recursive walk on random trees that share subtrees" do
      rng = Random.new(541)
      pool = Array.new(6) { |i| cause(i) }
      40.times do |i|
        kids = Array.new(rng.rand(0..3)) { rng.rand < 0.1 ? nil : pool.sample(random: rng) }
        pool << cause(100 + i, kids)
      end
      pool.last(10).each do |root|
        expect(reporter.send(:find_deepest_leaf, root)).to eq(reference_leaf(root))
      end
    end

    it "stays fast when every level reuses the level below twice" do
      node = cause(0)
      60.times { |i| node = cause(i + 1, [node, node]) }

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      depth, leaf = reporter.send(:find_deepest_leaf, node)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect([depth, leaf.pos]).to eq([60, 0])
      expect(elapsed).to be < 1
    end
  end
end
