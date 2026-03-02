# Evaluates a block at parse time. The result from the block must be a parser
# (something which implements #apply). In the first case, the parser will then
# be applied to the input, creating the result.
#
# Dynamic parses are never cached.
#
# Example:
#   dynamic { rand < 0.5 ? str('a') : str('b') }
#
class Parsanol::Atoms::Dynamic < Parsanol::Atoms::Base
  attr_reader :block

  def initialize(block)
    @block = block
  end

  def cached?
    false
  end

  def try(source, context, consume_all)
    # Phase 55: Cache @block ivar to reduce lookup overhead
    block = @block
    result = block.call(source, context)

    # Result is a parslet atom.
    return result.apply(source, context, consume_all)
  end

  def to_s_inner(prec)
    "dynamic { ... }"
  end
end
