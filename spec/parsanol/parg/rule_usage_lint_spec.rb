# frozen_string_literal: true

require "parsanol"

# ruby#307 lint completion: rule-usage advisory warnings. Dead rules
# and single-use inlining candidates; entry roots and compiler-injected
# rules are exempt.
RSpec.describe "PARG rule usage lint" do
  def warnings_for(source)
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(document).warnings
  end

  it "warns when a rule is referenced by no rule" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        pair = 1*ALPHA "=" 1*DIGIT
        unused = "zzz"
        entry document: pair
      }
    PARG
    expect(warnings_for(source)).to include(/"unused" is referenced by no rule/)
  end

  it "warns when a rule has exactly one reference" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        pair = inner "=" 1*DIGIT
        inner = 1*ALPHA
        entry document: pair
      }
    PARG
    expect(warnings_for(source)).to include(/"inner" has exactly one reference/)
  end

  it "stays silent for entry roots and multiply-referenced rules" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        pair = word "=" word
        word = 1*ALPHA
        entry document: pair
      }
    PARG
    warnings = warnings_for(source)
    expect(warnings).not_to include(/"word"/)
    expect(warnings).not_to include(/"pair"/)
  end
end
