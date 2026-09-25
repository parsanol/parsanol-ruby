# frozen_string_literal: true

module Parsanol
  module PG
    # PG intermediate representation node.
    #
    # kind + payload slots:
    #   [:lit,   string, fold]            literal; fold = case-insensitive
    #   [:class, ranges]                  byte ranges [[lo, hi], ...]
    #   [:seq,   items]
    #   [:alt,   branches]                ordered choice
    #   [:rep,   child, min, max]         max nil = unbounded
    #   [:opt,   child]                   maybe (0..1)
    #   [:pred,  positive, child]         &x / !x
    #   [:cap,   name, child]             x as name
    #   [:ref,   name]                    rule reference
    #   [:table, table, column]           alternatives expanded from data
    Node = Struct.new(:kind, :a, :b, :c)
  end
end
