# PARG language server

`parsanol parg lsp` runs a language server for `.parg` grammars over stdio
(JSON-RPC 2.0, no framework dependency). One implementation serves every
editor.

## Features

| Capability | Method | Behavior |
|---|---|---|
| Diagnostics | `textDocument/publishDiagnostics` | parse errors, lint errors, failing in-file tests; `use` imports are merged before compiling |
| Hover | `textDocument/hover` | the rule's `##` doc comment (works on definitions and references, including `helper.code`) |
| Go to definition | `textDocument/definition` | rule definition line; imported rules jump into the imported `.parg`; `use x` jumps to `x.parg` |
| Find references | `textDocument/references` | identifier tokens outside strings/comments; optional declaration |
| Completion | `textDocument/completion` | PARG keywords, rule names, imported `alias.rule` names, terminal/operator snippets |
| Semantic tokens | `textDocument/semanticTokens/full` | keywords, rule names (declaration modifier), capture names after `as`, strings, `%x` code points, comments |
| Code action | `textDocument/codeAction` | reorder all-literal alternatives longest-first |

Imports resolve from the document's own directory, then from
`PG_IMPORT_DIR` (path-separator list). Table data resolves from
`PG_TABLES_DIR`, defaulting to the document directory.

## Neovim

```lua
vim.filetype.add({ extension = { parg = "parg" } })

vim.api.nvim_create_autocmd("FileType", {
  pattern = "parg",
  callback = function(args)
    vim.lsp.start({
      name = "parsanol-parg",
      cmd = { "parsanol", "parg", "lsp" },
      root_dir = vim.fs.dirname(vim.fs.find({ ".git" }, { upward = true })[1])
        or vim.fs.dirname(args.file),
    }, { bufnr = args.buf })
  end,
})
```

`vim.lsp.config`/`vim.lsp.enable` (Neovim 0.11+) works the same way; point
`cmd` at the CLI and set `filetypes = { "parg" }`.

## VS Code

There is no dedicated extension yet. Use a generic LSP client extension
(e.g. "LSP Client") with a server definition:

```json
{
  "parsanol-parg": {
    "command": ["parsanol", "parg", "lsp"],
    "fileExtensions": ["parg"],
    "languageId": "parg"
  }
}
```

For a packaged experience, the same command can be wrapped with
`vscode-languageclient` in a minimal extension; the server needs no
workspace configuration beyond the environment variables above.

## End-to-end coverage

`spec/parsanol/parg/lsp_spec.rb` drives the server over framed stdio exactly
as an editor does: initialize capabilities, didOpen, diagnostics, hover,
definition, references, completion, semantic tokens, and imports across real
files. Every feature is exercised at the protocol level.

Client screenshots/recordings are not committed: they require an interactive
editor session. The protocol tests are the regression gate; capture a client
session when documenting a release.

## Limitations

- Positions are computed in characters; LSP specifies UTF-16 code units.
  Grammars whose lines contain astral-plane characters may show off-by-one
  highlight columns.
- Hover shows rule documentation, not inferred FIRST sets or diagnostics.
- Imports must be local files (the compiler's `use` model); remote URIs are
  not resolved.
