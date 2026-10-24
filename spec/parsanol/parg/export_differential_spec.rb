# frozen_string_literal: true

require "parsanol"
require "json"
require_relative "../../support/ebnf_matcher"

# ruby#321 slice 2: the acceptance-equivalence differential, internal
# half. The compiled artifact's embedded tests (accept/reject sets)
# replay through the EXPORTED grammar parsed back by the strict
# EbnfMatcher: an accept must match, a reject must not. This pins the
# lowering's language equivalence from our side; the external half
# (the actual XGrammar runtime) is the follow-up slice.
RSpec.describe "export acceptance equivalence" do
  def exported_matcher(source)
    document = Parsanol::PARG::Parser.new(source).parse
    compiled = Parsanol::PARG::Compiler.compile(document)
    ebnf = Parsanol::PARG::Export.call(JSON.generate(compiled.envelope))
    EbnfMatcher.parse(ebnf)
  end

  it "replays the demo grammar's acceptance set through the export" do
    node = exported_matcher(<<~PARG)
      grammar Demo version "1.0.0" {
        entry main: iso_identifier
        digit = %x30-39
        number = 1*digit
        publisher = %i"iso" / %i"ieee"
        iso_identifier = publisher " " number
        test main {
          accept "iso 12345"
          accept "IEEE 42"
          reject "iso"
          reject "iso x1"
        }
      }
    PARG
    expect(EbnfMatcher.matches?(node, "iso 12345")).to be(true)
    expect(EbnfMatcher.matches?(node, "IEEE 42")).to be(true)
    expect(EbnfMatcher.matches?(node, "iso")).to be(false)
    expect(EbnfMatcher.matches?(node, "iso x1")).to be(false)
  end

  it "replays an optional-and-range grammar" do
    node = exported_matcher(<<~PARG)
      grammar Opt version "1.0.0" {
        entry main: line
        sign = "-" / "+"
        number = 2*4DIGIT
        line = [sign] number
        test main {
          accept "-12"
          accept "+1234"
          accept "99"
          reject "1"
          reject "-12345"
        }
      }
    PARG
    expect(EbnfMatcher.matches?(node, "-12")).to be(true)
    expect(EbnfMatcher.matches?(node, "+1234")).to be(true)
    expect(EbnfMatcher.matches?(node, "99")).to be(true)
    expect(EbnfMatcher.matches?(node, "1")).to be(false)
    expect(EbnfMatcher.matches?(node, "-12345")).to be(false)
  end

  it "replays a fold-literal grammar" do
    node = exported_matcher(<<~PARG)
      grammar Fold version "1.0.0" {
        entry main: tag
        tag = %i"on" / %i"off"
        test main {
          accept "ON"
          accept "off"
          reject "OnX"
        }
      }
    PARG
    expect(EbnfMatcher.matches?(node, "ON")).to be(true)
    expect(EbnfMatcher.matches?(node, "off")).to be(true)
    expect(EbnfMatcher.matches?(node, "OnX")).to be(false)
  end
end
