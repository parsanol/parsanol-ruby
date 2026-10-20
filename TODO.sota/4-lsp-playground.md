# 4 — Finish the LSP; grammar playground on the site

Status: done — Tier 1. LSP feature-complete (#250): imports-aware
diagnostics, hover, go-to-definition, find-references, completion,
semantic tokens, code actions; protocol-level e2e specs; client setup
in `docs/parg-lsp.md`. Playground shipped (parsanol.github.io#12) and
live at https://www.parsanol.org/playground/ with artifact-backed
demos, live tree/captures, embedded-test badge, and gzip share links.
Documented follow-ups: browser-side grammar compilation (read-only
source in v1), structured recovery diagnostics when the wasm package
ships the recovery export, and captured client screenshots.

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
