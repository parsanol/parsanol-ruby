# frozen_string_literal: true

# Source position tracker for parsed content.
# Preserves both the string value and its byte offset in the original input,
# enabling precise error reporting and source mapping.
#
# Line/column is computed LAZILY on first access — zero overhead
# for users who don't need position info.
module Parsanol
  class Slice
    include Parsanol::Resettable

    attr_reader :content, :input

    def initialize(byte_offset = 0, string_content = "", input = nil)
      @byte_position = byte_offset
      @content = string_content
      @input = input
      @line_and_column = nil
    end

    def reset!(new_offset = 0, new_content = "", new_input = nil)
      @byte_position = new_offset
      @content = new_content
      @input = new_input
      @line_and_column = nil
      self
    end

    def self.from_rope(rope, offset, input = nil)
      new(offset, rope.to_s, input)
    end

    # Position
    def offset
      @byte_position
    end

    alias bytepos offset
    alias charpos offset
    alias str content

    # Equality
    def ==(other)
      return content == other if other.is_a?(String)
      return content == other.content if other.is_a?(Parsanol::Slice)

      content == other
    end

    def eql?(other)
      other.is_a?(Parsanol::Slice) && content.eql?(other.content)
    end

    def hash
      [content, offset].hash
    end

    # Delegated methods
    def match(pattern)
      content.match(pattern)
    end

    def size
      content.size
    end

    alias length size

    def empty?
      content.empty?
    end

    def +(other)
      self.class.new(@byte_position, content + other.to_s, @input)
    end

    # Lazy line/column — computed once and cached.
    def line_and_column
      raise ArgumentError, "Line/column requires input" unless @input

      @line_and_column ||= compute_line_and_column
    end

    # Conversions
    def to_str
      content.to_s
    end

    alias to_s to_str

    def to_slice
      self
    end

    def to_sym
      content.to_sym
    end

    def to_i
      content.to_i
    end

    def to_f
      content.to_f
    end

    def inspect
      "#{content.inspect}@#{offset}"
    end

    # JSON
    def to_json(*)
      as_json.to_json(*)
    end

    def as_json
      result = { "value" => content, "offset" => offset, "length" => length }
      if @input
        line, column = line_and_column
        result["line"] = line
        result["column"] = column
      end
      result
    end

    # Source span
    def to_span(_input = nil)
      line, column = line_and_column
      end_line, end_column = line_and_column_at(offset + length)
      start_pos = SourcePosition.new(offset: offset, line: line, column: column)
      end_pos = SourcePosition.new(offset: offset + length, line: end_line,
                                   column: end_column)
      SourceSpan.new(start_pos: start_pos, end_pos: end_pos)
    end

    private

    def compute_line_and_column
      line_and_column_at(@byte_position)
    end

    # Unified line/column computation:
    # - String input: compute from input string
    # - LineCache: delegate to cache
    def line_and_column_at(pos)
      if @input.respond_to?(:line_and_column)
        # LineCache or duck-typed object
        @input.line_and_column(pos)
      else
        # String input
        prefix = @input.byteslice(0, pos) || ""
        line = 1 + prefix.count("\n")
        last_nl = prefix.rindex("\n")
        column = last_nl ? pos - last_nl : pos + 1
        [line, column]
      end
    end
  end
end
