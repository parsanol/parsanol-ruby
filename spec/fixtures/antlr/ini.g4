grammar Ini;

file: line* ;
line: section | assignment | COMMENT ;
section: LBRACKET name RBRACKET ;
assignment: key EQ value ;
key: TEXT ;
value: TEXT ;
name: TEXT ;
LBRACKET: '[' ;
RBRACKET: ']' ;
EQ: '=' ;
COMMENT: ';' ~[\r\n]* ;
TEXT: [a-zA-Z0-9_.-]+ ;
