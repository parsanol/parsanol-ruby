"""ruby#321 external half: replay the PARG->XGrammar exports through the
real XGrammar runtime; the artifacts' test acceptance sets must match.

Not a CI gate: needs a local venv with the third-party runtime
(pip install xgrammar). Run from the gem root:

  PARSANOL_LIB=$PWD PARG_CONFORMANCE_DIR=../parsanol-rs/corpus/conformance \
    python3 tools/xgrammar_replay.py

Findings (xgrammar 0.1.x, byte-level synthetic vocab): 60/71 test
cases identical; every mismatch is the CFG-vs-ordered-choice class
(the target finds derivations PEG first-match-wins forbids — the
documented export risk, now measured); unsupported constructs reject
at export naming themselves (lookahead, lookbehind, trivia, fold
groups, unicode classes)."""
import json, subprocess, sys, os

PARSANOL_LIB = os.environ["PARSANOL_LIB"]
CONFORMANCE = os.environ["PARG_CONFORMANCE_DIR"]

def export(artifact_path):
    script = (
        '$LOAD_PATH.unshift File.expand_path("lib", ENV["PARSANOL_LIB"]);'
        'require "parsanol"; require "parsanol/parg"; require "json";'
        'print Parsanol::PARG::Export.call(File.read(ARGV[0]))'
    )
    out = subprocess.run(
        ["ruby", "-e", script, artifact_path],
        capture_output=True, text=True,
        env={**os.environ},
    )
    if out.returncode != 0:
        lines = [l for l in out.stderr.strip().splitlines() if l.strip()]
        return None, lines[0] if lines else "export failed"
    return out.stdout, None

import xgrammar as xg
VOCAB = [bytes([i]) for i in range(256)] + [b"ab", b"abc"]
INFO = xg.TokenizerInfo(VOCAB, xg.VocabType.RAW, stop_token_ids=[])
COMPILER = xg.GrammarCompiler(INFO, cache_enabled=False)

results = {"matched": 0, "mismatched": 0, "export_unsupported": 0, "details": []}
for name in sorted(os.listdir(CONFORMANCE)):
    if not name.endswith(".json"):
        continue
    name = name[: -len(".json")]
    path = os.path.join(CONFORMANCE, name + ".json")
    with open(path) as fh:
        artifact = json.load(fh)
    tests = artifact.get("tests") or []
    if not tests:
        continue
    entry = artifact["default_entry"]
    if entry is None:
        continue
    ebnf, error = export(path)
    if ebnf is None:
        results["export_unsupported"] += 1
        results["details"].append(f"{name}: EXPORT UNSUPPORTED ({error})")
        continue
    try:
        compiled = COMPILER.compile_grammar(ebnf, root_rule_name=f"{entry}_entry")
    except Exception as err:
        results["export_unsupported"] += 1
        results["details"].append(f"{name}: XGRAMMAR COMPILE ERROR ({str(err).strip().splitlines()[-1]})")
        continue
    for test in tests:
        input_text = test["input"]
        want = test["kind"] in ("accept", "capture", "example", "shape")
        matcher = xg.GrammarMatcher(compiled, terminate_without_stop_token=True)
        got = matcher.accept_string(input_text)
        if got == want:
            results["matched"] += 1
        else:
            results["mismatched"] += 1
            results["details"].append(
                f"{name}: {test['kind']} {input_text!r} want={want} xgrammar={got}"
            )

print(json.dumps(results, indent=1))
