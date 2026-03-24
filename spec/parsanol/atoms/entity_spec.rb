# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Atoms::Entity do
  context "when constructed with str('bar') inside" do
    let(:named) { described_class.new("name", &proc { Parsanol.str("bar") }) }

    it "parses 'bar' without raising exceptions" do
      named.parse("bar")
    end

    it "raises when applied to 'foo'" do
      lambda {
        named.parse("foo")
      }.should raise_error(Parsanol::ParseFailed)
    end

    describe "#inspect" do
      it "returns the name of the entity" do
        named.inspect.should == "NAME"
      end
    end
  end

  context "when constructed with empty block" do
    let(:entity) { described_class.new("name", &proc {}) }

    it "raises NotImplementedError" do
      lambda {
        entity.parse("some_string")
      }.should raise_error(NotImplementedError)
    end
  end

  context "recursive definition parser" do
    class RecDefParser
      include Parsanol

      rule :recdef do
        str("(") >> atom >> str(")")
      end
      rule :atom do
        str("a") | str("b") | recdef
      end
    end
    let(:parser) { RecDefParser.new }

    it "parses balanced parens" do
      parser.recdef.parse("(((a)))")
    end

    it "does not throw 'stack level too deep' when printing errors" do
      cause = catch_failed_parse { parser.recdef.parse("(((a))") }
      cause.ascii_tree
    end
  end

  context "when constructed with a label" do
    let(:named) do
      described_class.new("name", "label", &proc {
        Parsanol.str("bar")
      })
    end

    it "parses 'bar' without raising exceptions" do
      named.parse("bar")
    end

    it "raises when applied to 'foo'" do
      lambda {
        named.parse("foo")
      }.should raise_error(Parsanol::ParseFailed)
    end

    describe "#inspect" do
      it "returns the label of the entity" do
        named.inspect.should == "label"
      end
    end

    describe "#parslet" do
      it "sets the label on the cached parslet" do
        named.parslet.label.should == "label"
      end
    end
  end
end
