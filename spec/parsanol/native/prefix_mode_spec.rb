# frozen_string_literal: true

require "spec_helper"

RSpec.describe "native prefix mode", :native do
  let(:parser_class) do
    Class.new(Parsanol::Parser) do
      root(:word)
      rule(:word) { match("[a-z]").repeat(1).as(:w) }
    end
  end
  let(:input) { "hello world" }

  it "matches the Ruby engine's prefix tree" do
    pending "native extension predates parse_handle_prefix" unless Parsanol::Native.respond_to?(:_parse_handle_prefix)

    expect(parser_class.new.parse(input, mode: :native, prefix: true))
      .to eq(parser_class.new.parse(input, mode: :ruby, prefix: true))
  end

  it "defaults to native for prefix parses when available" do
    pending "native extension predates parse_handle_prefix" unless Parsanol::Native.respond_to?(:_parse_handle_prefix)

    expect(parser_class.new.parse(input, prefix: true)).to include(w: "hello")
  end

  it "returns the end position alongside the tree" do
    pending "native extension predates parse_handle_prefix" unless Parsanol::Native.respond_to?(:_parse_handle_prefix)

    _value, end_pos = Parsanol::Native.parse_prefix(parser_class.new.root, input)
    expect(end_pos).to eq(5)
  end
end
