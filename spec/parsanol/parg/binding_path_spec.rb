# frozen_string_literal: true

require "parsanol"

# ruby#308 v2: compile-time binding PATH resolution. A path is a
# contract about the capture tree; a segment that does not resolve
# fails the build naming the segment (unlike the coverage lint, which
# is advisory). The validated language is what the runtime honors
# today: `capture` and `capture[].leaf`.
RSpec.describe "PARG binding path resolution" do
  def compile_with_bindings(bindings_lines, rules)
    source = <<~PARG
      grammar Bp version "1.0.0" {
        entry top: pairs
        #{rules}
        bindings pairs {
        #{bindings_lines}
        }
        test {
          accept "123"
        }
      }
    PARG
    Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse)
  end

  let(:nested_rules) do
    "  pairs = 1*((1*DIGIT as number) as pair)\n  " \
      "total = 3*DIGIT as total\n"
  end

  it "accepts a scalar path and an array path over a nested capture" do
    expect(compile_with_bindings("  pair -> pair[].number", nested_rules)).to be_truthy
  end

  it "accepts a bare capture path" do
    expect(compile_with_bindings("  number -> number", nested_rules)).to be_truthy
  end

  it "fails the build naming the root segment that resolves to nothing" do
    expect { compile_with_bindings("  ghost -> ghost[].number", nested_rules) }
      .to raise_error(Parsanol::PARG::CompileError, /ghost/)
  end

  it "fails the build on a dotted leaf" do
    expect { compile_with_bindings("  pair -> pair[].nu.mber", nested_rules) }
      .to raise_error(Parsanol::PARG::CompileError, /nu\.mber/)
  end

  it "fails the build when the [] marks a capture outside any repetition" do
    expect { compile_with_bindings("  total -> total[].digit", nested_rules) }
      .to raise_error(Parsanol::PARG::CompileError, /\[\]/)
  end

  it "fails the build on paths deeper than one repetition level" do
    expect { compile_with_bindings("  pair -> pair[].number.extra", nested_rules) }
      .to raise_error(Parsanol::PARG::CompileError, /number\.extra/)
  end

  it "fails the build when a second [] appears" do
    expect { compile_with_bindings("  pair -> pair[].number[]", nested_rules) }
      .to raise_error(Parsanol::PARG::CompileError, /\[\]/)
  end
end
