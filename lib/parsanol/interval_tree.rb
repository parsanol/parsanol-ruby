# Interval tree implementation for GPeg-style incremental parsing
# Based on the GPeg paper: "Fast Incremental PEG Parsing" (Yedidia, SLE 2021)
#
# This data structure stores memoization results keyed by position intervals [start, end)
# rather than single positions, enabling efficient invalidation of changed regions.
#
# Performance characteristics:
# - Insert: O(log n)
# - Query: O(log n + k) where k is number of overlapping intervals
# - Delete overlapping: O(log n + k)
#
class Parsanol::IntervalTree
  # A node in the interval tree
  # Each node stores an interval [low, high) and associated data
  class Node
    attr_accessor :interval, :data, :max, :left, :right

    def initialize(low, high, data)
      @interval = [low, high]  # [start, end) half-open interval
      @data = data
      @max = high  # Maximum endpoint in subtree
      @left = nil
      @right = nil
    end

    def low
      @interval[0]
    end

    def high
      @interval[1]
    end
  end

  def initialize
    @root = nil
    @size = 0
  end

  attr_reader :size

  # Insert an interval with associated data
  # @param low [Integer] Start position (inclusive)
  # @param high [Integer] End position (exclusive)
  # @param data [Object] Data to associate with this interval
  def insert(low, high, data)
    @root = insert_recursive(@root, low, high, data)
    @size += 1
  end

  # Query for all intervals that overlap with [low, high)
  # @param low [Integer] Start position (inclusive)
  # @param high [Integer] End position (exclusive)
  # @return [Array<Object>] Array of data from overlapping intervals
  def query_overlapping(low, high)
    # Empty intervals cannot overlap with anything
    return [] if low >= high

    results = []
    query_recursive(@root, low, high, results)
    results
  end

  # Query for exact interval match
  # @param low [Integer] Start position (inclusive)
  # @param high [Integer] End position (exclusive)
  # @return [Object, nil] Data if exact match found, nil otherwise
  def query_exact(low, high)
    find_exact(@root, low, high)
  end

  # Delete all intervals that overlap with [low, high)
  # Returns array of deleted data
  # @param low [Integer] Start position (inclusive)
  # @param high [Integer] End position (exclusive)
  # @return [Array<Object>] Array of data from deleted intervals
  def delete_overlapping(low, high)
    deleted = []
    @root = delete_overlapping_recursive(@root, low, high, deleted)
    @size -= deleted.size
    deleted
  end

  # Clear all intervals
  def clear
    @root = nil
    @size = 0
  end

  # Check if tree is empty
  def empty?
    @root.nil?
  end

  private

  # Insert node recursively maintaining BST property on interval start
  def insert_recursive(node, low, high, data)
    return Node.new(low, high, data) if node.nil?

    # BST insertion based on interval start position
    if low < node.low
      node.left = insert_recursive(node.left, low, high, data)
    else
      node.right = insert_recursive(node.right, low, high, data)
    end

    # Update max endpoint in this subtree
    node.max = [node.max, high].max
    node.max = [node.max, node.left.max].max if node.left
    node.max = [node.max, node.right.max].max if node.right

    node
  end

  # Query recursively for overlapping intervals
  def query_recursive(node, low, high, results)
    return if node.nil?

    # If no interval in this subtree can overlap, prune search
    return if node.max <= low

    # Check left subtree (may have overlapping intervals)
    query_recursive(node.left, low, high, results) if node.left

    # Check current node for overlap
    # Two intervals [a,b) and [c,d) overlap if: a < d AND c < b
    if node.low < high && low < node.high
      results << node.data
    end

    # Check right subtree
    # Only search right if intervals starting there could overlap
    query_recursive(node.right, low, high, results) if node.right && node.low < high
  end

  # Find exact interval match
  def find_exact(node, low, high)
    return nil if node.nil?

    if node.low == low && node.high == high
      return node.data
    end

    # Search in appropriate subtree
    if low < node.low
      find_exact(node.left, low, high)
    else
      find_exact(node.right, low, high)
    end
  end

  # Delete overlapping intervals recursively
  def delete_overlapping_recursive(node, low, high, deleted)
    return nil if node.nil?

    # Recursively delete from left subtree
    node.left = delete_overlapping_recursive(node.left, low, high, deleted) if node.left

    # Recursively delete from right subtree
    node.right = delete_overlapping_recursive(node.right, low, high, deleted) if node.right

    # Check if current node overlaps
    if node.low < high && low < node.high
      # This node overlaps - delete it
      deleted << node.data

      # Remove this node and reinsert children
      if node.left.nil?
        return node.right
      elsif node.right.nil?
        return node.left
      else
        # Node has two children - replace with inorder successor
        # Find minimum node in right subtree
        min_node = find_min(node.right)

        # Replace current node's interval and data with successor's
        node.interval = min_node.interval
        node.data = min_node.data

        # Delete the successor from right subtree
        node.right = delete_min(node.right)
      end
    end

    # Update max for this node after potential deletions
    if node
      node.max = node.high
      node.max = [node.max, node.left.max].max if node.left
      node.max = [node.max, node.right.max].max if node.right
    end

    node
  end

  # Find minimum node in subtree (leftmost)
  def find_min(node)
    return node if node.left.nil?
    find_min(node.left)
  end

  # Delete minimum node from subtree
  def delete_min(node)
    return node.right if node.left.nil?
    node.left = delete_min(node.left)

    # Update max
    node.max = node.high
    node.max = [node.max, node.left.max].max if node.left
    node.max = [node.max, node.right.max].max if node.right

    node
  end
end
