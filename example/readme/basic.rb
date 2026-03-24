# frozen_string_literal: true

# The example from the readme. With this, I am making sure that the readme
# 'works'. Is this too messy?

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

# cut here -------------------------------------------------------------------
require "parsanol/parslet"
include Parsanol::Parslet

# Constructs a parser using a Parser Expression Grammar like DSL:
parser = str('"') >>
  (
    (str("\\") >> any) |
    (str('"').absent? >> any)
  ).repeat.as(:string) >>
  str('"')

# Parse the string and capture parts of the interpretation (:string above)
tree = parser.parse('"This is a \\"String\\" in which you can escape stuff"') # => {:string=>"This is a \\\"String\\\" in which you can escape stuff"}

# Here's how you can grab results from that tree:

transform = Parsanol::Transform.new do
  rule(string: simple(:x)) do
    puts "String contents: #{x}"
  end
end
transform.apply(tree)
