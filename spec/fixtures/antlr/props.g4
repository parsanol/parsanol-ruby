grammar Props;

/* java.util.Properties shape: key=value / key:value entries and
   #-comments, no continuation lines, no escapes — the scoped v1
   importer's plain-text vocabulary. */

file: entry_line* ;
entry_line: assignment | comment_line ;
assignment: key (EQ | COLON) value ;
comment_line: COMMENT ;
key: TEXT ;
value: TEXT ;

EQ: '=' ;
COLON: ':' ;
COMMENT: '#' ~[\r\n]* ;
TEXT: [a-zA-Z0-9_.]+ ;
