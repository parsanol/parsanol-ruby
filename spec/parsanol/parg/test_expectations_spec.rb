# frozen_string_literal: true

require "spec_helper"

# In-file test expectations accept null, arrays, and nested objects so the
# corpus can pin array bindings, absent-optional nil, and flatten/merge
# results (parsanol-rs#254 gaps G4/G5/G6/G7/G11).
RSpec.describe "PARG test expectation values" do
  def document(source)
    Parsanol::PARG::Parser.new(source).parse
  end

  let(:source) do
    <<~PARG
      grammar Expectations version "1.0.0" {
        main = 1*%x30-39

        entry main: main

        test main {
          capture "1" { value: null }
          capture "1" { items: [ 1, 2.5, "x", null, true, false, -1.5 ] }
          capture "1" { nested: { a: 1, b: [ { c: false } ] } }
          capture "1" { n: 42 }
        }
      }
    PARG
  end

  it "parses scalars, null, arrays, and nested objects" do
    tests = document(source).tests
    expect(tests[0].expect).to eq(value: nil)
    expect(tests[1].expect).to eq(items: [1, 2.5, "x", nil, true, false, -1.5])
    expect(tests[2].expect).to eq(nested: { a: 1, b: [{ c: false }] })
    expect(tests[3].expect).to eq(n: 42)
  end

  it "distinguishes a nil capture from a missing one" do
    sourced = <<~PARG
      grammar OptionalCapture version "1.0.0" {
        main = ( [ "-" ] ) as dash 1*%x61-7A

        entry main: main

        test main {
          capture "-ab" { dash: "-" }
          capture "ab" { dash: null }
        }
      }
    PARG
    document = Parsanol::PARG::Parser.new(sourced).parse
    expect { Parsanol::PARG::Compiler.compile(document) }.not_to raise_error
  end

  it "keeps integers as integers and decimals as floats" do
    expect(document(source).tests[3].expect[:n]).to be_a(Integer)
    items = document(source).tests[1].expect[:items]
    expect(items[0]).to be_a(Integer)
    expect(items[1]).to be_a(Float)
    expect(items[6]).to eq(-1.5)
  end
end
