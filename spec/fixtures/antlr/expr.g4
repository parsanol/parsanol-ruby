// A tiny arithmetic expression language.
grammar Expr;

prog: expr EOF ;

expr: term ((PLUS | MINUS) term)* ;
term: factor ((MUL | DIV) factor)* ;
factor: NUMBER | LPAREN expr RPAREN ;

NUMBER: [0-9]+ ([.] [0-9]+)? ;
LPAREN: '(' ;
RPAREN: ')' ;
PLUS: '+' ;
MINUS: '-' ;
MUL: '*' ;
DIV: '/' ;
