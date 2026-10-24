# frozen_string_literal: true

require "parsanol"
require "json"

# ruby#308 first slice: the two halves of binding coverage, as advisory
# warnings. The grammar compiles either way — the lints carry the
# migration.
RSpec.describe "PARG binding coverage lints" do
  def warnings_for(source)
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(document).warnings
  end

  it "warns when a binding references a capture no rule produces" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        pair = word as word_capture "=" 1*DIGIT
        word = 1*( ALPHA )
        bindings pair {
          word_capture -> word (string)
          ghost -> other (string)
        }
        entry document: pair
      }
    PARG
    expect(warnings_for(source)).to include(/binding references capture "ghost"/)
  end

  it "warns when a capture is bound by no bindings section" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        pair = word as word_capture "=" num as num_capture
        word = 1*( ALPHA )
        num = 1*DIGIT
        bindings pair {
          word_capture -> word (string)
        }
        entry document: pair
      }
    PARG
    expect(warnings_for(source)).to include(/capture "num_capture" is bound by no bindings section/)
  end

  it "stays silent when every capture is bound and every binding resolves" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        pair = word as word_capture "=" num as num_capture
        word = 1*( ALPHA )
        num = 1*DIGIT
        bindings pair {
          word_capture -> word (string)
          num_capture -> num (integer)
        }
        entry document: pair
      }
    PARG
    warnings = warnings_for(source)
    expect(warnings).not_to include(/binding references capture/)
    expect(warnings).not_to include(/is bound by no bindings section/)
  end

  it "stays silent for grammars without bindings" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        pair = word as word_capture "=" 1*DIGIT
        word = 1*( ALPHA )
        entry document: pair
      }
    PARG
    expect(warnings_for(source)).not_to include(/is bound by no bindings section/)
  end
end
