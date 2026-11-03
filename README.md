**Запуск**

```zig
zig build -Doptimize=ReleaseFast
./zig-out/bin/vm3 Sort.bc 
```

**Результат**

```
DROP                                                  31 times
DUP                                                   28 times
ELEM                                                  21 times
CONST 1                                               16 times
CONST 1; ELEM                                         13 times
DUP; CONST 1                                          11 times
DROP; DUP                                             11 times
CONST 0                                               11 times
DROP; DROP                                            10 times
CONST 0; ELEM                                          8 times
LD ARG 0                                               7 times
ELEM; DROP                                             7 times
DUP; CONST 0                                           7 times
JMP L762                                               5 times
END                                                    5 times
SEXP 0 2                                               4 times
DUP; DUP                                               4 times
ST LOCAL 0; DROP                                       3 times
ST LOCAL 0                                             3 times
MAKE_ARRAY 2; JMP L762                                 3 times
MAKE_ARRAY 2                                           3 times
LD LOCAL 3                                             3 times
LD LOCAL 0                                             3 times
JMP L350                                               3 times
ELEM; ST LOCAL 0                                       3 times
DUP; ARRAY 2                                           3 times
CALL L351 1                                            3 times
ARRAY 2                                                3 times
TAG 0 2                                                2 times
SEXP 0 2; MAKE_ARRAY 2                                 2 times
LD LOCAL 1                                             2 times
JMP L116                                               2 times
EQ                                                     2 times
ELEM; CONST 1                                          2 times
ELEM; CONST 0                                          2 times
DUP; TAG 0 2                                           2 times
CALL L43 1                                             2 times
CALL L151 1                                            2 times
BEGIN 1 0                                              2 times
TAG 0 2; CJMPNZ L428                                   1 times
TAG 0 2; CJMPNZ L392                                   1 times
SUB; CALL L43 1                                        1 times
SUB                                                    1 times
ST LOCAL 5; DROP                                       1 times
ST LOCAL 5                                             1 times
ST LOCAL 4; DROP                                       1 times
ST LOCAL 4                                             1 times
ST LOCAL 3; DROP                                       1 times
ST LOCAL 3                                             1 times
ST LOCAL 2; DROP                                       1 times
ST LOCAL 2                                             1 times
ST LOCAL 1; DROP                                       1 times
ST LOCAL 1                                             1 times
SEXP 0 2; JMP L116                                     1 times
SEXP 0 2; CALL L351 1                                  1 times
LINE 9; LD ARG 0                                       1 times
LINE 9                                                 1 times
LINE 7; LD LOCAL 2                                     1 times
LINE 7                                                 1 times
LINE 6; LD LOCAL 1                                     1 times
LINE 6                                                 1 times
LINE 5; LD LOCAL 3                                     1 times
LINE 5                                                 1 times
LINE 3; LD ARG 0                                       1 times
LINE 3                                                 1 times
LINE 27; CONST 10000                                   1 times
LINE 27                                                1 times
LINE 25; LINE 27                                       1 times
LINE 25                                                1 times
LINE 24; LD ARG 0                                      1 times
LINE 24                                                1 times
LINE 20; LD ARG 0                                      1 times
LINE 20                                                1 times
LINE 18; LINE 20                                       1 times
LINE 18                                                1 times
LINE 16; LD LOCAL 0                                    1 times
LINE 16                                                1 times
LINE 15; LD LOCAL 0                                    1 times
LINE 15                                                1 times
LINE 14; LD ARG 0                                      1 times
LINE 14                                                1 times
LD LOCAL 5; LD LOCAL 3                                 1 times
LD LOCAL 5                                             1 times
LD LOCAL 4; SEXP 0 2                                   1 times
LD LOCAL 4                                             1 times
LD LOCAL 3; LD LOCAL 4                                 1 times
LD LOCAL 3; LD LOCAL 1                                 1 times
LD LOCAL 3; LD LOCAL 0                                 1 times
LD LOCAL 2; CALL L351 1                                1 times
LD LOCAL 2                                             1 times
LD LOCAL 1; LD LOCAL 3                                 1 times
LD LOCAL 1; GT                                         1 times
LD LOCAL 0; SEXP 0 2                                   1 times
LD LOCAL 0; JMP L350                                   1 times
LD LOCAL 0; CALL L151 1                                1 times
LD ARG 0; MAKE_ARRAY 2                                 1 times
LD ARG 0; LD ARG 0                                     1 times
LD ARG 0; DUP                                          1 times
LD ARG 0; CONST 1                                      1 times
LD ARG 0; CJMPZ L106                                   1 times
LD ARG 0; CALL L351 1                                  1 times
LD ARG 0; CALL L151 1                                  1 times
JMP L762; JMP L762                                     1 times
JMP L734                                               1 times
JMP L715                                               1 times
JMP L386                                               1 times
JMP L336                                               1 times
JMP L262                                               1 times
GT; CJMPZ L600                                         1 times
GT                                                     1 times
FAIL 7 17; JMP L762                                    1 times
FAIL 7 17                                              1 times
FAIL 14 9; JMP L350                                    1 times
FAIL 14 9                                              1 times
EQ; CJMPZ L274                                         1 times
EQ; CJMPZ L191                                         1 times
ELEM; ST LOCAL 5                                       1 times
ELEM; ST LOCAL 4                                       1 times
ELEM; ST LOCAL 3                                       1 times
ELEM; ST LOCAL 2                                       1 times
ELEM; ST LOCAL 1                                       1 times
ELEM; SEXP 0 2                                         1 times
ELEM; DUP                                              1 times
DUP; DROP                                              1 times
DROP; LINE 5                                           1 times
DROP; LINE 16                                          1 times
DROP; LINE 15                                          1 times
DROP; LD LOCAL 5                                       1 times
DROP; JMP L734                                         1 times
DROP; JMP L715                                         1 times
DROP; JMP L386                                         1 times
DROP; JMP L336                                         1 times
DROP; JMP L262                                         1 times
DROP; CONST 0                                          1 times
CONST 1; SUB                                           1 times
CONST 1; LINE 6                                        1 times
CONST 1; EQ                                            1 times
CONST 10000; CALL L43 1                                1 times
CONST 10000                                            1 times
CONST 0; LINE 9                                        1 times
CONST 0; JMP L116                                      1 times
CONST 0; EQ                                            1 times
CJMPZ L600; CONST 1                                    1 times
CJMPZ L600                                             1 times
CJMPZ L274; DUP                                        1 times
CJMPZ L274                                             1 times
CJMPZ L191; DUP                                        1 times
CJMPZ L191                                             1 times
CJMPZ L106; LD ARG 0                                   1 times
CJMPZ L106                                             1 times
CJMPNZ L637; DROP                                      1 times
CJMPNZ L637                                            1 times
CJMPNZ L428; DROP                                      1 times
CJMPNZ L428                                            1 times
CJMPNZ L392                                            1 times
CJMPNZ L280                                            1 times
CJMPNZ L197                                            1 times
CALL L117 1                                            1 times
BEGIN 2 0; LINE 25                                     1 times
BEGIN 2 0                                              1 times
BEGIN 1 6; LINE 3                                      1 times
BEGIN 1 6                                              1 times
BEGIN 1 1; LINE 14                                     1 times
BEGIN 1 1                                              1 times
BEGIN 1 0; LINE 24                                     1 times
BEGIN 1 0; LINE 18                                     1 times
ARRAY 2; CJMPNZ L637                                   1 times
ARRAY 2; CJMPNZ L280                                   1 times
ARRAY 2; CJMPNZ L197                                   1 times
```