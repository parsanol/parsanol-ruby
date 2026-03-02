# @parsanol/wasm

High-performance PEG parser using WebAssembly. Designed for use with Opal (Ruby in JavaScript) and general JavaScript applications.

## Features

- **18-44x faster** than pure Ruby parser
- **99.5% fewer allocations**
- Works in browsers and Node.js
- Full TypeScript support
- Compatible with Opal

## Installation

```bash
npm install @parsanol/wasm
```

## Usage

### Browser/ESM

```html
<script type="module">
  import { initParsanol, ParsanolParser } from '@parsanol/wasm';

  // Initialize WASM (call once)
  await initParsanol();

  // Create parser from grammar JSON
  const grammar = {
    atoms: [
      { Str: { pattern: "hello" } }
    ],
    root: 0
  };

  const parser = new ParsanolParser(grammar);

  // Parse input
  const result = parser.parse('hello');
  console.log(result); // "hello"
</script>
```

### Node.js

```javascript
const { initParsanol, ParsanolParser } = require('@parsanol/wasm');

async function main() {
  await initParsanol();

  const parser = new ParsanolParser(grammarJson);
  const result = parser.parse('input text');
  console.log(result);
}

main();
```

### Opal (Ruby in Browser)

```ruby
# First initialize WASM in JavaScript:
# Parsanol::WasmParser.init.then { puts "ready" }

require 'parsanol/wasm_parser'

grammar_json = {
  atoms: [
    { Str: { pattern: "hello" } }
  ],
  root: 0
}.to_json

parser = Parsanol::WasmParser.new(grammar_json)
result = parser.parse('hello')
puts result  # => "hello"
```
