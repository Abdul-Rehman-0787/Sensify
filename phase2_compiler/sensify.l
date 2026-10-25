%{
/* sensify.l - Lexer (tokenizer) for Sensify. Same file is used in Phase 1 and Phase 2. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sensify.tab.h"

int lineNumber = 1;
%}

%option noyywrap nounput noinput

digit       [0-9]
letter      [A-Za-z_]

%%

"//".*                          { /* skip comments */ }
[ \t\r]+                        { /* skip spaces */ }
\n                              { lineNumber++; }

"|>"                            { return PIPE; }
"&&"                            { return AND; }
"||"                            { return OR; }
">="                            { return GE; }
"<="                            { return LE; }
"=="                            { return EQ; }
"!="                            { return NE; }

"sensor"                        { return SENSOR; }
"endpoint"                      { return ENDPOINT; }
"pipeline"                      { return PIPELINE; }
"ingest"                        { return INGEST; }
"input"                         { return INPUT; }
"output"                        { return OUTPUT; }
"averageWindow"                 { return AVERAGEWINDOW; }
"sumWindow"                     { return SUMWINDOW; }
"filter"                        { return FILTER; }
"scale"                         { return SCALE; }
"offset"                        { return OFFSET; }
"trigger"                       { return TRIGGER; }
"emit"                          { return EMIT; }
"value"                         { return VALUE; }

{digit}+(\.{digit}+)?           { yylval.number = atof(yytext); return NUMBER; }

\"[^\"\n]*\"                    {
                                    /* copy the text without the two quote marks */
                                    int length = strlen(yytext) - 2;
                                    yylval.text = (char *)malloc(length + 1);
                                    strncpy(yylval.text, yytext + 1, length);
                                    yylval.text[length] = '\0';
                                    return STRING;
                                }

{letter}({letter}|{digit})*     { yylval.text = strdup(yytext); return IDENT; }

.                               { return yytext[0]; /* parser will report the error */ }

%%
