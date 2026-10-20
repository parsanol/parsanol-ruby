#!/usr/bin/env python3
"""tree-sitter JSON acceptance harness: same corpus + protocol."""
import json
import statistics
import sys
import time

import tree_sitter_json
from tree_sitter import Language, Parser

JSON_LANGUAGE = Language(tree_sitter_json.language())

def main():
    corpus_path, iterations = sys.argv[1], int(sys.argv[2])
    corpus = json.load(open(corpus_path))
    parser = Parser(JSON_LANGUAGE)
    docs = [(name, text.encode()) for name, text in corpus.items()]

    for name, text in docs:
        tree = parser.parse(text)
        assert tree.root_node.has_error is False, f"{name} failed to parse"

    samples = [(name, len(text), []) for name, text in docs]
    for _ in range(iterations):
        for i, (_, text) in enumerate(docs):
            start = time.perf_counter()
            parser.parse(text)
            samples[i][2].append((time.perf_counter() - start) * 1000.0)

    for name, nbytes, times in samples:
        print(f"tree-sitter,{name},{nbytes},{iterations},{statistics.median(times):.6f}")

if __name__ == "__main__":
    main()
