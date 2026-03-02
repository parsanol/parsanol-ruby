# frozen_string_literal: true

# Test Cases for Parslet Compatibility Layer
#
# Issue: Sequence with Separator Pattern not Handled Correctly
#

### Test Case 1: Repeated Named Elements with Separators
#
# Grammar Pattern:
# ```
#        listOf_formalParameter: formalParameter (op_delim formalParameter)*
# ```
#
# Input:
# ```
#        FUNCTION add(a : INTEGER; b : INTEGER) : INTEGER;
# ```
#
# Expected (Parslet):
# ```json
#        {
#          "listOf_formalParameter": [
#            {"formalParameter": {"parameterId": "a", ...}},
#            {"op_delim": ";", "formalParameter": {"parameterId": "b", ...}}
#          ]
#        }
# ```
#
# Actual (Parsanol `parse_parslet_compatible`)
# ```json
#        {
#          "listOf_formalParameter": {
#            "formalParameter": {"parameterId": "b", ...},
#            "op_delim": ";"
#          }
#        }
# ```
#
# Problem:
# - Parslet produces an **array of hashes** where each hash represents one element
# - Parsanol produces a **single merged hash**, losing the first element
#

### Test Case 2: Expression with Binary Operator
#
# Grammar Pattern:
# ```
#        simpleExpression: term (operator term)*
# ```
#
# Input:
# ```
#        a + b
# ```
#
# Expected (Parslet):
# ```json
#        {
#          "term": {...},
#          "rhs": [
#            {"item": {"operator": "+", "term": {...}}
#          ]
#        }
# ```
#
# Actual (Parsanol)
# ```json
#        {
#          "term": {...},
#          "rhs": {"item": {"operator": "+", "term": {...}}
#        }
# ```
#
# Problem:
# - Parslet produces `rhs` as an **array** (even with one element)
# - Parsanol produces `rhs` as a **hash**
#

### Test Case 3: Multiple Entities
#
# Grammar Pattern:
# ```
#        schemaBody: entityDecl*
# ```
#
# Input:
# ```
#        SCHEMA test;
#        ENTITY person; name : STRING; END_ENTITY;
#        ENTITY address; street : STRING; END_ENTITY;
#        END_SCHEMA;
# ```
#
# Expected (Parslet):
# ```json
#        {
#          "schemaBodyDeclaration": [
#            {"schemaBodyDeclaration": {"declaration": {"entityDecl": {...}}},
#            {"schemaBodyDeclaration": {"declaration": {"entityDecl": {...}}}
#          ]
#        }
# ```
#
# Actual (Parsanol)
# ```json
#        {
#          "schemaBodyDeclaration": {
#            "schemaBodyDeclaration": {"declaration": {"entityDecl": {...}}
#          }
#        }
# ```
#
# Problem:
# - Only the last entity is preserved
# - The array structure is lost
#

## Root Cause
#
# In `parslet_transform.rs`, the `flatten_sequence` function
#
#        // Line 234-238
#        if let Some(pos) = merged_hash.iter().position(|(key, _)| *key == k) {
#          merged_hash[pos] = (k.clone(), v);  // BUG: Overwrites previous value!
#        } else {
#          merged_hash.push((k.clone(), v));
#        }
#
# When the same key appears in multiple hashes (repetition pattern), the code overwrites the previous value instead of:
#
# 1. Detect this is a repetition pattern
# 2. Converting to an array of hashes
# 3. Preserving all elements
#

## Proposed Fix
#
# Modify `flatten_sequence` to detect repetition pattern
#
#        fn flatten_sequence(items: &[AstNode], arena: &mut AstArena, input: &str) -> AstNode {
#            // ... existing code ...
#
#            # NEW: Check if this is a repetition pattern (same key in multiple hashes)
#            let key_counts: HashMap<&str, usize> = // count occurrences of each key
#
#            if key_counts.values().any(|&c| c > 1) {
#                # Repetition pattern detected - keep as array of hashes
#                return AstNode::Array { /* original items */ };
#            }
#
#            // ... existing merge logic for non-repetition patterns ...
#        end
