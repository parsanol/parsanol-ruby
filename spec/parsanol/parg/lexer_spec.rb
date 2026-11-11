# frozen_string_literal: true

require "spec_helper"

RSpec.describe Parsanol::PARG::Lexer do
  def tokens(text)
    described_class.new(text).tokens.map { |t| [t.type, t.value, t.offset] }
  end

  it "emits typed tokens with character offsets and drops whitespace and comments" do
    expect(tokens(%(a = "é" # note\nb = %x41-5A))).to eq(
      [
        [:ident, "a", 0], [:punct, "=", 2], [:str, %("é"), 4],
        [:newline, "\n", 14],
        [:ident, "b", 15], [:punct, "=", 17], [:hex, "41-5A", 19]
      ],
    )
  end

  it "keeps doc comments and strips the prefix of %i and %s strings" do
    expect(tokens(%(## doc\n%i"ab" %s"cd"))).to eq(
      [[:doc, "## doc", 0], [:newline, "\n", 6], [:istr, %("ab"), 7], [:sstr, %("cd"), 14]],
    )
  end

  it "counts offsets in characters after non-ASCII text" do
    expect(tokens(%(x = "éé" y)).last).to eq([:ident, "y", 9])
  end

  it "reports an unexpected character at its character offset" do
    expect { described_class.new(%(x = "é" @)) }
      .to raise_error(Parsanol::PARG::ParseError, /unexpected character "@" at offset 8/)
  end
end
