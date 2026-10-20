#!/usr/bin/env python3
"""Lark JSON acceptance harness (LALR): same corpus + protocol."""
import json
import statistics
import sys
import time

from lark import Lark

JSON_GRAMMAR = r"""
?start: value
?value: object
      | array
      | string
      | SIGNED_NUMBER      -> number
      | "true"             -> true
      | "false"            -> false
      | "null"             -> null
array : "[" [value ("," value)*] "]"
object : "{" [pair ("," pair)*] "}"
pair  : string ":" value
string: ESCAPED_STRING
%import common.ESCAPED_STRING
%import common.SIGNED_NUMBER
%import common.WS
%ignore WS
"""

def main():
    corpus_path, iterations = sys.argv[1], int(sys.argv[2])
    corpus = json.load(open(corpus_path))
    parser = Lark(JSON_GRAMMAR, parser="lalr", start="value")
    docs = [(name, text) for name, text in corpus.items()]

    for name, text in docs:
        parser.parse(text)  # warmup + acceptance

    samples = [(name, len(text.encode()), []) for name, text in docs]
    for _ in range(iterations):
        for i, (_, text) in enumerate(docs):
            start = time.perf_counter()
            parser.parse(text)
            samples[i][2].append((time.perf_counter() - start) * 1000.0)

    for name, nbytes, times in samples:
        print(f"lark-lalr,{name},{nbytes},{iterations},{statistics.median(times):.6f}")

if __name__ == "__main__":
    main()
