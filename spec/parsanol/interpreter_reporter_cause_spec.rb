# frozen_string_literal: true

require "spec_helper"

# The interpreter tier's error reporting must raise ParseFailed even
# when a CUSTOM reporter's #err/#err_at return their own objects: the
# ErrorReporter::Base contract declares the return value
# "implementation-specific", so the reporter observes the failure
# events while the raise-able deepest cause is derived with the #265
# default. Before the guard the raw return value reached `cause.raise`
# and crashed with NoMethodError (private Kernel#raise) on any
# non-Cause — Hash per the README example, Array per event recording,
# nil per fire-and-forget reporters. (The native tier feeds its own
# deepest through native/parser.rb and was never affected.)
RSpec.describe "interpreter error reporting with custom reporters" do
  let(:parser_class) do
    Class.new(Parsanol::Parser) do
      root(:w)
      rule(:w) { str("ab") >> match("[0-9]").repeat(1).as(:n) }
    end
  end

  def recording_reporter(sink)
    Class.new(Parsanol::ErrorReporter::Base) do
      define_method(:err) { |_a, _s, m, _c = nil| sink << [:err, m] }
      define_method(:err_at) { |_a, _s, m, pos, _c = nil| sink << [:err_at, m, pos] }
    end.new
  end

  it "raises ParseFailed when the reporter returns an Array of events" do
    events = []
    expect { parser_class.new.parse("abx", reporter: recording_reporter(events)) }
      .to raise_error(Parsanol::ParseFailed, /\[0-9\]/)

    # The deepest failure is the err_at at offset 2 on both tiers —
    # the interpreter feeds the honest event stream (the failing
    # matcher, the repetition, the outer sequence); the native tier
    # synthesizes exactly that one event.
    expect(events).to include([:err_at, kind_of(String), 2])
  end

  it "raises ParseFailed when the reporter returns a Hash cause" do
    # The ErrorReporter::Base docstring example: err appends a Hash and
    # returns it (`@errors.last`).
    sink = []
    reporter = Class.new(Parsanol::ErrorReporter::Base) do
      define_method(:err) { |_a, _s, m, _c = nil| (sink << { position: m }) && sink.last }
      define_method(:err_at) { |_a, _s, m, pos, _c = nil| (sink << { position: pos, message: m }) && sink.last }
    end.new
    expect { parser_class.new.parse("abx", reporter: reporter) }
      .to raise_error(Parsanol::ParseFailed, /\[0-9\]/)
  end

  it "raises ParseFailed when the reporter returns nil" do
    reporter = Class.new(Parsanol::ErrorReporter::Base) do
      define_method(:err) { |_a, _s, _m, _c = nil| nil }
      define_method(:err_at) { |_a, _s, _m, _pos, _c = nil| nil }
    end.new
    expect { parser_class.new.parse("abx", reporter: reporter) }
      .to raise_error(Parsanol::ParseFailed, /\[0-9\]/)
  end

  it "still raises the built-in Deepest cause when no reporter is supplied" do
    expect { parser_class.new.parse("abx") }
      .to raise_error(Parsanol::ParseFailed, /\[0-9\]/)
  end
end
