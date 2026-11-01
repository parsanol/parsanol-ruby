# frozen_string_literal: true

require "parsanol/parg"

# The serializer-cache collision (parsanol-ruby#404): a compile that
# precedes another compile could poison it. The structure fingerprint
# treated Atoms::Entity as transparent, but the serialized grammar JSON
# keeps the Entity nodes — two webs whose Entities point at different
# rules shared a cache key while serializing differently, and the
# grammar cache then served one grammar's atoms for the other.
RSpec.describe "compile isolation across grammars (ruby#404)" do
  def v2_source
    <<~PARG
      grammar CaptureOverReference version "1.0.0" edition "v2" {
        root = number as num
        number = 1*digit
        digit = %x30-39
        entry main: root
      }
    PARG
  end

  def v1_source
    <<~PARG
      grammar ConformanceEntries version "1.0.0" edition "v1" {
        word = 1*%x61-7A as word
        num = 1*%x30-39 as num
        entry word: word
        entry num: num
      }
    PARG
  end

  def num_atoms(source)
    document = Parsanol::PARG::Parser.new(source).parse
    compiled = Parsanol::PARG::Compiler.new(document, nil).compile
    JSON.generate(compiled.envelope["entries"]["num"]["grammar"]["atoms"])
  end

  it "a preceding edition-2 compile leaves a later edition-1 compile untouched" do
    solo = num_atoms(v1_source)
    Parsanol::PARG::Parser.new(v2_source).parse
    Parsanol::PARG::Compiler.new(Parsanol::PARG::Parser.new(v2_source).parse, nil).compile
    expect(num_atoms(v1_source)).to eq(solo)
  end

  it "the structure fingerprint distinguishes webs that serialize differently" do
    v2_result = Parsanol::PARG::Compiler.new(
      Parsanol::PARG::Parser.new(v2_source).parse, nil
    ).compile
    v1_result = Parsanol::PARG::Compiler.new(
      Parsanol::PARG::Parser.new(v1_source).parse, nil
    ).compile
    v2_root = v2_result.atoms["main"] || v2_result.atoms[:main] || v2_result.atoms.each_value.first
    v1_num = v1_result.atoms["num"] || v1_result.atoms[:num] || v1_result.atoms.each_value.first
    v2_key = Parsanol::Native::Parser.send(:grammar_cache_key, v2_root)
    v1_key = Parsanol::Native::Parser.send(:grammar_cache_key, v1_num)
    expect(v2_key).not_to eq(v1_key)
  end
end
