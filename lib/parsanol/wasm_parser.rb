# frozen_string_literal: true

module Parsanol
  # WASM-based parser for Opal environments
  #
  # This class provides a bridge between Opal (Ruby compiled to JavaScript)
  # and the WASM parser. It uses the Parslet WASM module.
  #
  # @example In Opal environment
  #   # First, ensure WASM is loaded (in your HTML/JS)
  #   # <script src="parslet_wasm.js"></script>
  #   # <script>
  #   #   ParsletWasm.init().then(() => console.log('ready'));
  #   # </script>
  #
  #   # Then in Ruby/Opal:
  #   grammar_json = parser.to_json
  #   wasm_parser = Parsanol::WasmParser.new(grammar_json)
  #   result = wasm_parser.parse(input)
  #
  class WasmParser
    # Tags for flat array format
    TAG_NIL         = 0x00
    TAG_BOOL        = 0x01
    TAG_INT         = 0x02
    TAG_FLOAT       = 0x03
    TAG_STRING      = 0x04
    TAG_ARRAY_START = 0x05
    TAG_ARRAY_END   = 0x06
    TAG_HASH_START  = 0x07
    TAG_HASH_END    = 0x08
    TAG_HASH_KEY    = 0x09

    # @return [String] The grammar JSON
    attr_reader :grammar_json

    # Create a new WASM parser
    #
    # @param grammar_json [String, Hash] Grammar JSON string or hash
    # @raise [RuntimeError] If WASM is not initialized
    #
    def initialize(grammar_json)
      @grammar_json = grammar_json.is_a?(Hash) ? grammar_json.to_json : grammar_json
      @parser = nil
    end

    # Parse input string and return AST
    #
    # @param input [String] Input string to parse
    # @return [Hash, Array, String, nil] Parsed AST
    # @raise [RuntimeError] If parsing fails
    #
    def parse(input)
      ensure_initialized
      result = `#{@parser}.parse(#{input})`
      convert_js_to_ruby(result)
    end

    # Parse input and return flat array (more efficient for large results)
    #
    # @param input [String] Input string to parse
    # @return [Array] Flat array with tagged values
    # @raise [RuntimeError] If parsing fails
    #
    def parse_flat(input)
      ensure_initialized
      flat = `#{@parser}.parseFlat(#{input})`
      decode_flat(flat, input)
    end

    # Parse input and return JSON string
    #
    # @param input [String] Input string to parse
    # @return [String] JSON string of parsed AST
    # @raise [RuntimeError] If parsing fails
    #
    def parse_json(input)
      ensure_initialized
      `#{@parser}.parseJson(#{input})`
    end

    # Check if WASM is available and initialized
    #
    # @return [Boolean]
    #
    def self.available?
      `
        if (typeof ParsletWasm === 'undefined') {
          return false;
        }
        return ParsletWasm.isInitialized ? ParsletWasm.isInitialized() : false;
      `
    end

    # Initialize WASM module (async)
    #
    # @return [Promise] Promise that resolves when WASM is ready
    #
    def self.init
      `
        if (typeof ParsletWasm !== 'undefined' && ParsletWasm.initParslet) {
          return ParsletWasm.initParslet();
        }
        return Promise.reject(new Error('ParsletWasm not loaded'));
      `
    end

    private

    def ensure_initialized
      return if @parser

      `
        if (typeof ParsletWasm === 'undefined') {
          throw new Error('ParsletWasm not loaded. Include parslet.js and parsanol_native_bg.wasm');
        }
        if (!ParsletWasm.isInitialized || !ParsletWasm.isInitialized()) {
          throw new Error('WASM not initialized. Call Parsanol::WasmParser.init first');
        }
        #{@parser} = new ParsletWasm.ParsletParser(#{@grammar_json});
      `
    end

    # Convert JavaScript result to Ruby
    def convert_js_to_ruby(_js_obj)
      %x{
        if (js_obj === null || js_obj === undefined) {
          return nil;
        }
        if (typeof js_obj === 'boolean') {
          return js_obj;
        }
        if (typeof js_obj === 'number') {
          return js_obj;
        }
        if (typeof js_obj === 'string') {
          return js_obj;
        }
        if (Array.isArray(js_obj)) {
          return js_obj.map(function(item) {
            return #{convert_js_to_ruby(`item`)};
          });
        }
        if (typeof js_obj === 'object') {
          var hash = {};
          Object.keys(js_obj).forEach(function(key) {
            hash[key] = #{convert_js_to_ruby(`js_obj[key]`)};
          });
          return hash;
        }
        return nil;
      }
    end

    # Decode flat array format to Ruby objects
    def decode_flat(flat, input)
      stack = []
      i = 0
      length = `#{flat}.length`

      while i < length
        tag = `#{flat}[#{i}]`

        case tag
        when TAG_NIL
          stack << nil
          i += 1
        when TAG_BOOL
          stack << (`#{flat}[#{i + 1}]` != 0)
          i += 2
        when TAG_INT
          stack << `#{flat}[#{i + 1}]`
          i += 2
        when TAG_FLOAT
          bits = `#{flat}[#{i + 1}]`
          float = `new Float64Array(new BigUint64Array([#{bits}]).buffer)[0]`
          stack << float
          i += 2
        when TAG_STRING
          offset = `#{flat}[#{i + 1}]`
          len = `#{flat}[#{i + 2}]`
          stack << input.byteslice(offset, len)
          i += 3
        when TAG_ARRAY_START
          stack << :array_marker
          i += 1
        when TAG_ARRAY_END
          items = []
          items.unshift(stack.pop) while stack.last != :array_marker
          stack.pop # Remove marker
          stack << items
          i += 1
        when TAG_HASH_START
          stack << :hash_marker
          i += 1
        when TAG_HASH_END
          pairs = []
          while stack.last != :hash_marker
            value = stack.pop
            key = stack.pop
            pairs.unshift([key, value])
          end
          stack.pop # Remove marker
          stack << pairs.to_h
          i += 1
        when TAG_HASH_KEY
          len = `#{flat}[#{i + 1}]`
          i += 3 # Skip tag, len, and placeholder
          # Read key bytes
          key_bytes = []
          chunks = (len + 7) / 8
          chunks.times do |j|
            chunk = `#{flat}[#{i + j}]`
            8.times do |k|
              break if key_bytes.length >= len

              key_bytes << ((chunk >> (k * 8)) & 0xff)
            end
          end
          i += chunks
          key = key_bytes.pack('C*').force_encoding('UTF-8')
          stack << key
        else
          raise "Unknown tag: #{tag} at index #{i}"
        end
      end

      stack.first
    end
  end

  # Factory method to create appropriate parser
  #
  # @param grammar_json [String, Hash] Grammar JSON
  # @return [WasmParser, Object] Appropriate parser for current environment
  #
  def self.create_wasm_parser(grammar_json)
    WasmParser.new(grammar_json)
  end
end
