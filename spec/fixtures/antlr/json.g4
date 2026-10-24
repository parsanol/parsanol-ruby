grammar Json;

/* A faithful subset of the canonical ANTLR JSON grammar
   (antlr/grammars-v4, Minecraft JSON subset). The WS -> skip lexer
   rule is omitted: the scoped v1 importer keeps whitespace
   significant, so separators are explicit and inputs are compact.
   SAFECODEPOINT's \uXXXX escapes are likewise out of the v1 charset
   vocabulary; string bodies use the explicit exclusion set. */

json: value ;

obj: '{' pair (',' pair)* '}' | '{' '}' ;
pair: STRING ':' value ;
arr: '[' value (',' value)* ']' | '[' ']' ;
value: STRING | NUMBER | obj | arr | 'true' | 'false' | 'null' ;

STRING: '"' (ESC | SAFESTRINGCHAR)* '"' ;
NUMBER: '-'? ('0' | [1-9] [0-9]*) ('.' [0-9]+)? ([eE] [+-]? [0-9]+)? ;
ESC: '\\' ["\\/bfnrt] ;
SAFESTRINGCHAR: ~["\\\n\r] ;
