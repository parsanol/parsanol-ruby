# frozen_string_literal: true

require "spec_helper"

describe "Parsanol::Parslet compatibility layer" do
  describe "module structure" do
    it "provides Parsanol::Parslet as a nested module" do
      expect(defined?(Parsanol::Parslet)).to eq("constant")
      expect(Parsanol::Parslet).to be_a(Module)
    end

    it "provides Parslet-compatible API through nested module" do
      expect(Parsanol::Parslet::Parser).to eq(Parsanol::Parser)
      expect(Parsanol::Parslet::Transform).to eq(Parsanol::Transform)
    end
  end

  describe "DSL methods" do
    it "delegates match to Parsanol" do
      expect(Parsanol::Parslet.match("[a-z]")).to be_a(Parsanol::Atoms::Re)
    end

    it "delegates str to Parsanol" do
      expect(Parsanol::Parslet.str("hello")).to be_a(Parsanol::Atoms::Str)
    end

    it "delegates any to Parsanol" do
      expect(Parsanol::Parslet.any).to be_a(Parsanol::Atoms::Re)
    end

    it "delegates simple to Parsanol" do
      expect(Parsanol::Parslet.simple(:x)).to be_a(Parsanol::Pattern::SimpleBind)
    end

    it "delegates sequence to Parsanol" do
      expect(Parsanol::Parslet.sequence(:x)).to be_a(Parsanol::Pattern::SequenceBind)
    end

    it "delegates subtree to Parsanol" do
      expect(Parsanol::Parslet.subtree(:x)).to be_a(Parsanol::Pattern::SubtreeBind)
    end
  end

  describe "class aliases" do
    it "aliases Parser to Parsanol::Parser" do
      expect(Parsanol::Parslet::Parser).to eq(Parsanol::Parser)
    end

    it "aliases Transform to Parsanol::Transform" do
      expect(Parsanol::Parslet::Transform).to eq(Parsanol::Transform)
    end

    it "aliases Slice to Parsanol::Slice" do
      expect(Parsanol::Parslet::Slice).to eq(Parsanol::Slice)
    end

    it "aliases Source to Parsanol::Source" do
      expect(Parsanol::Parslet::Source).to eq(Parsanol::Source)
    end

    it "aliases Cause to Parsanol::Cause" do
      expect(Parsanol::Parslet::Cause).to eq(Parsanol::Cause)
    end

    it "aliases Pattern to Parsanol::Pattern" do
      expect(Parsanol::Parslet::Pattern).to eq(Parsanol::Pattern)
    end
  end

  describe "Atoms module" do
    it "aliases Base to Parsanol::Atoms::Base" do
      expect(Parsanol::Parslet::Atoms::Base).to eq(Parsanol::Atoms::Base)
    end

    it "aliases Str to Parsanol::Atoms::Str" do
      expect(Parsanol::Parslet::Atoms::Str).to eq(Parsanol::Atoms::Str)
    end

    it "aliases Re to Parsanol::Atoms::Re" do
      expect(Parsanol::Parslet::Atoms::Re).to eq(Parsanol::Atoms::Re)
    end

    it "aliases Sequence to Parsanol::Atoms::Sequence" do
      expect(Parsanol::Parslet::Atoms::Sequence).to eq(Parsanol::Atoms::Sequence)
    end

    it "aliases Alternative to Parsanol::Atoms::Alternative" do
      expect(Parsanol::Parslet::Atoms::Alternative).to eq(Parsanol::Atoms::Alternative)
    end

    it "aliases Repetition to Parsanol::Atoms::Repetition" do
      expect(Parsanol::Parslet::Atoms::Repetition).to eq(Parsanol::Atoms::Repetition)
    end

    it "aliases Named to Parsanol::Atoms::Named" do
      expect(Parsanol::Parslet::Atoms::Named).to eq(Parsanol::Atoms::Named)
    end

    it "aliases Entity to Parsanol::Atoms::Entity" do
      expect(Parsanol::Parslet::Atoms::Entity).to eq(Parsanol::Atoms::Entity)
    end

    it "aliases Lookahead to Parsanol::Atoms::Lookahead" do
      expect(Parsanol::Parslet::Atoms::Lookahead).to eq(Parsanol::Atoms::Lookahead)
    end

    it "aliases Cut to Parsanol::Atoms::Cut" do
      expect(Parsanol::Parslet::Atoms::Cut).to eq(Parsanol::Atoms::Cut)
    end

    it "aliases Capture to Parsanol::Atoms::Capture" do
      expect(Parsanol::Parslet::Atoms::Capture).to eq(Parsanol::Atoms::Capture)
    end

    it "aliases Scope to Parsanol::Atoms::Scope" do
      expect(Parsanol::Parslet::Atoms::Scope).to eq(Parsanol::Atoms::Scope)
    end

    it "aliases Dynamic to Parsanol::Atoms::Dynamic" do
      expect(Parsanol::Parslet::Atoms::Dynamic).to eq(Parsanol::Atoms::Dynamic)
    end

    it "aliases Infix to Parsanol::Atoms::Infix" do
      expect(Parsanol::Parslet::Atoms::Infix).to eq(Parsanol::Atoms::Infix)
    end

    it "aliases Ignored to Parsanol::Atoms::Ignored" do
      expect(Parsanol::Parslet::Atoms::Ignored).to eq(Parsanol::Atoms::Ignored)
    end

    it "aliases ParseFailed to Parsanol::ParseFailed" do
      expect(Parsanol::Parslet::Atoms::ParseFailed).to eq(Parsanol::ParseFailed)
    end
  end

  describe "parser usage" do
    let(:parser_class) do
      Class.new(Parsanol::Parslet::Parser) do
        include Parsanol::Parslet

        rule(:number) { match("[0-9]").repeat(1).as(:int) }
        root(:number)
      end
    end

    it "parses input correctly" do
      parser = parser_class.new
      result = parser.parse("42")
      expect(result).to eq({ int: "42" })
    end
  end

  describe "transform usage" do
    let(:transform_class) do
      Class.new(Parsanol::Parslet::Transform) do
        rule(int: simple(:n)) { Integer(n) }
      end
    end

    it "transforms input correctly" do
      transform = transform_class.new
      result = transform.apply({ int: "42" })
      expect(result).to eq(42)
    end
  end
end
