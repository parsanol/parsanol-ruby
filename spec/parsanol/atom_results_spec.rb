# frozen_string_literal: true

require "spec_helper"

describe "Result of a Parsanol#parse" do
  include Parsanol
  extend Parsanol

  describe "regression" do
    def recursive_prefix_success_parser_class(adaptive_cache_threshold:)
      Class.new(Parsanol::Parser) do
        rule(:space) { str(" ").repeat(1) }
        rule(:space?) { space.maybe }
        rule(:operator) { str("=").as(:operator) }
        rule(:operand) { str("|x|").as(:factor) | str("R").as(:rhs) }
        rule(:element) { operand | operator }
        rule(:expression) do
          (element >> space? >> expression.as(:prime) >> str("!")) |
            element |
            (element >> space? >> expression.as(:expr)) |
            (element >> space? >> expression.as(:expr) >> space? >>
              expression.as(:expression).maybe)
        end
        root :expression

        define_method(:run_with_context) do |input, reporter, consume_all|
          context = Parsanol::Atoms::Context.new(
            reporter,
            parser_class: self.class,
            adaptive_cache_threshold: adaptive_cache_threshold,
          )

          apply(input, context, consume_all)
        end
      end
    end

    def expected_recursive_prefix_success_tree
      {
        factor: "|x|",
        expr: { operator: "=" },
        expression: { rhs: "R" },
      }
    end

    [
      # Behaviour with maybe-nil
      [str("foo").maybe >> str("bar"), "bar", "bar"],
      [str("bar") >> str("foo").maybe, "bar", "bar"],

      # These might be hard to understand; look at the result of
      #   str.maybe >> str
      # and
      #   str.maybe >> str first.
      [(str("f").maybe >> str("b")).repeat, "bb", "bb"],
      [(str("b") >> str("f").maybe).repeat, "bb", "bb"],

      [str("a").as(:a) >> (str("b") >> str("c").as(:a)).repeat, "abc",
       [{ a: "a" }, { a: "c" }]],

      [str("a").as(:a).repeat >> str("b").as(:b).repeat, "ab",
       [{ a: "a" }, { b: "b" }]],

      # Repetition behaviour / named vs. unnamed
      [str("f").repeat, "", ""],
      [str("f").repeat.as(:f), "", { f: [] }],

      # Maybe behaviour / named vs. unnamed
      [str("f").maybe, "", ""],
      [str("f").maybe.as(:f), "", { f: nil }],
    ].each do |parslet, input, result|
      context parslet.inspect do
        it "parses \"#{input}\" into \"#{result}\"" do
          expect(strip_positions(parslet.parse(input))).to eq(result)
        end
      end
    end

    it "shares built-in prefix successes for Parslet-compatible recursion" do
      parser_class =
        recursive_prefix_success_parser_class(adaptive_cache_threshold: 0)

      expect(strip_positions(parser_class.new.parse("|x|=R")))
        .to eq(expected_recursive_prefix_success_tree)
    end

    it "shares built-in prefix successes when adaptive caching is inactive" do
      parser_class =
        recursive_prefix_success_parser_class(adaptive_cache_threshold: 10_000)

      expect(strip_positions(parser_class.new.parse("|x|=R")))
        .to eq(expected_recursive_prefix_success_tree)
    end

    it "still enforces full consumption at the named boundary" do
      expect { str("a").as(:letter).parse("ab") }
        .to raise_error(Parsanol::ParseFailed)
    end
  end
end
