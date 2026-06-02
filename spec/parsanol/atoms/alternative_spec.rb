# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Atoms::Alternative do
  include Parsanol

  let(:counting_str_class) do
    Class.new(Parsanol::Atoms::Str) do
      attr_reader :attempts

      def initialize(text)
        @attempts = 0
        super
      end

      def try(source, context, consume_all)
        @attempts += 1
        super
      end
    end
  end

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

    def indexed_candidates(parser, input)
      source = Parsanol::Source.new(input)
      context = Parsanol::Atoms::Context.new(nil)
      parser.send(:indexed_options, source, context)
    end

    it "does not inspect every branch while building large choices" do
      atoms = Array.new(32) do |idx|
        inspect_raising_str_class.new(format("item%02d", idx))
      end

      expect { choice_from(atoms) }.not_to raise_error
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
      parser = str("a").as(:short) | str("ab").as(:long)

      expect(parser.parse("ab", prefix: true)).to eq({ short: "a" })
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

    it "handles multibyte literal prefixes" do
      parser = choice_from(Array.new(32) { |idx| str("変#{idx}") })

      expect(parser.parse("変20")).to eq("変20")
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
      atoms = item_literals.map { |literal| counting_str_class.new(literal) }
      parser = choice_from(
        atoms.map { |atom| slash >> atom.as(:symbol) },
      )

      expect(parser.parse("\\item21")).to eq({ symbol: "item21" })
      expect(atoms.sum(&:attempts)).to be < atoms.size
      expect(atoms[21].attempts).to eq(1)
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
  end
end
