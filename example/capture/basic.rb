# frozen_string_literal: true

# This example demonstrates how pieces of input can be captured and matched
# against later on. Without this, you cannot match here-documents and other
# self-dependent grammars.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"
require 'parsanol/parslet'
require 'parsanol/convenience'
require 'pp'

class CapturingParser < Parsanol::Parser
  root :document

  # Introduce a scope for each document. This ensures that documents can be
  # nested.
  rule(:document) { scope { doc_start >> text >> doc_end } }

  # Start of a document is a heredoc marker. This is captured in :marker
  rule(:doc_start) { str('<') >> marker >> newline }
  rule(:marker) { match['A-Z'].repeat(1).capture(:marker) }

  # The content of a document can be either lines of text or another
  # document, introduced by <HERE, where HERE is the doc marker.
  rule(:text) { (document.as(:doc) | text_line.as(:line)).repeat(1) }
  rule(:text_line) do
    captured_marker.absent? >> any >>
      (newline.absent? >> any).repeat >> newline
  end

  # The end of the document is marked by the marker that was at the beginning
  # of the document, by itself on a line.
  rule(:doc_end) { captured_marker }
  rule(:captured_marker) do
    dynamic do |_source, context|
      str(context.captures[:marker])
    end
  end

  rule(:newline) { match["\n"] }
end

parser = CapturingParser.new
pp parser.parse_with_debug %(<CAPTURE
Text1
<FOOBAR
Text3
Text4
FOOBAR
Text2
CAPTURE)
