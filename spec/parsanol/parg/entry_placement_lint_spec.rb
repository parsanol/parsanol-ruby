# frozen_string_literal: true

require "parsanol"

# ruby#307: canonical entry placement (advisory). Entries at the foot;
# an entry above its rule is a style warning.
RSpec.describe "PARG entry placement lint" do
  def warnings_for(source)
    Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse).warnings
  end

  it "warns when the entry precedes its rule" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        entry document: pair
        pair = 1*ALPHA
      }
    PARG
    expect(warnings_for(source)).to include(/entry "document" is declared before/)
  end

  it "stays silent for the canonical foot placement" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        pair = 1*ALPHA
        entry document: pair
      }
    PARG
    expect(warnings_for(source)).not_to include(/entry "document"/)
  end
end
