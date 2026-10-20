#!/usr/bin/env node
// Replay exported differential-fuzz fixtures through the wasm runtime.
//
// Usage: node fuzz_wasm.mjs <export-dir>
//
// <export-dir> is produced by the Ruby differential fuzz spec with
// FUZZ_EXPORT_DIR set: gNNN.artifact.json + gNNN.cases.json, where each
// case carries the canonical shape the Ruby and Rust paths agreed on.
// This script requires `parsanol` (the @parsanol/wasm-backed runtime) to
// be resolvable from its own location.
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { PargRuntime } from "parsanol";

const dir = process.argv[2];
if (!dir) {
  console.error("usage: node fuzz_wasm.mjs <export-dir>");
  process.exit(2);
}

const WIRE_KEYS = new Set(["value", "line", "column", "offset", "length"]);

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === "object") {
    const keys = Object.keys(value);
    if (keys.includes("value") && keys.every((key) => WIRE_KEYS.has(key))) {
      return canonical(value.value);
    }
    const out = {};
    for (const key of keys) out[key] = canonical(value[key]);
    return out;
  }
  if (value === null || typeof value === "boolean" || Number.isInteger(value)) return value;
  return String(value);
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
}

const same = (left, right) => JSON.stringify(stable(left)) === JSON.stringify(stable(right));

let artifacts = 0;
let cases = 0;
let accepted = 0;
const mismatches = [];

for (const file of readdirSync(dir).sort()) {
  if (!file.endsWith(".artifact.json")) continue;
  artifacts += 1;
  const prefix = file.replace(/\.artifact\.json$/, "");
  const expected = JSON.parse(readFileSync(join(dir, `${prefix}.cases.json`), "utf8"));
  const runtime = new PargRuntime(readFileSync(join(dir, file), "utf8"));

  for (const testCase of expected.cases) {
    cases += 1;
    let ok = true;
    let shape = null;
    try {
      shape = canonical(runtime.parseShape(testCase.input));
    } catch {
      ok = false;
    }
    if (ok) accepted += 1;
    if (ok !== testCase.accept || (ok && !same(shape, canonical(testCase.shape)))) {
      mismatches.push({ artifact: prefix, input: testCase.input, expected: testCase, got: { ok, shape } });
      if (mismatches.length >= 10) break;
    }
  }
  if (mismatches.length >= 10) break;
}

console.log(`wasm fuzz: artifacts=${artifacts} cases=${cases} accepted=${accepted} mismatches=${mismatches.length}`);
if (mismatches.length > 0) {
  console.error(JSON.stringify(mismatches.slice(0, 3), null, 2));
  process.exit(1);
}
