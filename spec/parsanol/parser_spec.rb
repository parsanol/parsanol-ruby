# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Parser do
  include Parsanol

  class FooParser < Parsanol::Parser
    rule(:foo) { str("foo") }
    root(:foo)
  end

  describe "<- .root" do
    parser = Class.new(Parsanol::Parser) do
      def root_parslet
        :answer
      end
    end
    parser.root :root_parslet

    it "has defined a 'root' method, returning the root" do
      parser_instance = parser.new
      expect(parser_instance.root).to eq(:answer)
    end
  end

  it "parses 'foo'" do
    FooParser.new.parse("foo").should == "foo"
  end

  describe "#rule_cache" do
    it "honors parser-provided rule caches" do
      builds = 0
      parser_class = Class.new(Parsanol::Parser) do
        include Parsanol

        @shared_rule_cache = { letter: :parser_owned_entry }

        def self.shared_rule_cache
          @shared_rule_cache
        end

        def rule_cache
          self.class.shared_rule_cache
        end

        rule(:letter) do
          builds += 1
          str("a")
        end
        root(:letter)
      end

      expect(parser_class.new.parse("a")).to eq("a")
      expect(parser_class.new.parse("a")).to eq("a")
      expect(builds).to eq(1)
      expect(parser_class.shared_rule_cache[:letter]).to eq(:parser_owned_entry)
    end
  end

  context "composition" do
    let(:parser) { FooParser.new }

    it "allows concatenation" do
      composite = parser >> str("bar")
      composite.should parse("foobar")
    end
  end
end
