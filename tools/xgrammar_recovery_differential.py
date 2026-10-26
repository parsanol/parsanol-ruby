"""ruby#321 partial-mask differential: the recovery export mode vs the
engines' recovery path over the seeded corruption stream.

For each seed of the pinned rs#304 LCG stream: corrupt the clean input,
ask the ruby engine's parse_recovering whether the string RECOVERS
(ok or resync spans) and whether the recovered parse reached the end of
input, and ask XGrammar's matcher whether the recovery-mode export
accepts it. The normative gate:

  fully recovered (resynced AND resumed to input end)  => accepted
  clean                                                 => accepted

The buckets outside the escape grammar's language, counted and listed
rather than hidden:

- **recovered_partial**: the engine consumed a resync span but never
  resumed to input end — outside the escape language by design.
- **recovered_rejected** (declared): strings where the ENGINE scanned
  FORWARD to the first pattern match. The escape grammar anchors junk
  at the failure boundary — the correct DECODER semantics (the mask
  emits the junk from the violation point; it cannot skip bytes it
  has not emitted). The engine scans forward only because it
  discovers the violation after the junk began.
- **recovered_rejected** (inferred, no declared pattern): the escape
  form requires the declaration — the numbers are the quantitative
  recommendation to declare one.
- **not_recovered_accepted**: the known CFG-vs-ordered-choice class.

Strings XGrammar accepts while the PEG engine does not recover are the
known CFG-vs-ordered-choice class — counted, listed, never hidden.

Not a CI gate: needs a local venv (pip install xgrammar). Run from the
gem root:

  PARSANOL_LIB=$PWD \\
  PARG_CONFORMANCE_DIR=../parsanol-rs/corpus/conformance \\
  python3 tools/xgrammar_recovery_differential.py
"""
import json, os, subprocess, sys

PARSANOL_LIB = os.environ["PARSANOL_LIB"]
CONFORMANCE = os.environ["PARG_CONFORMANCE_DIR"]


def ruby_json(script, *args):
    out = subprocess.run(
        ["ruby", "-e",
         '$LOAD_PATH.unshift File.expand_path("lib", ENV["PARSANOL_LIB"]);'
         'require "parsanol"; require "parsanol/parg"; require "json";' + script,
         *args],
        capture_output=True, text=True, env={**os.environ},
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip().splitlines()[-1])
    return json.loads(out.stdout)


EXPORT_SCRIPT = (
    'artifact = Parsanol::PARG::Artifact.from_json(File.read(ARGV[0]));'
    'envelope = JSON.generate(artifact.envelope);'
    'recovery = Parsanol::PARG::Export.call(envelope, target: :xgrammar, recovery: true);'
    'plain = Parsanol::PARG::Export.call(envelope, target: :xgrammar);'
    'entry = artifact.envelope["default_entry"];'
    'print JSON.generate([recovery, plain, entry])'
)

SEED_SCRIPT = '''
class Lcg
  def initialize(seed) = (@state = seed)
  def next_u64
    @state = ((@state * 6364136223846793005) + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
    @state >> 11
  end
end
KINDS = %i[delete substitute insert duplicate].freeze
def corrupt(input, seed, count)
  rng = Lcg.new(0x5EED_0000 + seed)
  bytes = input.bytes
  count.times do
    return bytes.push(120) if bytes.empty?
    kind = KINDS[rng.next_u64 % 4]
    pos = rng.next_u64 % bytes.length
    pos -= 1 while (bytes[pos] & 0xC0) == 0x80 && pos.positive?
    case kind
    when :delete then bytes.delete_at(pos)
    when :substitute then bytes[pos] = 122
    when :insert then bytes.insert(pos, 122)
    when :duplicate then bytes.insert(pos, bytes[pos])
    end
  end
  bytes.pack("C*").force_encoding(Encoding::UTF_8)
end
text = File.read(File.join(ENV["PARG_CONFORMANCE_DIR"], ARGV[0] + ".json"))
artifact = Parsanol::PARG::Artifact.from_json(text)
envelope = JSON.parse(text)
entry = envelope.fetch("default_entry")
clean = envelope["tests"].find { |t| t["kind"] == "accept" }.fetch("input")
# Fully recovered = the resync spans splice out to a string that
# parses clean (consumed_upto on the wire is the PRE-resync deepest
# position, so it cannot serve as the resume oracle).
rows = [{ "input" => clean, "recovered" => true, "clean" => true, "fully_consumed" => true }]
64.times do |seed|
  corrupted = corrupt(clean, seed, 1 + (seed % 3))
  got = artifact.parse_recovering(entry, corrupted)
  recovered = got["ok"] == true || Array(got["resyncs"]).any?
  fully = false
  if recovered && !got["ok"]
    spans = Array(got["resyncs"]).sort_by { |s| s["offset"] }
    dejunked = spans.reverse.reduce(corrupted) do |text, span|
      text[0...span["offset"]] + text[span["resumed_at"]..]
    end
    fully = begin
      artifact.parse(entry, dejunked)
      true
    rescue Parsanol::ParseFailed
      false
    end
  end
  rows << { "input" => corrupted,
            "recovered" => recovered,
            "fully_consumed" => fully,
            "clean" => false }
end
print JSON.generate(rows)
'''

import xgrammar as xg
VOCAB = [bytes([i]) for i in range(256)] + [b"ab", b"abc"]
INFO = xg.TokenizerInfo(VOCAB, xg.VocabType.RAW, stop_token_ids=[])
COMPILER = xg.GrammarCompiler(INFO, cache_enabled=False)

totals = {}
surprises = []


def bucket(artifact_name, key):
    totals.setdefault(artifact_name, {}).setdefault(key, 0)
    totals[artifact_name][key] += 1

for name in ["recovery_resync_declared", "recovery_kv"]:
    artifact_path = os.path.join(CONFORMANCE, f"{name}.json")
    ebnf_recovery, ebnf_plain, entry = ruby_json(EXPORT_SCRIPT, artifact_path)
    root = f"{entry}_entry"
    compiled_recovery = COMPILER.compile_grammar(ebnf_recovery, root_rule_name=root)
    compiled_plain = COMPILER.compile_grammar(ebnf_plain, root_rule_name=root)

    for row in ruby_json(SEED_SCRIPT, name):
        matcher = xg.GrammarMatcher(compiled_recovery, terminate_without_stop_token=True)
        accepted = matcher.accept_string(row["input"])
        if row["clean"]:
            plain_ok = xg.GrammarMatcher(
                compiled_plain, terminate_without_stop_token=True
            ).accept_string(row["input"])
            bucket(name, "clean_accepted" if plain_ok else "clean_rejected")
            if not plain_ok:
                surprises.append(f"{name}: CLEAN input the PLAIN export rejects: {row['input']!r}")
            if not accepted:
                surprises.append(f"{name}: CLEAN input recovery mode rejects: {row['input']!r}")
            continue
        if row["recovered"] and not row["fully_consumed"]:
            # The engine consumed a resync span but never resumed to the
            # end: outside the escape grammar's language by design (it
            # accepts junk BETWEEN complete iterations, ending clean).
            bucket(name, "recovered_partial")
        elif row["recovered"]:
            bucket(name, "recovered_accepted" if accepted else "recovered_rejected")
            if not accepted:
                surprises.append(f"{name}: FULLY RECOVERED but rejected: {row['input']!r}")
        else:
            bucket(name, "not_recovered_accepted" if accepted else "not_recovered_rejected")
            if accepted:
                surprises.append(f"{name}: not recovered but accepted (cfg superset): {row['input']!r}")

print(json.dumps(totals, indent=1))
for line in surprises:
    print(" ", line)
