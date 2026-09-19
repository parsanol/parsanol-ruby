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
    result = parser.new.native_expressible?
    expect([true, false].include?(result)).to be(true)
  end

  it "warns once per reason across parser instances", :native do
    skip "native backend unavailable" unless Parsanol::Native.available?

    begin
      Parsanol::Parser.class_variable_set(:@@unsupported_warned, {})
    rescue NameError
      nil # first use defines it
    end

    # GH-85 made dynamic atoms expressible; a genuinely unexpressible
    # atom (a bare custom subclass) still routes to the Ruby engine.
    unsupported = Class.new(Parsanol::Atoms::Custom)
    klass = Class.new(Parsanol::Parser) do
      define_method(:unsupported_rule) { unsupported.new }
      rule(:x) { unsupported.new }
      root(:x)
    end

    expect { klass.new.native_expressible? }
      .to output(/parsanol: parsing with the Ruby engine/).to_stderr
    expect { 2.times { klass.new.native_expressible? } }
      .not_to output.to_stderr
  end
end
