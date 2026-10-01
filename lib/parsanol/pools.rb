# frozen_string_literal: true

module Parsanol
  # Pool namespace: per-type object pools backing the parser's arena
  # allocations. Each pool loads on first reference.
  module Pools
    autoload :SlicePool, "parsanol/pools/slice_pool"
    autoload :ArrayPool, "parsanol/pools/array_pool"
    autoload :PositionPool, "parsanol/pools/position_pool"
    autoload :BufferPool, "parsanol/pools/buffer_pool"
  end
end
