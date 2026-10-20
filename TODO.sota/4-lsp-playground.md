# 4 — Finish the LSP; grammar playground on the site

Status: open — Tier 1. Diagnostics already exist via
`compiler.run_tests` in the LSP; the rest is specced here.

## LSP (lib/parsanol/parg/lsp.rb)

- Diagnostics: parse errors, lint warnings, failing in-file tests (done)
- Hover: rule docs (## comments are already embedded in envelopes)
- Go-to-definition / find-references over rule names (document model:
  Parser#parse gives rules; Imports-aware)
- Completion: rule names, PARG keywords, %i// %x// literals
- Semantic tokens: rules vs captures vs keywords
- End-to-end: run against VS Code + Neovim LSP clients; document setup

## Playground (parsanol.github.io, Astro site)

- wasm parse of a live editor buffer (CodeMirror 6 + the parsanol wasm
  package): tree view, diagnostics from the wire format, capture
  highlighting
- The "all engines agree" badge: show the wasm tree alongside the
  artifact self-test result
- Shareable grammar URLs (gzip the source into the hash)
- The site is the delivery vehicle: grammar-as-artifact only lands when
  you can edit a grammar in a browser and watch it parse

## Acceptance

LSP: feature-complete against the list above with client
screenshots/recordings in the docs. Playground: deployed on
parsanol.github.io, loads a demo grammar, tree + diagnostics live.
Wasm size budget documented (the vendor is ~1.4 MB).
