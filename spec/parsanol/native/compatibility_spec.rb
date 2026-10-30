# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Native compatibility" do
  def choice_parser
    Class.new(Parsanol::Parser) do
      rule(:padding) { str("x").repeat.as(:padding) }
      rule(:piece) { str("a").as(:short) | str("ab").as(:whole) }
      rule(:body) do
        (piece >> str("!")) | piece | (str("a").as(:first) >> str("b").as(:second))
      end
      rule(:document) { padding >> body }
      root(:document)
    end.new
  end

  def plain(value)
    case value
    when Hash then value.transform_values { |child| plain(child) }
    when Array then value.map { |child| plain(child) }
    when Parsanol::Slice then value.to_s
    else value
    end
  end

  describe "compatibility dispatch" do
    it "rejects an unknown policy before selecting an engine" do
      expect(Parsanol::Native).not_to receive(:available?)

      expect { Parsanol::Native.parse(Parsanol.str("a"), "a", compatibility: :unknown) }
        .to raise_error(ArgumentError, /Unknown compatibility/)
    end

    it "rejects a missing native seam instead of accepting through Ruby" do
      allow(Parsanol::Native).to receive(:available?).and_return(true)
      allow(Parsanol::Native::Parser).to receive(:extension_loaded?).and_return(true)
      allow(Parsanol::Native).to receive(:respond_to?).and_call_original
      allow(Parsanol::Native).to receive(:respond_to?).with(:_parse_handle_with_compatibility).and_return(false)
      expect(Parsanol::Native).not_to receive(:raise_native_parse_error)

      expect { choice_parser.parse("ab", mode: :native, compatibility: :parslet) }
        .to raise_error(NotImplementedError, /requires an extension/)
    end

    it "does not silently select Ruby when auto mode finds an older native extension" do
      allow(Parsanol::Native).to receive(:available?).and_return(true)
      allow(Parsanol::Native::Parser).to receive(:extension_loaded?).and_return(true)
      allow(Parsanol::Native).to receive(:respond_to?).and_call_original
      allow(Parsanol::Native).to receive(:respond_to?).with(:_parse_handle_with_compatibility).and_return(false)

      expect { choice_parser.parse("ab", compatibility: :parslet) }
        .to raise_error(NotImplementedError, /requires an extension/)
    end

    it "selects Ruby in auto mode when no native engine is available" do
      allow(Parsanol::Native).to receive(:available?).and_return(false)

      expect(plain(choice_parser.parse("xxxxxxxxab", compatibility: :parslet)))
        .to eq(padding: "xxxxxxxx", first: "a", second: "b")
    end

    it "does not fall back when native mode was explicit and the engine is unavailable" do
      allow(Parsanol::Native).to receive(:available?).and_return(false)

      expect { choice_parser.parse("ab", mode: :native, compatibility: :parslet) }
        .to raise_error(LoadError, /Native parser not available/)
    end

    it "rejects native compatibility prefix mode without changing consumption semantics" do
      expect { choice_parser.parse("ab!", mode: :native, prefix: true, compatibility: :parslet) }
        .to raise_error(NotImplementedError, /does not yet support prefix/)
    end

    it "translates native failure positions without a Ruby acceptance pass" do
      error = RuntimeError.new("native refusal\n@@parsanol_pos:1")
      expect(Parsanol::Native).not_to receive(:raise_native_parse_error)

      expect { Parsanol::Native.raise_compatible_parse_error(error, "ax") }
        .to raise_error(Parsanol::ParseFailed) { |failure|
          expect(failure.parse_failure_cause.position).to eq(1)
          expect(failure.message).not_to include("@@parsanol_pos")
          expect(failure.cause).to be_nil
        }
    end
  end

  # Enabled by default and in GHA. Local checks against an old binary may
  # explicitly exclude this tag; stubs are never native functionality proof.
  describe "the actual native compatibility seam", :native_compatibility do
    [8, 8_300].each do |length|
      it "preserves complete capture values and strict defaults with #{length} padding bytes" do
        parser = choice_parser
        padding = "x" * length
        input = "#{padding}ab"

        expect(plain(parser.parse(input, mode: :native)))
          .to eq(padding: padding, whole: "ab")
        expect(plain(parser.parse(input, mode: :native, compatibility: :parslet)))
          .to eq(padding: padding, first: "a", second: "b")
        expect(plain(parser.parse(input, mode: :native)))
          .to eq(padding: padding, whole: "ab")
      end
    end

    it "keeps native refusals authoritative without Ruby recovery" do
      parser = choice_parser
      grammar = parser.root
      expect(grammar).not_to receive(:run_with_context)
      expect(Parsanol::Native).not_to receive(:raise_native_parse_error)

      expect { Parsanol::Native.parse(grammar, "ax", compatibility: :parslet) }
        .to raise_error(Parsanol::ParseFailed)
    end

    it "preserves the reference raw failure for a shared optional atom" do
      parser = Class.new(Parsanol::Parser) do
        rule(:document) do
          optional = str("a").maybe
          optional | (optional >> str("b")).as(:branch) | str("b").as(:fallback)
        end
        root(:document)
      end.new

      expect(plain(parser.parse("b", mode: :native, compatibility: :parslet)))
        .to eq(fallback: "b")
    end

    it "preserves memo seeding by a literal-pruned branch" do
      parser = Class.new(Parsanol::Parser) do
        rule(:piece) { str("a").as(:first) }
        rule(:document) do
          choices = (piece >> str("!")) | piece |
            (piece >> str("b").as(:second)) | str("ab").as(:whole)
          12.times { |i| choices = choices | str("c#{i}") }
          choices
        end
        root(:document)
      end.new

      expect(plain(parser.parse("ab", mode: :native, compatibility: :parslet)))
        .to eq(first: "a", second: "b")
    end

    it "retains memo answers after the same optional atom misses at earlier positions" do
      parser = Class.new(Parsanol::Parser) do
        rule(:piece) { str("a").maybe }
        rule(:tail) { piece | (piece >> str("b")).as(:branch) | str("b").as(:fallback) }
        rule(:document) { piece >> str("x") >> piece >> str("y") >> tail }
        root(:document)
      end.new

      expect(plain(parser.parse("xyb", mode: :native, compatibility: :parslet)))
        .to eq(fallback: "b")
    end

    it "discards a successful negative lookahead's internal failure position" do
      parser = Class.new(Parsanol::Parser) do
        rule(:document) do
          (str("ab").as(:probe) >> str("c")).absent? >> str("a").as(:a) >> str("!")
        end
        root(:document)
      end.new
      expect(parser.root).not_to receive(:run_with_context)

      expect { parser.parse("ab?", mode: :native, compatibility: :parslet) }
        .to raise_error(Parsanol::ParseFailed) { |failure|
          expect(failure.parse_failure_cause.position).to eq(1)
        }
    end

    it "reports the actual UTF-8 byte position without a Ruby reporting pass" do
      parser = Class.new(Parsanol::Parser) do
        rule(:document) { str("α").as(:prefix) >> str("!") }
        root(:document)
      end.new
      expect(parser.root).not_to receive(:run_with_context)

      expect { parser.parse("α?", mode: :native, compatibility: :parslet) }
        .to raise_error(Parsanol::ParseFailed) { |failure|
          expect(failure.parse_failure_cause.position).to eq(2)
        }
    end

    it "retains a bounded repetition's raw success for a later prefix attempt" do
      parser = Class.new(Parsanol::Parser) do
        rule(:document) do
          piece = str("a").repeat(1, 1)
          piece | (piece >> str("b").as(:tail))
        end
        root(:document)
      end.new

      expect(plain(parser.parse("ab", mode: :native, compatibility: :parslet)))
        .to eq(tail: "b")
    end

    it "reports the expected-choice category without a Ruby reporting pass" do
      parser = Class.new(Parsanol::Parser) do
        rule(:document) { str("a").as(:a) | str("b").as(:b) }
        root(:document)
      end.new
      expect(parser.root).not_to receive(:run_with_context)

      expect { parser.parse("c", mode: :native, compatibility: :parslet) }
        .to raise_error(Parsanol::ParseFailed, /Expected one of \[/)
    end
  end
end
