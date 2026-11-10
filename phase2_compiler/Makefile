sensifyc: sensify.tab.c lex.yy.c
	gcc -Wall -o sensifyc sensify.tab.c lex.yy.c

sensify.tab.c sensify.tab.h: sensify.y
	bison -d sensify.y

lex.yy.c: sensify.l sensify.tab.h
	flex sensify.l

clean:
	rm -f sensifyc sensify.tab.c sensify.tab.h lex.yy.c
