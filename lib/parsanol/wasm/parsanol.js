/**
 * Parsanol WASM Parser
 *
 * High-performance parser using WebAssembly for use in browsers and Node.js.
 * Compatible with Opal (Ruby in JavaScript) for parsing in the browser.
 *
 * @example
 * // Browser/ESM
 * import { ParsanolParser } from '@parsanol/wasm';
 * const parser = new ParsanolParser(grammarJson);
 * const result = parser.parse('input text');
 *
 * @example
 * // Node.js
 * const { ParsanolParser } = require('@parsanol/wasm');
 * const parser = new ParsanolParser(grammarJson);
 * const result = parser.parse('input text');
 *
 * @example
 * // Opal
 * %x{
 *   var parser = new ParsanolNative.WasmParser(#{grammar_json});
 *   var result = parser.parse(#{input});
 *   return result;
 * }
 */

import init, { WasmParser } from './parsanol_native.js';

let initialized = false;
let initPromise = null;

/**
 * Initialize the WASM module
 * Must be called before creating parsers (automatically called on first use)
 *
 * @returns {Promise<void>}
 */
export async function initParsanol() {
  if (initialized) return;
  if (initPromise) return initPromise;

  initPromise = init().then(() => {
    initialized = true;
  });

  return initPromise;
}

/**
 * Check if the WASM module is initialized
 *
 * @returns {boolean}
 */
export function isInitialized() {
  return initialized;
}

/**
 * High-performance parser using WebAssembly
 *
 * Usage:
 *   const parser = new ParsanolParser(grammarJson);
 *   const result = parser.parse('input');
 *   console.log(result);
 */
export class ParsanolParser {
  #parser = null;
  #grammarJson = null;

  /**
   * Create a new parser instance
   *
   * @param {string|object} grammar - Grammar JSON string or object
   * @throws {Error} If WASM not initialized or grammar is invalid
   */
  constructor(grammar) {
    if (!initialized) {
      throw new Error('Parsanol WASM not initialized. Call initParsanol() first.');
    }

    this.#grammarJson = typeof grammar === 'string' ? grammar : JSON.stringify(grammar);
    this.#parser = new WasmParser(this.#grammarJson);
  }

  /**
   * Parse input string and return AST
   *
   * @param {string} input - Input string to parse
   * @returns {object} Parsed AST as JavaScript object
   * @throws {Error} If parsing fails
   */
  parse(input) {
    return this.#parser.parse(input);
  }

  /**
   * Parse input and return flat array format
   * More efficient for large results (avoids object creation)
   *
   * @param {string} input - Input string to parse
   * @returns {BigUint64Array} Flat array with tagged values
   * @throws {Error} If parsing fails
   */
  parseFlat(input) {
    return this.#parser.parse_flat(input);
  }

  /**
   * Parse input and return JSON string
   * Useful for transferring to other contexts
   *
   * @param {string} input - Input string to parse
   * @returns {string} JSON string of parsed AST
   * @throws {Error} If parsing fails
   */
  parseJson(input) {
    return this.#parser.parse_json(input);
  }

  /**
   * Reset parser state for reuse
   */
  reset() {
    // Parser state is reset automatically on each parse
  }
}

/**
 * Decode flat array format to JavaScript object
 *
 * Tag format:
 * - 0x00: nil
 * - 0x01: bool (followed by 0 or 1)
 * - 0x02: int (followed by value)
 * - 0x03: float (followed by bits)
 * - 0x04: string (followed by offset, length)
 * - 0x05: array start
 * - 0x06: array end
 * - 0x07: hash start
 * - 0x08: hash end
 * - 0x09: hash key
 *
 * @param {BigUint64Array} flat - Flat array from parseFlat()
 * @param {string} input - Original input string for string references
 * @returns {any} Decoded JavaScript value
 */
export function decodeFlatArray(flat, input) {
  const TAG_NIL = 0x00n;
  const TAG_BOOL = 0x01n;
  const TAG_INT = 0x02n;
  const TAG_FLOAT = 0x03n;
  const TAG_STRING = 0x04n;
  const TAG_ARRAY_START = 0x05n;
  const TAG_ARRAY_END = 0x06n;
  const TAG_HASH_START = 0x07n;
  const TAG_HASH_END = 0x08n;
  const TAG_HASH_KEY = 0x09n;

  let pos = 0;

  function decode() {
    const tag = flat[pos++];

    switch (tag) {
      case TAG_NIL:
        return null;

      case TAG_BOOL:
        return flat[pos++] !== 0n;

      case TAG_INT:
        return Number(flat[pos++]);

      case TAG_FLOAT: {
        const bits = flat[pos++];
        return new Float64Array(new BigUint64Array([bits]).buffer)[0];
      }

      case TAG_STRING: {
        const offset = Number(flat[pos++]);
        const length = Number(flat[pos++]);
        return input.substring(offset, offset + length);
      }

      case TAG_ARRAY_START: {
        const arr = [];
        while (flat[pos] !== TAG_ARRAY_END) {
          arr.push(decode());
        }
        pos++; // Skip ARRAY_END
        return arr;
      }

      case TAG_HASH_START: {
        const obj = {};
        while (flat[pos] !== TAG_HASH_END) {
          // Skip TAG_HASH_KEY
          pos++;

          // Read key
          const keyLen = Number(flat[pos++]);
          // Skip placeholder
          pos++;

          // Read key bytes
          let key = '';
          const numChunks = Math.ceil(keyLen / 8);
          for (let i = 0; i < numChunks; i++) {
            const chunk = flat[pos++];
            for (let j = 0; j < 8 && key.length < keyLen; j++) {
              const byte = Number((chunk >> BigInt(j * 8)) & 0xffn);
              key += String.fromCharCode(byte);
            }
          }

          // Read value
          const value = decode();
          obj[key] = value;
        }
        pos++; // Skip HASH_END
        return obj;
      }

      default:
        throw new Error(`Unknown tag: ${tag}`);
    }
  }

  return decode();
}

/**
 * Create a parser with automatic initialization
 * Convenience function that handles async initialization
 *
 * @param {string|object} grammar - Grammar JSON string or object
 * @returns {Promise<ParsanolParser>} Initialized parser
 */
export async function createParser(grammar) {
  await initParsanol();
  return new ParsanolParser(grammar);
}

// Default export
export default {
  initParsanol,
  isInitialized,
  ParsanolParser,
  decodeFlatArray,
  createParser
};
