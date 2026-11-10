%{
/*
 * sensify.y - Phase 1: Sensify INTERPRETER (Flex + Bison only).
 *
 * No intermediate code is made. While Bison reads the program, our C code:
 *   1. remembers sensors, endpoints and pipeline stages in simple tables,
 *   2. checks for mistakes (undeclared names, bad window sizes ...),
 *   3. when the whole program is valid, runs every reading through the pipelines.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define maxNames     50
#define maxPipelines 10
#define maxStages    20
#define maxWindow    1000
#define maxReadings  100000

extern int lineNumber;
extern FILE *yyin;
int yylex(void);
void yyerror(const char *message);

/* ---------- kinds of things ---------- */
enum { averageStage, sumStage, filterStage, scaleStage, offsetStage, triggerStage, emitStage };
enum { opGreater, opLess, opGreaterEqual, opLessEqual, opEqual, opNotEqual };
enum { joinNone, joinAnd, joinOr };

/* ---------- tables ---------- */
typedef struct {
    int    kind;
    double amount;                 /* number used by scale / offset            */
    int    windowSize;             /* size used by averageWindow / sumWindow   */
    int    conditionCount;         /* filter: 1 or 2 comparisons               */
    int    conditionOp[2];
    double conditionValue[2];
    int    conditionJoin;          /* joinAnd or joinOr                        */
    int    endpointIndex;          /* trigger: which endpoint                  */
    char   message[256];           /* trigger: alert text                      */
    double buffer[maxWindow];      /* window: circular buffer of old values    */
    int    nextSlot;               /* window: where the next value is written  */
    int    filled;                 /* window: how many slots hold real values  */
    double runningSum;             /* window: sum of the values in the buffer  */
} Stage;

typedef struct {
    char  name[64];
    int   port;
    int   stageCount;
    Stage stages[maxStages];
} Pipeline;

char   sensorNames[maxNames][64];
int    sensorPorts[maxNames];
int    sensorCount = 0;

char   endpointNames[maxNames][64];
char   endpointUrls[maxNames][256];
int    endpointCount = 0;

Pipeline pipelines[maxPipelines];
int      pipelineCount = 0;
Pipeline *currentPipeline = NULL;

int    readingPorts[maxReadings];
double readingValues[maxReadings];
int    readingCount = 0;

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

void addSensor(const char *name, double port) {
    if (findSensor(name) >= 0 || findEndpoint(name) >= 0) reportError("name already used", name);
    if (sensorCount >= maxNames) reportError("too many sensors", name);
    if (!isWholeNumber(port) || port < 1 || port > 65535) reportError("port must be a whole number from 1 to 65535 for sensor", name);
    strcpy(sensorNames[sensorCount], name);
    sensorPorts[sensorCount] = (int)port;
    sensorCount++;
}

void addEndpoint(const char *name, const char *url) {
    if (findSensor(name) >= 0 || findEndpoint(name) >= 0) reportError("name already used", name);
    if (endpointCount >= maxNames) reportError("too many endpoints", name);
    strcpy(endpointNames[endpointCount], name);
    strncpy(endpointUrls[endpointCount], url, 255);
    endpointUrls[endpointCount][255] = '\0';
    endpointCount++;
}

void startPipeline(const char *name, const char *sensorName) {
    int i;
    int sensorIndex = findSensor(sensorName);
    if (sensorIndex < 0) reportError("pipeline ingests an undeclared sensor", sensorName);
    for (i = 0; i < pipelineCount; i++)
        if (strcmp(pipelines[i].name, name) == 0) reportError("pipeline name already used", name);
    if (pipelineCount >= maxPipelines) reportError("too many pipelines", name);

    currentPipeline = &pipelines[pipelineCount];
    memset(currentPipeline, 0, sizeof(Pipeline));
    strcpy(currentPipeline->name, name);
    currentPipeline->port = sensorPorts[sensorIndex];
}

int isSink(int kind) {
    return kind == triggerStage || kind == emitStage;
}

/* adds a new empty stage to the pipeline we are reading right now */
Stage *addStage(int kind) {
    Stage *stage;
    if (currentPipeline->stageCount > 0 &&
        isSink(currentPipeline->stages[currentPipeline->stageCount - 1].kind))
        reportError("nothing can come after a trigger/emit stage in pipeline", currentPipeline->name);
    if (currentPipeline->stageCount >= maxStages) reportError("too many stages in pipeline", currentPipeline->name);

    stage = &currentPipeline->stages[currentPipeline->stageCount];
    stage->kind = kind;
    currentPipeline->stageCount++;
    return stage;
}

Stage *lastStage() {
    return &currentPipeline->stages[currentPipeline->stageCount - 1];
}

int checkWindowSize(double size) {
    if (!isWholeNumber(size) || size < 1 || size > maxWindow) {
        fprintf(stderr, "Error on line %d: window size must be a whole number from 1 to %d\n", lineNumber, maxWindow);
        exit(1);
    }
    return (int)size;
}

void finishPipeline() {
    if (currentPipeline->stageCount == 0 ||
        !isSink(currentPipeline->stages[currentPipeline->stageCount - 1].kind))
        reportError("pipeline must end with trigger(...) or emit()", currentPipeline->name);
    pipelineCount++;
}

/* ---------- running the program ---------- */
int compareValues(int op, double left, double right) {
    if (op == opGreater)      return left > right;
    if (op == opLess)         return left < right;
    if (op == opGreaterEqual) return left >= right;
    if (op == opLessEqual)    return left <= right;
    if (op == opEqual)        return left == right;
    return left != right;
}

int filterPasses(Stage *stage, double value) {
    int first = compareValues(stage->conditionOp[0], value, stage->conditionValue[0]);
    int second;
    if (stage->conditionCount == 1) return first;
    second = compareValues(stage->conditionOp[1], value, stage->conditionValue[1]);
    if (stage->conditionJoin == joinAnd) return first && second;
    return first || second;
}

/* puts the new value in the window and updates the running sum */
void updateWindow(Stage *stage, double value) {
    double oldValue = stage->buffer[stage->nextSlot];
    stage->buffer[stage->nextSlot] = value;
    stage->runningSum = stage->runningSum + value;
    stage->runningSum = stage->runningSum - oldValue;
    stage->nextSlot = (stage->nextSlot + 1) % stage->windowSize;
    if (stage->filled < stage->windowSize) stage->filled++;
}

/* sends one value through all stages of one pipeline */
void runStages(Pipeline *pipeline, double value) {
    int i;
    for (i = 0; i < pipeline->stageCount; i++) {
        Stage *stage = &pipeline->stages[i];
        if (stage->kind == averageStage) {
            updateWindow(stage, value);
            value = stage->runningSum / (double)stage->filled;
        } else if (stage->kind == sumStage) {
            updateWindow(stage, value);
            value = stage->runningSum;
        } else if (stage->kind == filterStage) {
            if (!filterPasses(stage, value)) return;   /* value is dropped */
        } else if (stage->kind == scaleStage) {
            value = value * stage->amount;
        } else if (stage->kind == offsetStage) {
            value = value + stage->amount;
        } else if (stage->kind == triggerStage) {
            printf("ALERT -> %s : %s (value=%.2f)\n", endpointUrls[stage->endpointIndex], stage->message, value);
        } else if (stage->kind == emitStage) {
            printf("EMIT value=%.2f\n", value);
        }
    }
}

void runAllPipelines() {
    int r, p;
    for (r = 0; r < readingCount; r++)
        for (p = 0; p < pipelineCount; p++)
            if (pipelines[p].port == readingPorts[r])
                runStages(&pipelines[p], readingValues[r]);
}

/* readings file: every line is "port value", for example: 8080 70.5 */
void loadReadings(FILE *file) {
    int port;
    double value;
    while (readingCount < maxReadings && fscanf(file, "%d %lf", &port, &value) == 2) {
        readingPorts[readingCount] = port;
        readingValues[readingCount] = value;
        readingCount++;
    }
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
    : items                                { runAllPipelines(); }
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
    : AVERAGEWINDOW '(' NUMBER ')'      { Stage *s = addStage(averageStage); s->windowSize = checkWindowSize($3); }
    | SUMWINDOW '(' NUMBER ')'          { Stage *s = addStage(sumStage);     s->windowSize = checkWindowSize($3); }
    | SCALE '(' signedNumber ')'        { Stage *s = addStage(scaleStage);   s->amount = $3; }
    | OFFSET '(' signedNumber ')'       { Stage *s = addStage(offsetStage);  s->amount = $3; }
    | FILTER '(' { addStage(filterStage); } condition ')'
    | TRIGGER '(' IDENT ',' STRING ')'  {
                                            int e = findEndpoint($3);
                                            Stage *s;
                                            if (e < 0) reportError("trigger uses an undeclared endpoint", $3);
                                            s = addStage(triggerStage);
                                            s->endpointIndex = e;
                                            strncpy(s->message, $5, 255);
                                            s->message[255] = '\0';
                                        }
    | EMIT '(' ')'                      { addStage(emitStage); }
    ;

condition
    : comparison
    | comparison AND { lastStage()->conditionJoin = joinAnd; } comparison
    | comparison OR  { lastStage()->conditionJoin = joinOr;  } comparison
    ;

comparison
    : VALUE relop signedNumber          {
                                            Stage *s = lastStage();
                                            s->conditionOp[s->conditionCount] = $2;
                                            s->conditionValue[s->conditionCount] = $3;
                                            s->conditionCount++;
                                        }
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
    FILE *readingsFile = stdin;

    if (argc < 2) {
        fprintf(stderr, "Usage: %s program.sfy [readings.txt]\n", argv[0]);
        fprintf(stderr, "If readings.txt is left out, readings are read from the keyboard/pipe (stdin).\n");
        return 1;
    }
    yyin = fopen(argv[1], "r");
    if (yyin == NULL) {
        fprintf(stderr, "Cannot open program file: %s\n", argv[1]);
        return 1;
    }
    if (argc >= 3) {
        readingsFile = fopen(argv[2], "r");
        if (readingsFile == NULL) {
            fprintf(stderr, "Cannot open readings file: %s\n", argv[2]);
            return 1;
        }
    }
    loadReadings(readingsFile);
    return yyparse();
}
