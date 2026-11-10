%{
/*
 * sensify.y - Phase 2: Sensify AOT COMPILER (Flex + Bison -> LLVM IR text).
 *
 * The grammar is the same as Phase 1. The difference: instead of running the
 * stages, every grammar action WRITES LLVM IR text. The result is a .ll file
 * that clang turns into a normal executable.
 *
 * The generated program reads lines "port value" from stdin (just like the
 * interpreter reads its readings) and prints the same ALERT / EMIT lines.
 *
 * IR is written into three temporary files, glued together at the end:
 *   stringsOut : text constants        globalsOut : window state variables
 *   codeOut    : one function per pipeline
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define maxNames     50
#define maxPipelines 10
#define maxWindow    1000

extern int lineNumber;
extern FILE *yyin;
int yylex(void);
void yyerror(const char *message);

enum { averageStage, sumStage, filterStage, scaleStage, offsetStage, triggerStage, emitStage };
enum { opGreater, opLess, opGreaterEqual, opLessEqual, opEqual, opNotEqual };
enum { joinNone, joinAnd, joinOr };

/* ---------- tables (only names, ports and endpoints are remembered) ---------- */
char sensorNames[maxNames][64];
int  sensorPorts[maxNames];
int  sensorCount = 0;

char endpointNames[maxNames][64];
int  endpointCount = 0;            /* the url of endpoint i is the IR constant @endpoint<i> */

char pipelineNames[maxPipelines][64];
int  pipelinePorts[maxPipelines];
int  pipelineCount = 0;

/* ---------- state used while writing IR ---------- */
FILE *stringsOut;
FILE *globalsOut;
FILE *codeOut;
char *outputPath;

int  tempCounter = 0;              /* makes %t0, %t1, ...        */
int  labelCounter = 0;             /* makes keep0, drop0, ...    */
int  messageCounter = 0;           /* makes @message0, ...       */
int  windowCounter = 0;            /* makes @window0.buf, ...    */
char currentValue[64];             /* name of the IR register that holds the value now */
int  lastStageKind = -1;           /* kind of the previous stage in this pipeline      */
int  stageCountInPipeline = 0;

char conditionRegister[64];        /* IR register holding the result of a filter condition */
int  comparisonCount = 0;
int  currentJoin = joinNone;

/* ---------- small helpers ---------- */
void reportError(const char *message, const char *name) {
    fprintf(stderr, "Error on line %d: %s '%s'\n", lineNumber, message, name);
    exit(1);
}

int findSensor(const char *name) {
    int i;
    for (i = 0; i < sensorCount; i++)
        if (strcmp(sensorNames[i], name) == 0) return i;
    return -1;
}

int findEndpoint(const char *name) {
    int i;
    for (i = 0; i < endpointCount; i++)
        if (strcmp(endpointNames[i], name) == 0) return i;
    return -1;
}

int isWholeNumber(double number) {
    return number == (double)(int)number;
}

int isSink(int kind) {
    return kind == triggerStage || kind == emitStage;
}

/* gives a fresh register name like %t7 */
void makeTemp(char *name) {
    sprintf(name, "%%t%d", tempCounter);
    tempCounter++;
}

/* writes:  @label = private constant [n x i8] c"text\00"   (n includes the zero at the end) */
void writeStringConstant(const char *label, const char *text) {
    int i;
    fprintf(stringsOut, "@%s = private constant [%d x i8] c\"", label, (int)strlen(text) + 1);
    for (i = 0; text[i] != '\0'; i++) {
        unsigned char c = (unsigned char)text[i];
        if (c < 32 || c > 126 || c == '"' || c == '\\')
            fprintf(stringsOut, "\\%02X", c);      /* special characters are written as \HEX */
        else
            fputc(c, stringsOut);
    }
    fprintf(stringsOut, "\\00\"\n");
}

/* LLVM wants a double like 6.5500000000000000e+01 (it must contain a dot or an e) */
void writeDouble(FILE *file, double number) {
    fprintf(file, "%.16e", number);
}

const char *compareName(int op) {
    if (op == opGreater)      return "ogt";
    if (op == opLess)         return "olt";
    if (op == opGreaterEqual) return "oge";
    if (op == opLessEqual)    return "ole";
    if (op == opEqual)        return "oeq";
    return "une";
}

/* ---------- semantic checks (same rules as Phase 1) ---------- */
void addSensor(const char *name, double port) {
    if (findSensor(name) >= 0 || findEndpoint(name) >= 0) reportError("name already used", name);
    if (sensorCount >= maxNames) reportError("too many sensors", name);
    if (!isWholeNumber(port) || port < 1 || port > 65535) reportError("port must be a whole number from 1 to 65535 for sensor", name);
    strcpy(sensorNames[sensorCount], name);
    sensorPorts[sensorCount] = (int)port;
    sensorCount++;
}

void addEndpoint(const char *name, const char *url) {
    char label[64];
    if (findSensor(name) >= 0 || findEndpoint(name) >= 0) reportError("name already used", name);
    if (endpointCount >= maxNames) reportError("too many endpoints", name);
    strcpy(endpointNames[endpointCount], name);
    sprintf(label, "endpoint%d", endpointCount);
    writeStringConstant(label, url);
    endpointCount++;
}

int checkWindowSize(double size) {
    if (!isWholeNumber(size) || size < 1 || size > maxWindow) {
        fprintf(stderr, "Error on line %d: window size must be a whole number from 1 to %d\n", lineNumber, maxWindow);
        exit(1);
    }
    return (int)size;
}

/* called at the start of every stage: checks the order of stages */
void beginStage(int kind) {
    if (isSink(lastStageKind))
        reportError("nothing can come after a trigger/emit stage in pipeline", pipelineNames[pipelineCount - 1]);
    lastStageKind = kind;
    stageCountInPipeline++;
}

/* ---------- IR for pipelines ---------- */
void startPipeline(const char *name, const char *sensorName) {
    int i;
    int sensorIndex = findSensor(sensorName);
    if (sensorIndex < 0) reportError("pipeline ingests an undeclared sensor", sensorName);
    for (i = 0; i < pipelineCount; i++)
        if (strcmp(pipelineNames[i], name) == 0) reportError("pipeline name already used", name);
    if (pipelineCount >= maxPipelines) reportError("too many pipelines", name);

    strcpy(pipelineNames[pipelineCount], name);
    pipelinePorts[pipelineCount] = sensorPorts[sensorIndex];
    pipelineCount++;

    lastStageKind = -1;
    stageCountInPipeline = 0;
    strcpy(currentValue, "%value");

    fprintf(codeOut, "define void @pipeline_%s(double %%value) {\n", name);
    fprintf(codeOut, "entry:\n");
}

void finishPipeline() {
    if (stageCountInPipeline == 0 || !isSink(lastStageKind))
        reportError("pipeline must end with trigger(...) or emit()", pipelineNames[pipelineCount - 1]);
    fprintf(codeOut, "  ret void\n}\n\n");
}

/*
 * Window stage. The window keeps old values in a circular buffer (a global array).
 *   slot  = where the next value goes      count = how many slots are really filled
 *   sum   = sum of the values in the buffer
 * New sum = old sum + newValue - valueThatIsLeaving. average = sum / count.
 */
void writeWindow(int size, int wantAverage) {
    int id = windowCounter;
    char slot[64], oldPtr[64], oldValue[64], sum1[64], sum2[64], sum3[64];
    char nextSlot1[64], nextSlot2[64], count1[64], isNotFull[64], count2[64], count3[64], countDouble[64], result[64];
    windowCounter++;

    fprintf(globalsOut, "@window%d.buf = internal global [%d x double] zeroinitializer\n", id, size);
    fprintf(globalsOut, "@window%d.slot = internal global i32 0\n", id);
    fprintf(globalsOut, "@window%d.count = internal global i32 0\n", id);
    fprintf(globalsOut, "@window%d.sum = internal global double 0.0e+00\n", id);

    makeTemp(slot);   makeTemp(oldPtr);  makeTemp(oldValue);
    makeTemp(sum1);   makeTemp(sum2);    makeTemp(sum3);
    makeTemp(nextSlot1); makeTemp(nextSlot2);
    makeTemp(count1); makeTemp(isNotFull); makeTemp(count2); makeTemp(count3);

    fprintf(codeOut, "  %s = load i32, ptr @window%d.slot\n", slot, id);
    fprintf(codeOut, "  %s = getelementptr [%d x double], ptr @window%d.buf, i32 0, i32 %s\n", oldPtr, size, id, slot);
    fprintf(codeOut, "  %s = load double, ptr %s\n", oldValue, oldPtr);
    fprintf(codeOut, "  store double %s, ptr %s\n", currentValue, oldPtr);
    fprintf(codeOut, "  %s = load double, ptr @window%d.sum\n", sum1, id);
    fprintf(codeOut, "  %s = fadd double %s, %s\n", sum2, sum1, currentValue);
    fprintf(codeOut, "  %s = fsub double %s, %s\n", sum3, sum2, oldValue);
    fprintf(codeOut, "  store double %s, ptr @window%d.sum\n", sum3, id);
    fprintf(codeOut, "  %s = add i32 %s, 1\n", nextSlot1, slot);
    fprintf(codeOut, "  %s = srem i32 %s, %d\n", nextSlot2, nextSlot1, size);
    fprintf(codeOut, "  store i32 %s, ptr @window%d.slot\n", nextSlot2, id);
    fprintf(codeOut, "  %s = load i32, ptr @window%d.count\n", count1, id);
    fprintf(codeOut, "  %s = icmp slt i32 %s, %d\n", isNotFull, count1, size);
    fprintf(codeOut, "  %s = add i32 %s, 1\n", count2, count1);
    fprintf(codeOut, "  %s = select i1 %s, i32 %s, i32 %d\n", count3, isNotFull, count2, size);
    fprintf(codeOut, "  store i32 %s, ptr @window%d.count\n", count3, id);

    if (wantAverage) {
        makeTemp(countDouble);
        makeTemp(result);
        fprintf(codeOut, "  %s = sitofp i32 %s to double\n", countDouble, count3);
        fprintf(codeOut, "  %s = fdiv double %s, %s\n", result, sum3, countDouble);
        strcpy(currentValue, result);
    } else {
        strcpy(currentValue, sum3);
    }
}

/* scale -> fmul, offset -> fadd */
void writeMath(const char *instruction, double amount) {
    char result[64];
    makeTemp(result);
    fprintf(codeOut, "  %s = %s double %s, ", result, instruction, currentValue);
    writeDouble(codeOut, amount);
    fprintf(codeOut, "\n");
    strcpy(currentValue, result);
}

/* one comparison like (value > 65.5) -> an i1 register */
void writeComparison(int op, double number, char *resultName) {
    makeTemp(resultName);
    fprintf(codeOut, "  %s = fcmp %s double %s, ", resultName, compareName(op), currentValue);
    writeDouble(codeOut, number);
    fprintf(codeOut, "\n");
}

void beginCondition() {
    comparisonCount = 0;
    currentJoin = joinNone;
}

void addComparison(int op, double number) {
    char newResult[64], combined[64];
    writeComparison(op, number, newResult);
    if (comparisonCount == 0) {
        strcpy(conditionRegister, newResult);
    } else {
        makeTemp(combined);
        fprintf(codeOut, "  %s = %s i1 %s, %s\n", combined, currentJoin == joinAnd ? "and" : "or", conditionRegister, newResult);
        strcpy(conditionRegister, combined);
    }
    comparisonCount++;
}

/* if the condition is false we leave the function (value is dropped) */
void endCondition() {
    int id = labelCounter;
    labelCounter++;
    fprintf(codeOut, "  br i1 %s, label %%keep%d, label %%drop%d\n", conditionRegister, id, id);
    fprintf(codeOut, "drop%d:\n  ret void\n", id);
    fprintf(codeOut, "keep%d:\n", id);
}

void writeTrigger(int endpointIndex, const char *message) {
    char label[64], result[64];
    sprintf(label, "message%d", messageCounter);
    messageCounter++;
    writeStringConstant(label, message);
    makeTemp(result);
    fprintf(codeOut, "  %s = call i32 (ptr, ...) @printf(ptr @formatAlert, ptr @endpoint%d, ptr @%s, double %s)\n",
            result, endpointIndex, label, currentValue);
}

void writeEmit() {
    char result[64];
    makeTemp(result);
    fprintf(codeOut, "  %s = call i32 (ptr, ...) @printf(ptr @formatEmit, double %s)\n", result, currentValue);
}

/* ---------- gluing everything into the final .ll file ---------- */
void copyFile(FILE *from, FILE *to) {
    int c;
    rewind(from);
    while ((c = fgetc(from)) != EOF) fputc(c, to);
}

/* main(): read "port value" pairs until the input ends and call the matching pipelines */
void writeMainFunction(FILE *out) {
    int i;
    fprintf(out, "define i32 @main() {\n");
    fprintf(out, "entry:\n");
    fprintf(out, "  %%port = alloca i32\n");
    fprintf(out, "  %%reading = alloca double\n");
    fprintf(out, "  br label %%readLoop\n");
    fprintf(out, "readLoop:\n");
    fprintf(out, "  %%scanResult = call i32 (ptr, ...) @scanf(ptr @formatScan, ptr %%port, ptr %%reading)\n");
    fprintf(out, "  %%gotTwo = icmp eq i32 %%scanResult, 2\n");
    fprintf(out, "  br i1 %%gotTwo, label %%process0, label %%finished\n");
    for (i = 0; i < pipelineCount; i++) {
        fprintf(out, "process%d:\n", i);
        fprintf(out, "  %%p%d = load i32, ptr %%port\n", i);
        fprintf(out, "  %%same%d = icmp eq i32 %%p%d, %d\n", i, i, pipelinePorts[i]);
        fprintf(out, "  br i1 %%same%d, label %%call%d, label %%process%d\n", i, i, i + 1);
        /* the call block must come before the next process block */
        fprintf(out, "call%d:\n", i);
        fprintf(out, "  %%v%d = load double, ptr %%reading\n", i);
        fprintf(out, "  call void @pipeline_%s(double %%v%d)\n", pipelineNames[i], i);
        fprintf(out, "  br label %%process%d\n", i + 1);
    }
    fprintf(out, "process%d:\n", pipelineCount);
    fprintf(out, "  br label %%readLoop\n");
    fprintf(out, "finished:\n");
    fprintf(out, "  ret i32 0\n");
    fprintf(out, "}\n");
}

void finishProgram() {
    FILE *out = fopen(outputPath, "w");
    if (out == NULL) {
        fprintf(stderr, "Cannot create output file: %s\n", outputPath);
        exit(1);
    }
    fprintf(out, "; Generated by the Sensify compiler\n");
    fprintf(out, "declare i32 @printf(ptr, ...)\n");
    fprintf(out, "declare i32 @scanf(ptr, ...)\n\n");
    copyFile(stringsOut, out);
    fprintf(out, "\n");
    copyFile(globalsOut, out);
    fprintf(out, "\n");
    copyFile(codeOut, out);
    writeMainFunction(out);
    fclose(out);
}
%}

%union {
    double number;
    char  *text;
    int    code;
}

%token SENSOR ENDPOINT PIPELINE INGEST INPUT OUTPUT
%token AVERAGEWINDOW SUMWINDOW FILTER SCALE OFFSET TRIGGER EMIT VALUE
%token PIPE AND OR GE LE EQ NE
%token <number> NUMBER
%token <text>   IDENT STRING
%type  <number> signedNumber
%type  <code>   relop

%%

program
    : items                                { finishProgram(); }
    ;

items
    : /* nothing */
    | items item
    ;

item
    : sensorDeclaration
    | endpointDeclaration
    | pipelineDeclaration
    ;

sensorDeclaration
    : SENSOR IDENT '=' INPUT '(' NUMBER ')' ';'       { addSensor($2, $6); }
    ;

endpointDeclaration
    : ENDPOINT IDENT '=' OUTPUT '(' STRING ')' ';'    { addEndpoint($2, $6); }
    ;

pipelineDeclaration
    : PIPELINE IDENT '{' INGEST IDENT                 { startPipeline($2, $5); }
      stages ';' '}'                                  { finishPipeline(); }
    ;

stages
    : /* nothing */
    | stages PIPE stage
    ;

stage
    : AVERAGEWINDOW '(' NUMBER ')'      { beginStage(averageStage); writeWindow(checkWindowSize($3), 1); }
    | SUMWINDOW '(' NUMBER ')'          { beginStage(sumStage);     writeWindow(checkWindowSize($3), 0); }
    | SCALE '(' signedNumber ')'        { beginStage(scaleStage);   writeMath("fmul", $3); }
    | OFFSET '(' signedNumber ')'       { beginStage(offsetStage);  writeMath("fadd", $3); }
    | FILTER '(' { beginStage(filterStage); beginCondition(); } condition ')'   { endCondition(); }
    | TRIGGER '(' IDENT ',' STRING ')'  {
                                            int e = findEndpoint($3);
                                            if (e < 0) reportError("trigger uses an undeclared endpoint", $3);
                                            beginStage(triggerStage);
                                            writeTrigger(e, $5);
                                        }
    | EMIT '(' ')'                      { beginStage(emitStage); writeEmit(); }
    ;

condition
    : comparison
    | comparison AND { currentJoin = joinAnd; } comparison
    | comparison OR  { currentJoin = joinOr;  } comparison
    ;

comparison
    : VALUE relop signedNumber          { addComparison($2, $3); }
    ;

relop
    : '>'   { $$ = opGreater; }
    | '<'   { $$ = opLess; }
    | GE    { $$ = opGreaterEqual; }
    | LE    { $$ = opLessEqual; }
    | EQ    { $$ = opEqual; }
    | NE    { $$ = opNotEqual; }
    ;

signedNumber
    : NUMBER        { $$ = $1; }
    | '-' NUMBER    { $$ = -$2; }
    ;

%%

void yyerror(const char *message) {
    fprintf(stderr, "Error on line %d: %s\n", lineNumber, message);
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s program.sfy output.ll\n", argv[0]);
        return 1;
    }
    yyin = fopen(argv[1], "r");
    if (yyin == NULL) {
        fprintf(stderr, "Cannot open program file: %s\n", argv[1]);
        return 1;
    }
    outputPath = argv[2];
    stringsOut = tmpfile();
    globalsOut = tmpfile();
    codeOut = tmpfile();

    /* text constants that every program needs */
    writeStringConstant("formatAlert", "ALERT -> %s : %s (value=%.2f)\n");
    writeStringConstant("formatEmit", "EMIT value=%.2f\n");
    writeStringConstant("formatScan", "%d %lf");

    return yyparse();
}
