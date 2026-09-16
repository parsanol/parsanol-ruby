# frozen_string_literal: true

require "spec_helper"

RSpec.describe "native reporter feeding", :native do
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

  it "feeds the native deepest failure to a supplied reporter" do
    events = []
    expect { parser_class.new.parse("abx", reporter: recording_reporter(events)) }
      .to raise_error(Parsanol::ParseFailed)

    expect(events).to contain_exactly(
      [:err_at, kind_of(String), 2],
    )
  end

  it "raises with the deepest expected set in the message" do
    expect { parser_class.new.parse("abx", reporter: recording_reporter([])) }
      .to raise_error(Parsanol::ParseFailed, /\[0-9\]/)
  end

  it "sends no events on success" do
    events = []
    parser_class.new.parse("ab12", reporter: recording_reporter(events))
    expect(events).to be_empty
  end
end
