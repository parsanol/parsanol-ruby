# frozen_string_literal: true

# The PARG compiler builds Parsanol atoms, so requiring "parsanol/parg"
# directly must also load the parsanol core.
require "parsanol"

module Parsanol
  # PARG — the parsanol grammar language.
  #
  # A text source format for parsanol grammars: human-readable, ABNF/RFC
  # flavoured, PEG semantics (ordered choice). PARG sources compile to a
  # checksummed artifact envelope whose grammar section is the same portable
  # JSON the native engines register — the text is the contract, the JSON is
  # its compiled form.
  module PARG
    autoload :Error, "parsanol/parg/error"
    autoload :ParseError, "parsanol/parg/error"
    autoload :CompileError, "parsanol/parg/error"
    autoload :ArtifactError, "parsanol/parg/error"
    autoload :Node, "parsanol/parg/node"
    autoload :Lexer, "parsanol/parg/lexer"
    autoload :Parser, "parsanol/parg/parser"
    autoload :Document, "parsanol/parg/document"
    autoload :Compiler, "parsanol/parg/compiler"
    autoload :Artifact, "parsanol/parg/artifact"
    autoload :Bindings, "parsanol/parg/bindings"
    autoload :Render, "parsanol/parg/render"
    autoload :Derive, "parsanol/parg/derive"
    autoload :SelfHost, "parsanol/parg/selfhost"
    autoload :Frontend, "parsanol/parg/frontend"
    autoload :Lutaml, "parsanol/parg/lutaml"
    autoload :Import, "parsanol/parg/import"
    autoload :CLI, "parsanol/parg/cli"
    autoload :Lsp, "parsanol/parg/lsp"
    autoload :Lints, "parsanol/parg/lints"
    autoload :Preprocess, "parsanol/parg/preprocess"
    autoload :Visitor, "parsanol/parg/visitor"
    autoload :Imports, "parsanol/parg/imports"
    autoload :Suite, "parsanol/parg/authoring"
    autoload :Schema, "parsanol/parg/authoring"

    # PARG sources and JSON artifacts are UTF-8 by definition: read them as
    # UTF-8 whatever the locale's default external encoding, and skip a
    # byte-order mark the way YAML.safe_load_file does (GH-121).
    def self.read_utf8(path)
      File.read(path, mode: "r:bom|utf-8")
    end
  end
end
