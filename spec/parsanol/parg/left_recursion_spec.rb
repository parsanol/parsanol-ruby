# frozen_string_literal: true

require "spec_helper"

# Direct left recursion (owner decision 2026-10-21, #251): rewritten at
# compile time into a chain of left-folding tier rules — the ANTLR 4 model.
# Branches in source order are precedence tiers, earlier binding tighter;
# the non-recursive alternatives are the primary. Indirect recursion keeps
# its compile error.
RSpec.describe "PARG direct left recursion" do
  def compile(source)
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(document)
  end

  let(:arith) do
    <<~PARG
      grammar LeftRecArith version "1.0.0" {
        ## `*` binds tighter than `+`; both left-associative.
        expr = expr ( "*" expr ) as mul / expr ( "+" expr ) as add / term
        term = ( 1*%x30-39 ) as num
        top = ( expr ) as expr

        entry top: top

        test top {
          shape "1+2*3" { expr: [ { num: "1" },
            { add: [ { num: "2" }, { mul: { num: "3" } } ] } ] }
          shape "1*2+3" { expr: [ { num: "1" },
            { mul: { num: "2" } }, { add: { num: "3" } } ] }
          shape "1+2+3" { expr: [ { num: "1" },
            { add: { num: "2" } }, { add: { num: "3" } } ] }
          shape "1*2*3" { expr: [ { num: "1" },
            { mul: { num: "2" } }, { mul: { num: "3" } } ] }
          reject "+1"
          reject "1+"
        }
      }
    PARG
  end

  it "compiles a directly left-recursive grammar" do
    expect { compile(arith) }.not_to raise_error
  end

  it "folds with tiered precedence and left associativity" do
    artifact = Parsanol::PARG::Artifact.from_json(JSON.generate(compile(arith).envelope))
    {
      "1+2*3" => [{ num: "1" }, { add: [{ num: "2" }, { mul: { num: "3" } }] }],
      "1*2+3" => [{ num: "1" }, { mul: { num: "2" } }, { add: { num: "3" } }],
      "1+2+3" => [{ num: "1" }, { add: { num: "2" } }, { add: { num: "3" } }],
      "1*2*3" => [{ num: "1" }, { mul: { num: "2" } }, { mul: { num: "3" } }],
    }.each do |input, shape|
      expect(artifact.parse("top", input, mode: :ruby)).to eq(expr: shape),
                                                           "#{input}: wrong fold"
    end
  end

  it "rejects a rule with no non-recursive alternative" do
    expect do
      compile("grammar R version \"1.0.0\" {\n  r = r \"x\"\n\n  entry r: r\n}")
    end.to raise_error(Parsanol::PARG::CompileError, /no non-recursive alternative/)
  end

  it "rejects a bare self-reference" do
    expect do
      compile("grammar R version \"1.0.0\" {\n  r = r / \"x\"\n\n  entry r: r\n}")
    end.to raise_error(Parsanol::PARG::CompileError, /consists only of the recursive reference/)
  end

  it "rejects a nullable fold" do
    expect do
      compile("grammar R version \"1.0.0\" {\n  r = r [ \"x\" ] / \"y\"\n\n  entry r: r\n}")
    end.to raise_error(Parsanol::PARG::CompileError, /can match empty after the leading reference/)
  end

  it "rejects captures around the leading reference" do
    expect do
      compile("grammar R version \"1.0.0\" {\n  r = ( r \"*\" r ) as mul / \"x\"\n\n  entry r: r\n}")
    end.to raise_error(Parsanol::PARG::CompileError, /must begin with a bare reference/)
  end

  it "still rejects indirect left recursion" do
    expect do
      compile("grammar R version \"1.0.0\" {\n  a = b \"x\" / \"y\"\n  b = a / \"z\"\n\n  entry a: a\n}")
    end.to raise_error(Parsanol::PARG::CompileError, /left recursion detected/)
  end

  it "reserves the expansion prefix" do
    expect do
      compile("grammar R version \"1.0.0\" {\n  __left_r_1 = \"x\"\n\n  entry r: __left_r_1\n}")
    end.to raise_error(Parsanol::PARG::CompileError, /reserved/)
  end
end
