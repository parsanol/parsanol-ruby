# frozen_string_literal: true

require "spec_helper"

# GH-71: degradation warning prints once per reason, and
# native_expressible? is a public check.
RSpec.describe "native expressibility" do
  it "answers without raising for Dynamic grammars" do
    parser = Class.new(Parsanol::Parser) do
      rule(:x) { dynamic { |_s, _c| str("a") } }
      root(:x)
    end
    expect([true, false]).to include(parser.new.native_expressible?)
  end

  it "warns once per reason across parser instances", :native do
    skip "native backend unavailable" unless Parsanol::Native.available?

    klass = Class.new(Parsanol::Parser) do
      rule(:x) { dynamic { |_s, _c| str("a") } }
      root(:x)
    end

    require "stringio"
    original_stderr = $stderr
    $stderr = StringIO.new
    begin
      3.times { klass.new.native_expressible? }
      captured = $stderr.string
    ensure
      $stderr = original_stderr
    end

    expect(captured.scan("parsanol: parsing with the Ruby engine").length).to eq(1)
  end
end
