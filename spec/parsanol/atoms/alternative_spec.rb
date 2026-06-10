# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Atoms::Alternative do
  include Parsanol

  let(:inspect_raising_str_class) do
    Class.new(Parsanol::Atoms::Str) do
      def inspect
        raise "unexpected inspect"
      end
    end
  end

  let(:custom_str_class) do
    Class.new(Parsanol::Atoms::Str) do
      def try(source, context, _consume_all)
        pos = source.bytepos
        slice = source.consume(3)
        return ok(slice) if slice.content == "hit"

        source.bytepos = pos
        context.err(self, source, "custom miss")
      end
    end
  end

  def counting_str(text)
    atom = str(text)
    attempts = 0
    original_try = atom.method(:try)

    atom.define_singleton_method(:attempts) { attempts }
    atom.define_singleton_method(:try) do |source, context, consume_all|
      attempts += 1
      original_try.call(source, context, consume_all)
    end

    atom
  end

  describe "| shortcut" do
    let(:alternative) { str("a") | str("b") }

    context "when chained with different atoms" do
      before do
        # Chain something else to the alternative parslet. If it modifies the
        # parslet atom in place, we'll notice:

        alternative | str("d")
      end

      let!(:chained) { alternative | str("c") }

      it "is side-effect free" do
        chained.should parse("c")
        chained.should parse("a")
        chained.should_not parse("d")
      end
    end
  end

  describe "internal literal indexing" do
    def item_literals
      Array.new(32) { |idx| format("item%02d", idx) }
    end

    def choice_from(atoms)
      atoms.reduce { |choice, atom| choice | atom }
    end

    def large_literal_choice
      choice_from(item_literals.map { |literal| str(literal) })
    end

    def case_insensitive_word(word)
      word.chars
        .map { |char| match("[#{char.upcase}#{char.downcase}]") }
        .reduce(:>>)
    end

    def indexed_candidates(parser, input)
      source = Parsanol::Source.new(input)
      parser.send(:indexed_options, source)
    end

    it "does not inspect every branch while building large choices" do
      atoms = Array.new(32) do |idx|
        inspect_raising_str_class.new(format("item%02d", idx))
      end

      expect { choice_from(atoms) }.not_to raise_error
    end

    it "does not let custom inspect crash failure reporting" do
      parser = inspect_raising_str_class.new("aa") | str("bb")

      expect { parser.parse("cc") }
        .to raise_error(Parsanol::ParseFailed) { |error|
          expect(error.message).to include("Expected one of")
          expect(error.message).not_to include("unexpected inspect")
        }
    end

    it "skips literal branches that cannot match the current input" do
      parser = large_literal_choice

      expect(indexed_candidates(parser, "item31")).to eq([31])
      expect(parser.parse("item31")).to eq("item31")
    end

    it "fails impossible literal choices without scanning every branch" do
      parser = large_literal_choice

      expect { parser.parse("unknown") }.to raise_error(Parsanol::ParseFailed)

      expect(indexed_candidates(parser, "unknown")).to eq([])
    end

    it "does not index small choices" do
      parser = choice_from(%w[aa bb cc dd].map { |literal| str(literal) })

      expect(indexed_candidates(parser, "cc")).to be_nil
    end

    it "builds an index once the branch threshold is reached" do
      parser = choice_from(Array.new(16) { |idx| str(format("item%02d", idx)) })

      expect(indexed_candidates(parser, "item02")).to eq([2])
    end

    it "does not materialize the full remaining input while selecting indexed branches" do
      parser = large_literal_choice
      source = Parsanol::Source.new("item21#{'x' * 10_000}")

      def source.remaining
        raise "unexpected full remaining input read"
      end

      expect(parser.send(:indexed_options, source)).to eq([21])
      expect(source.pos).to eq(0)
    end

    it "does not raise from an unselected lazy entity while building the index" do
      missing = Parsanol::Atoms::Entity.new(:missing) { nil }
      parser = choice_from(item_literals.first(15).map { |literal| str(literal) } + [missing])

      expect(parser.parse("item00")).to eq("item00")
    end

    it "keeps custom string atom subclasses as candidates" do
      parser = choice_from(
        item_literals.first(15).map { |literal| str(literal) } + [custom_str_class.new("never")],
      )

      expect(parser.parse("hit")).to eq("hit")
    end

    it "preserves ordered-choice behavior for prefix collisions" do
      parser = choice_from(
        [str("item2").as(:short), str("item21").as(:long)] +
          item_literals.first(15).map { |literal| str(literal).as(:other) },
      )

      expect(indexed_candidates(parser, "item21")).to include(0, 1)
      expect(parser.parse("item21", prefix: true)).to eq({ short: "item2" })
    end

    it "preserves named captures" do
      parser = choice_from(
        item_literals.map { |literal| str(literal).as(:item) },
      )

      expect(parser.parse("item12")).to eq({ item: "item12" })
    end

    it "keeps unsafe branches as candidates" do
      parser = choice_from(
        [match["z"]] + item_literals.map { |literal| str(literal) },
      )

      expect(parser.parse("z")).to eq("z")
    end

    it "keeps broad regex branches unsafe" do
      patterns = %w[[A-Z] [0-9] [_] [a-z]]
      parser = choice_from(
        Array.new(16) { |idx| match(patterns[idx % patterns.size]) },
      )

      expect(indexed_candidates(parser, "A")).to be_nil
    end

    it "keeps fixed case-insensitive regex prefixes unsafe" do
      words = %w[ABS ACOS SIN SIZEOF TAN COS SEC CSC COT LOG EXP MIN MAX GCD LCM DIM]
      parser = choice_from(
        words.map do |word|
          case_insensitive_word(word).as(word.downcase.to_sym)
        end,
      )

      expect(indexed_candidates(parser, "aCoS")).to be_nil
      expect(indexed_candidates(parser, "sIN")).to be_nil
      expect(parser.parse("aCoS")).to eq({ acos: "aCoS" })
      expect(parser.parse("sIN")).to eq({ sin: "sIN" })
    end

    it "keeps nullable-leading regex prefixes unsafe" do
      words = %w[ABS ACOS SIN SIZEOF TAN COS SEC CSC COT LOG EXP MIN MAX GCD LCM DIM]
      parser = choice_from(
        words.map do |word|
          match[" "].repeat >> case_insensitive_word(word).as(word.downcase.to_sym)
        end,
      )

      expect(indexed_candidates(parser, "aCoS")).to be_nil
      expect(indexed_candidates(parser, "  aCoS")).to be_nil
      expect(parser.parse("  aCoS")).to eq({ acos: "aCoS" })
    end

    it "keeps nullable-leading literal prefixes unsafe" do
      operators = %w[* / + - = < > & | ^ % @ ! ? : ,]
      parser = choice_from(
        operators.map { |operator| match[" "].repeat >> str(operator).as(:operator) },
      )

      expect(indexed_candidates(parser, "+")).to be_nil
      expect(indexed_candidates(parser, " +")).to be_nil
      expect(parser.parse(" +")).to eq({ operator: "+" })
    end

    it "handles multibyte literal prefixes" do
      parser = choice_from(Array.new(32) { |idx| str("変#{idx}") })

      expect(parser.parse("変20")).to eq("変20")
    end

    it "fails normally when an ASCII prefix preview cuts multibyte input" do
      parser = choice_from(Array.new(16) { |idx| str((?a.ord + idx).chr) })

      expect { parser.parse("変", prefix: true) }
        .to raise_error(Parsanol::ParseFailed)
    end

    it "keeps empty literals as candidates" do
      parser = choice_from(
        [str("")] + item_literals.map { |literal| str(literal) },
      )

      expect(parser.parse("item03", prefix: true)).to eq("")
    end

    it "indexes alternatives that start with a literal sequence component" do
      parser = choice_from(
        item_literals.map { |literal| str(literal) >> match["!"] },
      )

      expect(parser.parse("item21!")).to eq("item21!")
    end

    it "keeps detailed child errors for indexed sequence-led failures" do
      parser = choice_from(
        item_literals.first(16).map { |literal| str(literal) >> str("!") },
      )
      cause = catch_failed_parse { parser.parse("item00?") }

      expect(cause.ascii_tree).to include('Expected "!", but got "?"')
    end

    it "keeps detailed child errors for indexed sequence-led partial-prefix failures" do
      parser = choice_from(
        item_literals.first(16).map { |literal| str(literal) >> str("!") },
      )
      cause = catch_failed_parse { parser.parse("item0X") }

      expect(cause.ascii_tree).to include('Expected "item00", but got "item0X"')
    end

    it "keeps detailed child errors for indexed literal partial-prefix failures" do
      parser = choice_from(
        item_literals.first(16).map { |literal| str(literal) },
      )
      cause = catch_failed_parse { parser.parse("item0X") }

      expect(cause.ascii_tree).to include('Expected "item00", but got "item0X"')
    end

    it "tries same-prefix sequence branches in original order" do
      parser = choice_from(
        item_literals.flat_map do |literal|
          [
            str(literal).as(:name) >> str("_").as(:suffix),
            str(literal).as(:name),
          ]
        end,
      )

      expect(parser.parse("item21")).to eq({ name: "item21" })
      expect(parser.parse("item21_")).to eq({ name: "item21", suffix: "_" })
    end

    it "indexes literal prefixes through rule entities and sequences" do
      slash = Parsanol::Atoms::Entity.new(:slash) { str("\\") }
      atoms = item_literals.map { |literal| counting_str(literal) }
      parser = choice_from(
        atoms.map { |atom| slash >> atom.as(:symbol) },
      )

      expect(parser.parse("\\item21")).to eq({ symbol: "item21" })
      # The successful first pass selects exactly the one matching branch; a
      # regression to sequential scanning would try branches 0..21 instead.
      expect(atoms.sum(&:attempts)).to eq(1)
      expect(atoms[21].attempts).to eq(1)
    end

    it "keeps partially literal nested sequences as viable candidates" do
      branch = lambda do
        (str("aa") >> match("[0-9]")).as(:num) >> str("b").as(:tail)
      end
      fillers = item_literals.first(15).map { |literal| str(literal) }

      indexed = choice_from([branch.call] + fillers)
      control = choice_from([branch.call] + fillers.first(13))

      expect(indexed.parse("aa5b")).to eq(control.parse("aa5b"))
    end

    it "keeps ordered choice when a nested branch is only partially literal" do
      nested = (str("aa") >> match("[0-9]")).as(:num) >> str("b").as(:tail)
      catch_all = match("[a-z0-9]").repeat(1).as(:word)
      parser = choice_from(
        [nested] + item_literals.first(15).map { |literal| str(literal) } +
          [catch_all],
      )

      expect(parser.parse("aa5b")).to eq({ num: "aa5", tail: "b" })
    end

    it "keeps entity-wrapped partially literal sequences as viable candidates" do
      partial = Parsanol::Atoms::Entity.new(:partial) do
        str("aa") >> match("[0-9]")
      end
      branch = partial.as(:num) >> str("b").as(:tail)
      parser = choice_from(
        [branch] + item_literals.first(15).map { |literal| str(literal) },
      )

      expect(parser.parse("aa5b")).to eq({ num: "aa5", tail: "b" })
    end

    it "reports causes for every branch when an indexed choice fails" do
      parser = choice_from(
        item_literals.first(16).map { |literal| str(literal) } + [str("zzz")],
      )
      cause = catch_failed_parse { parser.parse("qqq") }

      expect(cause.children.size).to eq(17)
    end

    it "freezes the alternatives array so the literal index cannot go stale" do
      parser = large_literal_choice

      expect(parser.alternatives).to be_frozen
      expect { parser.alternatives << str("zzz") }.to raise_error(FrozenError)
    end

    it "does not recurse forever while inspecting recursive entities" do
      recursive = nil
      recursive = Parsanol::Atoms::Entity.new(:recursive) do
        recursive >> str("x")
      end

      parser = choice_from(
        item_literals.map { |literal| str(literal) } + [recursive],
      )

      expect(parser.parse("item05")).to eq("item05")
    end

    it "does not clear ancestor recursion markers for seen entities" do
      recursive = Parsanol::Atoms::Entity.new(:recursive) { str("x") }
      marker = recursive.object_id
      seen = { marker => true }

      expect(large_literal_choice.send(:static_literal_prefixes, recursive, seen))
        .to eq([nil, false])
      expect(seen.fetch(marker)).to be(true)
    end
  end
end
