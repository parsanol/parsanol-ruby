# frozen_string_literal: true


module Parsanol::Atoms
  # A series of helper functions that have the common topic of flattening
  # result values into the intermediary tree that consists of Ruby Hashes and
  # Arrays.
  #
  # This module has one main function, #flatten, that takes an annotated
  # structure as input and returns the reduced form that users expect from
  # Atom#parse.
  #
  # NOTE: Since all of these functions are just that, functions without
  # side effects, they are in a module and not in a class. Its hard to draw
  # the line sometimes, but this is beyond.
  #
  module CanFlatten
    # Takes a mixed value coming out of a parslet and converts it to a return
    # value for the user by dropping things and merging hashes.
    #
    # Named is set to true if this result will be embedded in a Hash result from
    # naming something using <code>.as(...)</code>. It changes the folding
    # semantics of repetition.
    #
    def flatten(value, named=false)
      # Passes through everything that isn't an array of things
      # Phase 43: Use simpler check - if it's not an Array, return as-is
      return value unless value.is_a?(Array)

      # Extracts the s-expression tag
      tag = value[0]

      # Phase 43: Optimize flattening - reduce method call overhead
      # For single element arrays (common case), handle directly
      tail_size = value.size - 1
      if tail_size == 1
        flattened = flatten(value[1])
        case tag
          when :sequence
            return flattened
          when :maybe
            return named ? flattened : (flattened || '')
          when :repetition
            return flatten_repetition([flattened], named)
        end
      end

      # Flatten each element
      result = Array.new(tail_size)
      i = 0
      while i < tail_size
        result[i] = flatten(value[i + 1])
        i += 1
      end

      case tag
        when :sequence
          return flatten_sequence(result)
        when :maybe
          return named ? result.first : result.first || ''
        when :repetition
          return flatten_repetition(result, named)
      end

      fail "BUG: Unknown tag #{tag.inspect}."
    end

    # Lisp style fold left where the first element builds the basis for
    # an inject. Optimized with early return and reduced method calls.
    #
    def foldl(list, &block)
      len = list.size
      return '' if len == 0
      return list[0] if len == 1  # Fast path for single element

      result = list[0]
      i = 1
      while i < len
        result = block.call(result, list[i])
        i += 1
      end
      result
    end

    # Flatten results from a sequence of parslets.
    #
    # @api private
    #
    def flatten_sequence(list)
      foldl(list.compact) { |r, e|        # and then merge flat elements
        merge_fold(r, e)
      }
    end
    # @api private
    # Phase 43: Optimized merge_fold - reduce repeated class checks
    def merge_fold(l, r)
      l_class = l.class
      r_class = r.class

      # equal pairs: merge. ----------------------------------------------------
      if l_class == r_class
        if l_class == Hash
          warn_about_duplicate_keys(l, r)
          return l.merge(r)
        else
          return l + r
        end
      end

      # Phase 43: Cache instance_of? checks to avoid repeated method calls
      # unequal pairs: hoist to same level. ------------------------------------
      l_is_slice = l.instance_of?(Parsanol::Slice)
      r_is_slice = r.instance_of?(Parsanol::Slice)
      l_is_str = l_class == String || l_is_slice
      r_is_str = r_class == String || r_is_slice

      # Maybe classes are not equal, but both are stringlike?
      if l_is_str && r_is_str
        # if we're merging a String with a Slice, the slice wins.
        return r if r_is_slice
        return l if l_is_slice

        fail "NOTREACHED: What other stringlike classes are there?"
      end

      # special case: If one of them is a string/slice, the other is more important
      return l if r_is_str
      return r if l_is_str

      # otherwise just create an array for one of them to live in
      return l + [r] if r_class == Hash
      return [l] + r if l_class == Hash

      fail "Unhandled case when foldr'ing sequence."
    end

    # Flatten results from a repetition of a single parslet. named indicates
    # whether the user has named the result or not. If the user has named
    # the results, we want to leave an empty list alone - otherwise it is
    # turned into an empty string.
    #
    # @api private
    #
    # Phase 43: Optimized flatten_repetition - reduce array iterations
    def flatten_repetition(list, named)
      # Phase 43: Single pass to check for hashes and arrays
      has_hash = false
      has_array = false

      i = 0
      len = list.size
      while i < len
        e = list[i]
        has_hash = true if e.instance_of?(Hash)
        has_array = true if e.instance_of?(Array)
        break if has_hash && has_array  # Early exit if both found
        i += 1
      end

      if has_hash
        # If keyed subtrees are in the array, we'll want to discard all
        # strings inbetween. To keep them, name them.
        return list.select { |e| e.instance_of?(Hash) }
      end

      if has_array
        # If any arrays are nested in this array, flatten all arrays to this
        # level.
        return list.
          select { |e| e.instance_of?(Array) }.
          flatten(1)
      end

      # Consistent handling of empty lists, when we act on a named result
      return [] if named && list.empty?

      # If there are only strings, concatenate them and return that.
      foldl(list.compact) { |s,e| s+e }
    end

    # That annoying warning 'Duplicate subtrees while merging result' comes
    # from here. You should add more '.as(...)' names to your intermediary tree.
    #
    def warn_about_duplicate_keys(h1, h2)
      d = h1.keys & h2.keys
      unless d.empty?
        warn "Duplicate subtrees while merging result of \n  #{self.inspect}\nonly the values"+
             " of the latter will be kept. (keys: #{d.inspect})"
      end
    end
  end
end
