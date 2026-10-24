# frozen_string_literal: true

require "parsanol"

# C1 (rs#297 U1): rendered columns are CHARACTER counts — the guide's
# wire contract, matching rs's chars() walk. Offsets stay bytes. A
# byte column overstates every multibyte line.
RSpec.describe "character-based columns" do
  def column_at(input, offset)
    Parsanol::Slice.new(offset, "", input).line_and_column.last
  end

  it "counts characters, not bytes, on a multibyte line" do
    expect(column_at("日本語 x", 10)).to eq(5) # byte column would be 11
  end

  it "counts characters after a multibyte prefix across a newline" do
    expect(column_at("café\n日本語", 6)).to eq(1)
  end

  it "counts a trailing multibyte character" do
    expect(column_at("café", 3)).to eq(4) # é starts at byte 3 (c=0,a=1,f=2), char 4
  end

  it "stays one-based at line starts and file start" do
    expect(column_at("a\nb\nc", 2)).to eq(1)
    expect(column_at("abc", 0)).to eq(1)
  end
end
