# frozen_string_literal: true

require "spec_helper"

# Zero-width repetition bodies must terminate on BOTH engines: a body
# that matches without consuming input is counted once and the loop
# stops (try_general / with_tree_cache guards). These shapes hung the
# interpreter before the guards existed.
RSpec.describe "zero-width repetition termination and lint" do
  it "stops a pure-lookahead body after one empty match (interpreter)" do
    parser = Class.new(Parsanol::Parser) do
      rule(:x) { str("a").present?.repeat(1) }
      root(:x)
    end
    result = parser.new.parse("aaa", prefix: true)
    expect(result).to include(:repetition)
  end

  it "stops a guard-chain body (interpreter)" do
    parser = Class.new(Parsanol::Parser) do
      rule(:x) { (str("a").present? >> str("b").absent?).repeat(1) }
      root(:x)
    end
    result = parser.new.parse("aaa", prefix: true)
    expect(result).to include(:repetition)
  end

  it "terminates deep paren recursion (interpreter)" do
    parser = Class.new(Parsanol::Parser) do
      rule(:ws) { match("\\s").repeat }
      rule(:expr) do
        (str("(") >> ws >> expr.maybe >> ws >> str(")")).maybe >> ws
      end
      root(:expr)
    end
    expect { parser.new.parse("()" * 100, prefix: true) }
      .not_to raise_error
  end

  # Lint behavior: all shadowed-alternative violations are reported in
  # ONE error (compile previously aborted on the first), and the walk
  # descends entity bodies so DSL and PARG-compiled grammars get the
  # same verdicts.
  it "reports every lint violation in a single error" do
    parser = Class.new(Parsanol::Parser) do
      rule(:x) do
        str("a").present? | str("b").present? | str("c")
      end
      root(:x)
    end
    expect { Parsanol::VM.validate_alternatives(parser.new.root) }
      .to raise_error(Parsanol::GrammarError) do |e|
        expect(e.message).to include("2 shadowed-alternative violation(s)")
        expect(e.message).to include("'a'")
        expect(e.message).to include("'b'")
      end
  end

  it "descends entity bodies: a DSL rule shadowing inside a nested rule fails" do
    parser = Class.new(Parsanol::Parser) do
      rule(:inner) { str("a").present? | str("c") }
      rule(:outer) { str("x") >> inner }
      root(:outer)
    end
    # validate directly: the program cache is keyed by object_id (a
    # deliberate no-strong-refs tradeoff), so a recycled id could mask
    # the violation through a stale entry in a long-running process
    expect { Parsanol::VM.validate_alternatives(parser.new.root) }
      .to raise_error(Parsanol::GrammarError, /shadowed-alternative violation/)
  end
end
