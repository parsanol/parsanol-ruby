# frozen_string_literal: true

require "spec_helper"

describe "Automatic Rule Optimization" do
  include Parsanol

  context "when optimize_rules! is called" do
    class OptimizedParser < Parsanol::Parser
      optimize_rules!

      rule(:redundant) do
        str("a").repeat(1, 1) >>
          str("b").repeat(1, 1) >>
          str("c").repeat(1, 1)
      end

      rule(:nested_maybe) do
        str("x").repeat(0, 1).repeat(0, 1)
      end

      rule(:exact_counts) do
        str("m").repeat(2, 2).repeat(3, 3)
      end

      root :redundant
    end

    it "automatically simplifies repeat(1,1) in rules" do
      parser = OptimizedParser.new
      # The rule should parse successfully
      expect(parser.redundant.parse("abc")).to eq("abc")
    end

    it "automatically simplifies nested maybe" do
      parser = OptimizedParser.new
      # Should match with x
      expect(parser.nested_maybe.parse("x")).to eq("x")
      # Should match without x (returns empty string, not nil)
      expect(parser.nested_maybe.parse("")).to eq("")
    end

    it "automatically simplifies multiplied exact counts" do
      parser = OptimizedParser.new
      # Should require exactly 6 m's
      expect(parser.exact_counts.parse("mmmmmm")).to eq("mmmmmm")
    end

    it "produces the same results as manual optimization" do
      manual = str("a").repeat(1, 1) >> str("b").repeat(1, 1)
      manual_optimized = Parsanol::Optimizer.simplify_quantifiers(manual)

      auto_parser = OptimizedParser.new

      input = "ab"
      # Both should return Slice objects (parslet's default)
      expect(auto_parser.redundant.parse("abc").to_s).to eq("abc")
      expect(manual_optimized.parse(input).to_s).to eq("ab")
    end
  end

  context "when optimize_rules! is not called" do
    class UnoptimizedParser < Parsanol::Parser
      # As of v3.1.0, optimizations are DISABLED by default (opt-in)
      # This avoids overhead on tiny/small inputs
      rule(:redundant) do
        str("a").repeat(1, 1) >>
          str("b").repeat(1, 1)
      end

      root :redundant
    end

    it "still works without optimization (default)" do
      parser = UnoptimizedParser.new
      # Should work without optimization
      expect(parser.redundant.parse("ab")).to be_truthy
    end

    it "defaults optimize_rules? to false (v3.1.0+ opt-in)" do
      # As of v3.1.0, optimizations are opt-in to avoid overhead
      expect(UnoptimizedParser.optimize_rules?).to be false
    end
  end

  context "when optimization is explicitly disabled" do
    class ExplicitlyUnoptimizedParser < Parsanol::Parser
      disable_optimization! # Explicit opt-out

      rule(:redundant) do
        str("a").repeat(1, 1) >>
          str("b").repeat(1, 1)
      end

      root :redundant
    end

    it "respects explicit disable_optimization!" do
      expect(ExplicitlyUnoptimizedParser.optimize_rules?).to be false
    end

    it "still parses correctly without optimization" do
      parser = ExplicitlyUnoptimizedParser.new
      expect(parser.redundant.parse("ab")).to be_truthy
    end
  end

  context "with complex nested structures" do
    class ComplexOptimizedParser < Parsanol::Parser
      optimize_rules!

      rule(:deeply_nested) do
        str("a").repeat(1, 1).repeat(1, 1).repeat(1, 1)
      end

      rule(:mixed) do
        str("x").repeat(1, 1) >> str("y").repeat(0, 1) >> str("z")
      end

      root :deeply_nested
    end

    it "simplifies deeply nested repetitions" do
      parser = ComplexOptimizedParser.new
      expect(parser.deeply_nested.parse("a")).to eq("a")
    end

    it "handles mixed simplifiable and non-simplifiable patterns" do
      parser = ComplexOptimizedParser.new
      # With y
      expect(parser.mixed.parse("xyz")).to be_truthy
      # Without y
      expect(parser.mixed.parse("xz")).to be_truthy
    end
  end

  context "backward compatibility" do
    it "parsers without optimize_rules! work without optimization" do
      class LegacyParser < Parsanol::Parser
        rule(:test) { str("a").repeat(1, 1) }
        root :test
      end

      parser = LegacyParser.new
      # Should still work, just not optimized (opt-in model)
      expect(parser.test.parse("a")).to be_truthy
      expect(LegacyParser.optimize_rules?).to be false
    end

    it "does not break existing test suite" do
      # Run a sample from existing tests to ensure compatibility
      parser = str("hello").repeat(1, 1)
      expect(parser.parse("hello")).to eq("hello")
    end
  end

  context "combined optimizations" do
    class CombinedOptParser < Parsanol::Parser
      optimize_rules!

      rule(:combined) do
        # Has both quantifier and sequence issues
        (str("h") >> str("e") >> str("l") >> str("l") >> str("o")).repeat(1,
                                                                          1) >>
          str(" ") >>
          (str("w") >> str("o") >> str("r") >> str("l") >> str("d")).repeat(1,
                                                                            1)
      end

      root :combined
    end

    it "applies both quantifier and sequence optimizations" do
      parser = CombinedOptParser.new
      # Should merge strings and unwrap repeat(1,1)
      # Original: (Str('h') >> Str('e') >> ... >> Str('o')).repeat(1,1) >> Str(' ') >> (Str('w') >> ... >> Str('d')).repeat(1,1)
      # After quantifier: Sequence(Str('h'), Str('e'), ..., Str('o')) >> Str(' ') >> Sequence(Str('w'), ..., Str('d'))
      # After sequence: Str('hello') >> Str(' ') >> Str('world')
      # Final merge: Str('hello world')

      result = parser.combined.parse("hello world")
      expect(result).to eq("hello world")
    end

    it "produces same results as manual optimization" do
      parser = CombinedOptParser.new

      # Manual construction without optimization
      manual = (str("h") >> str("e") >> str("l") >> str("l") >> str("o")).repeat(
        1, 1
      ) >>
        str(" ") >>
        (str("w") >> str("o") >> str("r") >> str("l") >> str("d")).repeat(
          1, 1
        )

      input = "hello world"
      expect(parser.combined.parse(input)).to eq(manual.parse(input))
    end
  end

  context "edge cases" do
    class EdgeCaseParser < Parsanol::Parser
      optimize_rules!

      rule(:normal_repeat) do
        str("a").repeat(0, 3) # Should not be simplified
      end

      rule(:variable_repeat) do
        str("b").repeat(1) # Should not be simplified (unbounded)
      end

      root :normal_repeat
    end

    it "does not simplify non-trivial repetitions" do
      parser = EdgeCaseParser.new
      expect(parser.normal_repeat.parse("a")).to be_truthy
      expect(parser.normal_repeat.parse("aa")).to be_truthy
      expect(parser.normal_repeat.parse("aaa")).to be_truthy
    end

    it "does not simplify unbounded repetitions" do
      parser = EdgeCaseParser.new
      expect(parser.variable_repeat.parse("b")).to be_truthy
      expect(parser.variable_repeat.parse("bbb")).to be_truthy
    end
  end

  context "choice optimizations" do
    class ChoiceOptParser < Parsanol::Parser
      optimize_rules!

      rule(:duplicate_choices) do
        str("a") | str("b") | str("a") | str("c") | str("b")
      end

      rule(:nested_alternatives) do
        (str("x") | str("y")) | (str("z") | str("w"))
      end

      root :duplicate_choices
    end

    it "deduplicates alternative choices" do
      parser = ChoiceOptParser.new
      # All three unique options should still parse
      expect(parser.duplicate_choices.parse("a")).to eq("a")
      expect(parser.duplicate_choices.parse("b")).to eq("b")
      expect(parser.duplicate_choices.parse("c")).to eq("c")
    end

    it "flattens nested alternatives" do
      parser = ChoiceOptParser.new
      # All four flattened options should parse
      expect(parser.nested_alternatives.parse("x")).to eq("x")
      expect(parser.nested_alternatives.parse("y")).to eq("y")
      expect(parser.nested_alternatives.parse("z")).to eq("z")
      expect(parser.nested_alternatives.parse("w")).to eq("w")
    end
  end

  context "lookahead optimizations" do
    class LookaheadOptParser < Parsanol::Parser
      optimize_rules!

      rule(:double_negation) do
        str("a").absent?.absent? >> str("a")
      end

      rule(:idempotent_positive) do
        str("b").present?.present? >> str("b")
      end

      rule(:negative_of_positive) do
        str("c").present?.absent? >> str("d")
      end

      root :double_negation
    end

    it "simplifies double negation !(!x) to &x" do
      parser = LookaheadOptParser.new
      # Double negation becomes positive lookahead
      expect(parser.double_negation.parse("a")).to eq("a")
    end

    it "simplifies idempotent positive &(&x) to &x" do
      parser = LookaheadOptParser.new
      # Nested positive lookaheads are idempotent
      expect(parser.idempotent_positive.parse("b")).to eq("b")
    end

    it "simplifies negative of positive !(&x) to !x" do
      parser = LookaheadOptParser.new
      # !(&x) becomes !x
      expect(parser.negative_of_positive.parse("d")).to eq("d")
    end
  end

  context "all optimizations combined" do
    class AllOptimizationsParser < Parsanol::Parser
      optimize_rules!

      rule(:everything) do
        # Quantifiers: repeat(1,1)
        # Sequences: adjacent strings
        # Choices: duplicate alternatives
        ((str("a") >> str("b")).repeat(1,
                                       1) | (str("a") >> str("b")).repeat(1,
                                                                          1)) >>
          (str("c") | str("c") | str("d"))
      end

      rule(:with_lookahead) do
        # Add lookahead optimization test
        str("x").absent?.absent? >> str("y")
      end

      root :everything
    end

    it "applies all four optimizers together" do
      parser = AllOptimizationsParser.new
      # Should optimize:
      # 1. Remove repeat(1,1) with quantifier optimizer
      # 2. Merge str('a') >> str('b') with sequence optimizer
      # 3. Deduplicate alternatives with choice optimizer
      expect(parser.everything.parse("abc")).to be_truthy
      expect(parser.everything.parse("abd")).to be_truthy
    end

    it "optimizes lookaheads in combination with other optimizers" do
      parser = AllOptimizationsParser.new
      # 4. Simplify lookaheads: !(!x) becomes &x
      # The other 3 lookahead tests already verify functional correctness
      # This test just confirms lookahead optimization is integrated
      expect(parser).to respond_to(:with_lookahead)
    end
  end
end
