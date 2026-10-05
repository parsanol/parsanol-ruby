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
  # same verdicts. Bare zero-width lookahead branches are exempt —
  # they are guards, not content matchers (#137).
  it "reports every lint violation in a single error" do
    parser = Class.new(Parsanol::Parser) do
      rule(:x) do
        str("a").maybe | str("b").maybe | str("c")
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

  it "exempts bare zero-width guard branches (#137)" do
    parser = Class.new(Parsanol::Parser) do
      rule(:x) do
        str("a").present? | str("b").present? | str("c")
      end
      root(:x)
    end
    expect { Parsanol::VM.validate_alternatives(parser.new.root) }
      .not_to raise_error
  end

  it "accepts the coradoc continuation shape: guards plus content" do
    parser = Class.new(Parsanol::Parser) do
      rule(:x) do
        str("STOP").present? | dynamic { |_s, _c| str("z") }.absent? |
          match(/[a-z]/).repeat(1).as(:word)
      end
      root(:x)
    end
    expect { Parsanol::VM.validate_alternatives(parser.new.root) }
      .not_to raise_error
  end

  it "parses guard-first alternatives on the VM path" do
    parser = Class.new(Parsanol::Parser) do
      rule(:x) do
        str("STOP").present? | match(/[a-z]/).repeat(1).as(:word)
      end
      root(:x)
    end
    result = parser.new
    expect(result.parse("fine", mode: :ruby)[:word].to_s).to eq("fine")
    # guard succeeds empty where STOP matches: a prefix parse accepts
    # the zero-width match and captures nothing
    expect(result.parse("STOP", mode: :ruby, prefix: true)).to be_nil
  end

  it "descends entity bodies: a DSL rule shadowing inside a nested rule fails" do
    parser = Class.new(Parsanol::Parser) do
      rule(:inner) { str("a").maybe | str("c") }
      rule(:outer) { str("x") >> inner }
      root(:outer)
    end
    expect { Parsanol::VM.validate_alternatives(parser.new.root) }
      .to raise_error(Parsanol::GrammarError, /shadowed-alternative violation/)
  end
end
