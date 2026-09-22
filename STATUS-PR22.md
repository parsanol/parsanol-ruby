# PR #22 divergence tracking — RESOLVED (1.3.49+)

The 5 "known divergence" skips (recursive prefix-success sharing,
consume-all prefix boundary) are resolved by measurement, not by the
deferred cache_threshold benchmark:

Every caching mode (eager threshold 0, adaptive default, inactive
threshold 10_000, interval cache) and BOTH engines (ruby tier + native)
produce identical results for all five cases:

- recursive "|x|=R" -> {factor:, expr: {operator: "=", expr: {rhs: "R"}}}
  (nested; parslet 2.x yields the flat prefix-shared shape)
- consume-all "xy"   -> parses to "xy" (parslet raises ParseFailed)

Mechanism: strict (consume-all) attempts never replay shared prefix
successes, so memoization mode no longer changes trees. Parsanol
semantics = the consistent cross-engine behavior; parslet divergence is
intentional and documented in the specs. The specs now pin these
results and cross-check the native engine.
