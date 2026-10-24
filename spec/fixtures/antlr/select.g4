grammar Select;

/* A SQL SELECT-statement subset. Whitespace is a plain parser rule:
   the scoped v1 importer has no implicit-skip layer, so the grammar
   text says where whitespace is accepted — faithful to what is
   written. The case-insensitive keyword idiom (per-character sets)
   rides the importer's charset handling, and ordered choice makes
   keywords and TEXT share a first set: the compiler's
   order-dependence lint surfaces every decisive pair. */

query: ws? SELECT ws columnList ws FROM ws table (ws WHERE ws expr)? ws? SEMI? ;
columnList: STAR | column_item (COMMA column_item)* ;
column_item: TEXT ;
table: TEXT ;
expr: TEXT ;
ws: [ \t\n\r]+ ;

SELECT: [Ss][Ee][Ll][Ee][Cc][Tt] ;
FROM: [Ff][Rr][Oo][Mm] ;
WHERE: [Ww][Hh][Ee][Rr][Ee] ;
STAR: '*' ;
COMMA: ',' ;
SEMI: ';' ;
TEXT: [a-zA-Z0-9_]+ ;
