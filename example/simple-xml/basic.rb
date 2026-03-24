# frozen_string_literal: true

# A simple xml parser. It is simple in the respect as that it doesn't address
# any of the complexities of XML. This is ruby 1.9.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require "pp"
require "parsanol/parslet"

class XML < Parsanol::Parser
  root :document

  rule(:document) do
    (tag(close: false).as(:o) >> document.as(:i) >> tag(close: true).as(:c)) |
      text
  end

  # Perhaps we could have some syntax sugar to make this more easy?
  #
  def tag(opts = {})
    close = opts[:close] || false

    parslet = str("<")
    parslet >>= str("/") if close
    parslet >>= (str(">").absent? >> match("[a-zA-Z]")).repeat(1).as(:name)
    parslet >> str(">")
  end

  rule(:text) do
    match("[^<>]").repeat(0)
  end
end

def check(xml)
  r = XML.new.parse(xml)

  # We'll validate the tree by reducing valid pairs of tags into simply the
  # string "verified". If the transformation ends on a string, then the
  # document was 'valid'.
  #
  t = Parsanol::Transform.new do
    rule(
      o: { name: simple(:tag) },
      c: { name: simple(:tag) },
      i: simple(:t),
    ) { "verified" }
  end

  t.apply(r)
end

pp check("<a><b>some text in the tags</b></a>")
pp check("<b><b>some text in the tags</b></a>")
