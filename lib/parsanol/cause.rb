# frozen_string_literal: true

# Represents a cause why a parse did fail. Stores information about
# parse failure including:
# - message: Human-readable error description
# - source: The source object being parsed
# - position: Byte position where error occurred
# - children: Nested causes (for deeper context)
#
# @example
#   cause = Parsanol::Cause.new(
#     "Expected at least one",
#     source,
#     5
#   )
#   cause.children  # => []
#   cause.to_s  # => "Expected at least one"
#
module Parsanol
  class Cause
    # @return [Array<String>] Error message parts
    attr_reader :message

    # @return [Parsanol::Source] Source being parsed
    attr_reader :source

    # @return [Integer] Byte position where error occurred
    attr_reader :position

    # Alias for position (API compatibility)
    alias pos position

    # @return [Array<Cause>] Child causes
    attr_reader :children

    # Creates a new cause for parse failure
    #
    # @param message [String, Array<String>] Error description
    # @param source [Parsanol::Source] Source being parsed
    # @param position [Integer] Byte position where error occurred
    # @param children [Array<Cause>] Nested causes (optional)
    def initialize(message, source, position, children = [])
      @message = Array(message)
      @source = source
      @position = position
      @children = children.nil? ? [] : children
      @parsing_label = nil
    end

    # Factory method for creating a cause
    #
    # @param source [Parsanol::Source] source being parsed
    # @param position [Integer] Byte position where error occurred
    # @param message [String, Array<String>] Error description
    # @param children [Array<Cause>] Nested causes
    # @return [Cause] New cause instance
    def self.format(source, position, message, children = [])
      new(message, source, position, children)
    end

    # Associates a label with this cause for parsing context
    #
    # @param label [String] Description of what was being parsed
    # @return [void]
    def set_label(label)
      @parsing_label = " while parsing #{label}"
      @children.each { |c| c.set_label(label) }
    end

    # Formats this cause as a human-readable string
    #
    # @return [String] Formatted error message
    def to_s
      line_num, col_num = @source.line_and_column(@position)

      formatted_msg = @message.map do |msg|
        msg.respond_to?(:to_slice) ? msg.content.inspect : msg.to_s
      end.join

      "#{formatted_msg} at line #{line_num} char #{col_num}#{@parsing_label}."
    end

    # Generates a tree-style visualization of error causes
    #
    # @return [String] ASCII tree representation
    def ascii_tree
      output = StringIO.new
      build_tree_recursive(self, output, [true])
      output.string
    end

    # Raises a ParseFailed exception with this cause's information
    #
    # @raise [Parsanol::ParseFailed] Always
    def raise
      exc = Parsanol::ParseFailed.new(to_s, self)
      Kernel.raise exc
    end

    private

    def build_tree_recursive(node, stream, prefix_flags)
      render_prefix(stream, prefix_flags)
      stream.puts node.to_s

      node.children.each do |child|
        is_last_child = (node.children.last == child)
        build_tree_recursive(child, stream, prefix_flags + [is_last_child])
      end
    end

    def render_prefix(stream, prefix_flags)
      return if prefix_flags.size < 2

      prefix_flags[1..-2].each do |is_last|
        stream.print is_last ? '   ' : '|  '
      end

      stream.print prefix_flags.last ? '`- ' : '|- '
    end
  end
end
