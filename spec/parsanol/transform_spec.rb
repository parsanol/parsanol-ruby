# frozen_string_literal: true

require "spec_helper"

require "parsanol/parslet"

describe Parsanol::Transform do
  include Parsanol

  let(:transform) { described_class.new }

  A = Struct.new(:elt)
  B = Struct.new(:elt)
  C = Struct.new(:elt)
  Bi = Struct.new(:a, :b)

  describe "delayed construction" do
    context "given simple(:x) => A.new(x)" do
      before do
        transform.rule(simple(:x)) { |d| A.new(d[:x]) }
      end

      it "transforms 'a' into A.new('a')" do
        transform.apply("a").should == A.new("a")
      end

      it "transforms ['a', 'b'] into [A.new('a'), A.new('b')]" do
        transform.apply(%w[a b]).should ==
          [A.new("a"), A.new("b")]
      end
    end

    context "given rules on {:a => simple(:x)} and {:b => :_x}" do
      before do
        transform.rule(a: simple(:x)) { |d| A.new(d[:x]) }
        transform.rule(b: simple(:x)) { |d| B.new(d[:x]) }
      end

      it "transforms {:d=>{:b=>'c'}} into d => B('c')" do
        transform.apply({ d: { b: "c" } }).should == { d: B.new("c") }
      end

      it "transforms {:a=>{:b=>'c'}} into A(B('c'))" do
        transform.apply({ a: { b: "c" } }).should == A.new(B.new("c"))
      end
    end

    describe "pulling out subbranches" do
      before do
        transform.rule(a: { b: simple(:x) }, d: { e: simple(:y) }) do |d|
          Bi.new(*d.values_at(:x, :y))
        end
      end

      it "yields Bi.new('c', 'f')" do
        transform.apply(a: { b: "c" }, d: { e: "f" }).should ==
          Bi.new("c", "f")
      end
    end
  end

  describe "dsl construction" do
    let(:transform) do
      described_class.new do
        rule(simple(:x)) { A.new(x) }
      end
    end

    it "stills evaluate rules correctly" do
      transform.apply("a").should == A.new("a")
    end
  end

  describe "class construction" do
    class OptimusPrime < Parsanol::Transform
      rule(a: simple(:x)) { A.new(x) }
      rule(b: simple(:x)) { B.new(x) }
    end
    let(:transform) { OptimusPrime.new }

    it "evaluates rules" do
      transform.apply(a: "a").should == A.new("a")
    end

    context "optionally raise when no match found" do
      class BumbleBee < Parsanol::Transform
        def initialize(&block)
          super(raise_on_unmatch: true, &block)
        end
        rule(a: simple(:x)) { A.new(x) }
      end
      let(:transform) { BumbleBee.new }

      it "evaluates rules" do
        transform.apply(a: "a").should == A.new("a")
      end

      it "raises when no rules are matched" do
        lambda {
          transform.apply(z: "z")
        }.should raise_error(NotImplementedError, /Failed to match/)
      end
    end

    context "with inheritance" do
      class OptimusPrimeJunior < OptimusPrime
        rule(b: simple(:x)) { B.new(x.upcase) }
        rule(c: simple(:x)) { C.new(x) }
      end
      let(:transform) { OptimusPrimeJunior.new }

      it "inherits rules from its parent" do
        transform.apply(a: "a").should == A.new("a")
      end

      it "is able to override rules from its parent" do
        transform.apply(b: "b").should == B.new("B")
      end

      it "is able to define new rules" do
        transform.apply(c: "c").should == C.new("c")
      end
    end
  end

  describe "<- #call_on_match" do
    let(:bindings) { { foo: "test" } }

    context "when given a block of arity 1" do
      it "calls the block" do
        called = false
        transform.call_on_match(bindings, lambda do |_dict|
          called = true
        end)

        called.should == true
      end

      it "yields the bindings" do
        transform.call_on_match(bindings, lambda do |dict|
          dict.should == bindings
        end)
      end

      it "executes in the current context" do
        foo = "test"
        transform.call_on_match(bindings, lambda do |_dict|
          foo.should == "test"
        end)
      end
    end

    context "when given a block of arity 0" do
      it "calls the block" do
        called = false
        transform.call_on_match(bindings, proc do
          called = true
        end)

        called.should == true
      end

      it "has bindings as local variables" do
        transform.call_on_match(bindings, proc do
          foo.should == "test"
        end)
      end

      it "executes in its own context" do
        @bar = "test"
        transform.call_on_match(bindings, proc do
          instance_variable_get(:@bar).should_not == "test" if instance_variable_defined?(:@bar)
        end)
      end
    end
  end

  context "various transformations (regression)" do
    context "hashes" do
      it "are matched completely" do
        transform.rule(a: simple(:x)) { raise }
        transform.apply(a: "a", b: "b")
      end
    end
  end

  context "when not using the bindings as hash, but as local variables" do
    it "accesses the variables" do
      transform.rule(simple(:x)) { A.new(x) }
      transform.apply("a").should == A.new("a")
    end

    it "allows context as local variable" do
      transform.rule(simple(:x)) { foo }
      transform.apply("a", foo: "bar").should == "bar"
    end
  end
end
