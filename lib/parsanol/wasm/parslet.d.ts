/**
 * Type definitions for Parslet WASM Parser
 *
 * @packageDocumentation
 */

/**
 * Initialize the WASM module
 * Must be called before creating parsers
 */
export function initParslet(): Promise<void>;

/**
 * Check if the WASM module is initialized
 */
export function isInitialized(): boolean;

/**
 * Grammar specification for the parser
 *
 * The grammar is a JSON object with atoms and a root index.
 */
export interface Grammar {
  /** Array of atom definitions */
  atoms: Atom[];
  /** Index of the root atom */
  root: number;
}

/**
 * Atom types in the grammar
 */
export type Atom =
  | { Str: { pattern: string } }
  | { Re: { pattern: string } }
  | { Sequence: { atoms: number[] } }
  | { Alternative: { atoms: number[] } }
  | { Repetition: { atom: number; min: number; max: number | null } }
  | { Named: { name: string; atom: number } }
  | { Entity: { atom: number } }
  | { Lookahead: { atom: number; positive: boolean } }
  | 'Cut';

/**
 * Parse result - can be various types
 */
export type ParseResult =
  | null
  | boolean
  | number
  | string
  | ParseResult[]
  | { [key: string]: ParseResult };

/**
 * High-performance parser using WebAssembly
 */
export class ParsletParser {
  /**
   * Create a new parser instance
   *
   * @param grammar - Grammar JSON string or object
   * @throws {Error} If WASM not initialized or grammar is invalid
   */
  constructor(grammar: string | Grammar);

  /**
   * Parse input string and return AST
   *
   * @param input - Input string to parse
   * @returns Parsed AST as JavaScript object
   * @throws {Error} If parsing fails
   */
  parse(input: string): ParseResult;

  /**
   * Parse input and return flat array format
   *
   * @param input - Input string to parse
   * @returns Flat array with tagged values
   * @throws {Error} If parsing fails
   */
  parseFlat(input: string): BigUint64Array;

  /**
   * Parse input and return JSON string
   *
   * @param input - Input string to parse
   * @returns JSON string of parsed AST
   * @throws {Error} If parsing fails
   */
  parseJson(input: string): string;
}

/**
 * Decode flat array format to JavaScript object
 *
 * @param flat - Flat array from parseFlat()
 * @param input - Original input string for string references
 * @returns Decoded JavaScript value
 */
export function decodeFlatArray(flat: BigUint64Array, input: string): ParseResult;

/**
 * Create a parser with automatic initialization
 *
 * @param grammar - Grammar JSON string or object
 * @returns Promise resolving to initialized parser
 */
export function createParser(grammar: string | Grammar): Promise<ParsletParser>;

/**
 * Low-level WASM parser (from wasm-bindgen)
 *
 * @internal
 */
export class WasmParser {
  constructor(grammarJson: string);
  parse(input: string): any;
  parse_flat(input: string): BigUint64Array;
  parse_json(input: string): string;
}

/**
 * WASM module initialization function
 *
 * @internal
 */
export default function init(): Promise<void>;
