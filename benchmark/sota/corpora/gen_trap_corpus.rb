# Deterministic pathological JSON corpus: documented backtracking and
# scan traps, valid RFC 8259 documents. Same shape as the JSON corpus
# (name -> document text), so every existing harness can consume it.
require "json"

def deepen(open_token, close_token, depth, inner)
  (open_token * depth) + inner + (close_token * depth)
end

docs = {
  # Nesting depth stresses recursion limits and the arena's container
  # stack; a backtracking parser that copies intermediate arrays pays
  # quadratically here. Kept at 150: the portable engine's governor
  # counts atom frames, so JSON nesting fails near ~198 levels (see the
  # deep-nesting diagnostic issue) — the corpus targets the supported
  # range and the ceiling is documented, not exercised.
  "deep_arrays" => deepen("[", "]", 150, "0"),
  "deep_objects" => deepen('{"k":', "}", 100, "0"),

  # Token-prefix near misses (`tru`, `fals`, `nul`) force the ordered
  # choice to try boolean/null alternatives before falling through to
  # the string rule, at volume.
  "near_miss_tokens" => JSON.generate(
    Array.new(2000) { |i| %w[tru fals nul nulll trueish falsex][i % 6] },
  ),

  # Escape-heavy scanning: every string body is a maximal escape run.
  "escape_storm" => JSON.generate(
    { "s" => ("\\\"\n\t\b\f\r/" * 2500) },
  ),

  # One very long string: scan-loop throughput without nesting.
  "long_string" => JSON.generate({ "s" => "x" * 200_000 }),

  # Wide flat container: per-element dispatch and memo churn.
  "big_array" => JSON.generate(Array.new(20_000) { |i| i }),

  # Wide object: key interning and hash-container growth.
  "wide_object" => JSON.generate(
    Array.new(4_000) { |i| ["key_#{i}", i] }.to_h,
  ),

  # Whitespace-heavy pretty printing: skip/trivia loops and position
  # bookkeeping at every token.
  "whitespace_heavy" => JSON.pretty_generate(
    { "items" => Array.new(400) { |i| { "id" => i, "ok" => i.even? } } },
  ),

  # Number grammar edges: extremes, signs, exponents, negative zero.
  "number_zoo" => JSON.generate(
    [0, -0.0, 1e300, -1e-300, 12345678901234567890, 1.5e-7, -42, 0.0001],
  ),
}

File.write(
  File.join(__dir__, "traps_inputs.json"),
  JSON.generate(docs),
)
puts "wrote #{docs.size} trap documents: #{docs.map { |k, v| "#{k}=#{v.bytesize}B" }.join(', ')}"
