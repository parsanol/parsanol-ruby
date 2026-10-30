# frozen_string_literal: true

require "spec_helper"
require "parslet"

RSpec.describe Parsanol::Parser do
  def plain(value)
    case value
    when Hash then value.transform_values { |child| plain(child) }
    when Array then value.map { |child| plain(child) }
    when Parsanol::Slice, Parslet::Slice then value.to_s
    else value
    end
  end

  def shared_choice(library)
    Class.new(library::Parser) do
      rule(:piece) { str("a").as(:short) | str("ab").as(:whole) }
      rule(:document) do
        (piece >> str("!")) | piece | (str("a").as(:first) >> str("b").as(:second))
      end
      root(:document)
    end
  end

  it "opts into the reference prefix decision without changing the strict default" do
    parser = shared_choice(Parsanol).new
    reference = plain(shared_choice(Parslet).new.parse("ab"))

    expect(reference).to eq(first: "a", second: "b")
    expect(plain(parser.parse("ab", mode: :ruby))).to eq(whole: "ab")
    expect(plain(parser.parse("ab", mode: :ruby, compatibility: :parslet))).to eq(reference)
    expect(plain(parser.parse("ab", mode: :ruby))).to eq(whole: "ab")
  end

  it "does not execute the strict VM for an explicitly legacy parse" do
    expect(Parsanol::VM).not_to receive(:program_for)

    result = shared_choice(Parsanol).new.parse("ab", mode: :ruby, compatibility: :parslet)

    expect(plain(result)).to eq(first: "a", second: "b")
  end

  it "rejects legacy JSON mode instead of silently changing engines" do
    parser = shared_choice(Parsanol).new

    expect { parser.parse("ab", mode: :json, compatibility: :parslet) }
      .to raise_error(NotImplementedError, /does not yet support JSON/)
  end

  it "rejects an unknown policy" do
    expect { shared_choice(Parsanol).new.parse("ab", mode: :ruby, compatibility: :unknown) }
      .to raise_error(ArgumentError, /Unknown compatibility/)
  end

  it "rejects an unsupported legacy interval cache" do
    expect do
      Parsanol::Atoms::Context.new(nil, interval_cache: true, compatibility: :parslet)
    end.to raise_error(NotImplementedError, /does not yet support interval caching/)
  end

  it "selects legacy Tree diagnostics only for the opt-in default reporter" do
    parser = Class.new(Parsanol::Parser) do
      rule(:document) do
        (str("ab").as(:probe) >> str("c")).absent? >> str("a").as(:a) >> str("!")
      end
      root(:document)
    end.new
    positions = lambda do |options|
      parser.parse("ab?", mode: :ruby, **options)
      raise "expected rejection"
    rescue Parsanol::ParseFailed => e
      collect = lambda do |cause|
        cause.children.empty? ? [cause.position] : cause.children.flat_map { |child| collect.call(child) }
      end
      collect.call(e.parse_failure_cause).max
    end

    expect(positions.call({})).to eq(2)
    expect(positions.call(compatibility: :parslet)).to eq(1)
    expect(positions.call(compatibility: :parslet, reporter: Parsanol::ErrorReporter::Deepest.new)).to eq(2)
  end

  it "keeps dynamic and capture-dependent results uncached in legacy mode" do
    parser = Class.new(Parsanol::Parser) do
      rule(:dyn_tail) { dynamic { |_source, context| str(context.captures[:c].to_s) } }
      rule(:first) { str("x").capture(:c) >> str("y") >> dyn_tail >> str("1") }
      rule(:second) { str("xy").capture(:c) >> dyn_tail >> str("2") }
      rule(:document) { first | second }
      root(:document)
    end.new

    expect(parser.parse("xyxy2", mode: :ruby, compatibility: :parslet).to_s).to eq("xyxy2")
  end

  it "retains legacy prefix decisions when later branches pass the eviction window" do
    build = lambda do |library|
      Class.new(library::Parser) do
        rule(:piece) { str("a").as(:short) | str("a#{'b' * 301}").as(:whole) }
        rule(:tail) { (str("b").as(:b) >> str("")).repeat(301) }
        rule(:document) do
          (piece >> tail >> str("!")) | piece |
            (str("a").as(:first) >> str("b" * 301).as(:second))
        end
        root(:document)
      end
    end
    input = "a#{'b' * 301}"
    reference = plain(build.call(Parslet).new.parse(input))
    actual = plain(build.call(Parsanol).new.parse(input, mode: :ruby, compatibility: :parslet))

    expect(actual).to eq(reference)
    expect(actual.keys).to eq(%i[first second])
  end

  it "preserves a failed strict optional attempt when later reused as a prefix" do
    build = lambda do |library|
      Class.new(library::Parser) do
        rule(:document) do
          piece = str("a").maybe
          piece | (piece >> str("b")).as(:branch) | str("b").as(:fallback)
        end
        root(:document)
      end
    end
    reference = plain(build.call(Parslet).new.parse("b"))
    actual = plain(build.call(Parsanol).new.parse("b", mode: :ruby, compatibility: :parslet))

    expect(reference).to eq(fallback: "b")
    expect(actual).to eq(reference)
  end

  it "preserves memo seeding by branches that a literal index could prune" do
    build = lambda do |library|
      Class.new(library::Parser) do
        rule(:piece) { str("a").as(:first) }
        rule(:document) do
          branches = (piece >> str("!")) | piece |
            (piece >> str("b").as(:second)) | str("ab").as(:whole)
          12.times { |i| branches = branches | str("c#{i}") }
          branches
        end
        root(:document)
      end
    end
    reference = plain(build.call(Parslet).new.parse("ab"))
    actual = plain(build.call(Parsanol).new.parse("ab", mode: :ruby, compatibility: :parslet))

    expect(reference).to eq(first: "a", second: "b")
    expect(actual).to eq(reference)
  end

  it "retains a legacy memo answer after the same atom misses at earlier positions" do
    build = lambda do |library|
      Class.new(library::Parser) do
        rule(:piece) { str("a").maybe }
        rule(:tail) { piece | (piece >> str("b")).as(:branch) | str("b").as(:fallback) }
        rule(:document) { piece >> str("x") >> piece >> str("y") >> tail }
        root(:document)
      end
    end
    reference = plain(build.call(Parslet).new.parse("xyb"))
    actual = plain(build.call(Parsanol).new.parse("xyb", mode: :ruby, compatibility: :parslet))

    expect(reference).to eq(fallback: "b")
    expect(actual).to eq(reference)
  end

  it "retains a bounded repetition's raw success before its outer consume-all refusal" do
    build = lambda do |library|
      Class.new(library::Parser) do
        rule(:document) do
          piece = str("a").repeat(1, 1)
          piece | (piece >> str("b").as(:tail))
        end
        root(:document)
      end
    end
    reference = plain(build.call(Parslet).new.parse("ab"))
    actual = plain(build.call(Parsanol).new.parse("ab", mode: :ruby, compatibility: :parslet))

    expect(reference).to eq(tail: "b")
    expect(actual).to eq(reference)
  end
end
