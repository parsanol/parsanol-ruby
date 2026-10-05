# frozen_string_literal: true

require "spec_helper"
require "parsanol/native"

# parsanol-ruby#139 residual: the ffi-gem tier keeps its own grammar
# handle map. It is now FIFO-capped at Parser::CACHE_LIMIT with
# recency refresh; evicted handles are released Rust-side and
# re-register transparently on a later parse. Runs only where a
# cdylib is present (PARSANOL_FFI_LIB or a vendored libparsanol).
describe "ffi tier grammar handle bounds", if: Parsanol::Native::Ffi.available? do
  def grammar(num)
    suffix = "-v#{num}"
    Class.new(Parsanol::Parser) do
      rule(:word) { match(/[a-z]+/).repeat(1) >> str(suffix) }
      root(:word)
    end
  end

  it "bounds the handle map as grammars churn" do
    limit = Parsanol::Native::Parser::CACHE_LIMIT

    100.times do |n|
      result = Parsanol::Native::Ffi.parse(grammar(n).new, "hello-v#{n}")
      expect(result.to_s).to include("hello-v#{n}")
    end

    handles = Parsanol::Native::Ffi.instance_variable_get(:@handles)
    expect(handles.size).to be <= limit
  end

  it "re-registers an evicted grammar transparently" do
    100.times { |n| Parsanol::Native::Ffi.parse(grammar(200 + n).new, "x-v#{200 + n}") }

    result = Parsanol::Native::Ffi.parse(grammar(200).new, "hello-v200")
    expect(result.to_s).to include("hello-v200")
  end

  it "keeps a hot grammar's handle across churn" do
    limit = Parsanol::Native::Parser::CACHE_LIMIT
    hot = grammar(300).new
    Parsanol::Native::Ffi.parse(hot, "hot-v300")
    (limit + 5).times { |n| Parsanol::Native::Ffi.parse(grammar(400 + n).new, "x-v#{400 + n}") }

    result = Parsanol::Native::Ffi.parse(hot, "hot-v300")
    expect(result.to_s).to include("hot-v300")
  end
end
