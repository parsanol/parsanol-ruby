# frozen_string_literal: true

require "spec_helper"
require "parsanol/native"

# parsanol-ruby#139: the native-tier grammar caches. The structure-hash
# memo is keyed by the root atom object (identity), so a recycled
# object_id can never alias a new grammar to a dead grammar's handle;
# all three caches are FIFO-capped and evicted handles are released
# Rust-side so HandleEntries do not accumulate across the FFI boundary.
describe "native grammar caches", if: Parsanol::Native.available? do
  def grammar(num)
    suffix = "-v#{num}"
    Class.new(Parsanol::Parser) do
      rule(:word) { match(/[a-z]+/).repeat(1) >> str(suffix) }
      root(:word)
    end.new
  end

  def parse_with(handle, input)
    Parsanol::Native._parse_handle(handle, input).to_s
  end

  it "deduplicates handles by structure content, not tree identity" do
    first = Parsanol::Native::Parser.grammar_handle(grammar(1))
    twin = Parsanol::Native::Parser.grammar_handle(grammar(1))
    expect(twin).to eq(first)

    other = Parsanol::Native::Parser.grammar_handle(grammar(2))
    expect(other).not_to eq(first)
  end

  it "caches the structure memo per tree (identity, not object_id)" do
    Parsanol::Native::Parser.clear_cache
    Parsanol::Native::Parser.grammar_handle(grammar(3))
    Parsanol::Native::Parser.grammar_handle(grammar(3)) # twin tree
    stats = Parsanol::Native::Parser.cache_stats
    # Two distinct trees => two memo entries even though the structures
    # are identical. Under the old object_id memo this was still two —
    # but a recycled id between them would have returned the first
    # tree's hash; identity keys make that structurally impossible.
    expect(stats[:hash_cache_size]).to eq(2)
  end

  it "bounds the caches as grammars churn and re-registers on demand" do
    Parsanol::Native::Parser.clear_cache
    limit = Parsanol::Native::Parser.const_get(:CACHE_LIMIT)

    (1..(limit + 8)).each { |n| Parsanol::Native::Parser.grammar_handle(grammar(100 + n)) }

    stats = Parsanol::Native::Parser.cache_stats
    expect(stats[:hash_cache_size]).to be <= limit
    expect(stats[:grammar_cache_size]).to be <= limit
    expect(stats[:handle_cache_size]).to be <= limit

    # An evicted grammar re-registers transparently and still parses.
    handle = Parsanol::Native::Parser.grammar_handle(grammar(101))
    expect(parse_with(handle, "hello-v101")).to eq("hello-v101")
  end
end
