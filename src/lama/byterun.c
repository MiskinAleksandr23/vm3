#include "disassembler.h"
#include <inttypes.h>
#include <string.h>

static LamaDisasmStatus read_byte(const LamaBytecode *bf, size_t *ip,
                                  uint8_t *value) {
  if (*ip >= bf->code_size)
    return LAMA_DISASM_TRUNCATED_INSTRUCTION;
  *value = bf->code[(*ip)++];
  return LAMA_DISASM_OK;
}

static LamaDisasmStatus read_int(const LamaBytecode *bf, size_t *ip,
                                 int32_t *value) {
  if (*ip > bf->code_size || bf->code_size - *ip < 4)
    return LAMA_DISASM_TRUNCATED_INSTRUCTION;
  const uint8_t *p = bf->code + *ip;
  uint32_t bits = (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
                  ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
  memcpy(value, &bits, sizeof(*value));
  *ip += 4;
  return LAMA_DISASM_OK;
}

static LamaDisasmStatus check_string(const LamaBytecode *bf, int32_t offset) {
  if (offset < 0 || (size_t)offset >= bf->strings_size)
    return LAMA_DISASM_STRING_OFFSET_OUT_OF_BOUNDS;
  if ((size_t)offset >= bf->terminated_strings_size)
    return LAMA_DISASM_UNTERMINATED_STRING;
  return LAMA_DISASM_OK;
}

LamaDisasmStatus lama_disassemble_instruction(FILE *output,
                                              const LamaBytecode *bf,
                                              size_t offset,
                                              LamaInstructionInfo *info,
                                              size_t *written) {
#define READ(call)                                                             \
  do {                                                                         \
    LamaDisasmStatus status = (call);                                          \
    if (status != LAMA_DISASM_OK)                                              \
      return status;                                                           \
  } while (0)
#define INT(value) READ(read_int(bf, &ip, &(value)))
#define BYTE(value) READ(read_byte(bf, &ip, &(value)))
#define STRING(value)                                                          \
  do {                                                                         \
    INT(value);                                                                \
    READ(check_string(bf, (value)));                                           \
  } while (0)
#define PRINT(...)                                                             \
  do {                                                                         \
    if (output != NULL) {                                                      \
      int n = fprintf(output, __VA_ARGS__);                                    \
      if (n < 0)                                                               \
        return LAMA_DISASM_WRITE_FAILED;                                       \
      printed += (size_t)n;                                                    \
    }                                                                          \
  } while (0)
#define FAIL return LAMA_DISASM_INVALID_OPCODE

  size_t ip = offset;
  size_t printed = 0;
  bool has_target = false;
  int32_t a, b;
  uint8_t x, scope;
  static const char *const ops[] = {"ADD", "SUB", "MUL", "DIV", "MOD",
                                    "LT",  "LE",  "GT",  "GE",  "EQ",
                                    "NE",  "AND", "OR"};
  static const char *const pats[] = {"STRCMP", "STRING",  "ARRAY",  "SEXP",
                                     "BOXED",  "UNBOXED", "CLOSURE"};
  static const char *const lds[] = {"LD", "LDA", "ST"};
  static const char *const scopes[] = {"GLOBAL", "LOCAL", "ARG", "CLOSURE"};

  *info = (LamaInstructionInfo){.target = -1, .continues = true};
  BYTE(x);
  uint8_t h = (x & 0xF0) >> 4;
  uint8_t l = x & 0x0F;

  switch (h) {
  case 15:
    if (l != 15)
      FAIL;
    PRINT("STOP");
    info->continues = false;
    break;

  case 0:
    if (l < 1 || l > sizeof(ops) / sizeof(ops[0]))
      FAIL;
    PRINT("%s", ops[l - 1]);
    break;

  case 1:
    switch (l) {
    case 0:
      INT(a);
      PRINT("CONST %" PRId32, a);
      break;

    case 1:
      STRING(a);
      PRINT("STRING %" PRId32, a);
      break;

    case 2:
      STRING(a);
      INT(b);
      PRINT("SEXP %" PRId32 " %" PRId32, a, b);
      break;

    case 3:
      PRINT("STI");
      break;

    case 4:
      PRINT("STA");
      break;

    case 5:
      INT(info->target);
      has_target = true;
      info->continues = false;
      PRINT("JMP L%" PRId32, info->target);
      break;

    case 6:
      PRINT("END");
      info->continues = false;
      break;

    case 7:
      PRINT("RET");
      info->continues = false;
      break;

    case 8:
      PRINT("DROP");
      break;

    case 9:
      PRINT("DUP");
      break;

    case 10:
      PRINT("SWAP");
      break;

    case 11:
      PRINT("ELEM");
      break;

    default:
      FAIL;
    }
    break;

  case 2:
  case 3:
  case 4:
    if (l > 3)
      FAIL;
    INT(a);
    PRINT("%s %s %" PRId32, lds[h - 2], scopes[l], a);
    break;

  case 5:
    switch (l) {
    case 0:
      INT(info->target);
      has_target = true;
      PRINT("CJMPZ L%" PRId32, info->target);
      break;

    case 1:
      INT(info->target);
      has_target = true;
      PRINT("CJMPNZ L%" PRId32, info->target);
      break;

    case 2:
      INT(a);
      INT(b);
      PRINT("BEGIN %" PRId32 " %" PRId32, a, b);
      break;

    case 3:
      INT(a);
      INT(b);
      PRINT("CBEGIN %" PRId32 " %" PRId32, a, b);
      break;

    case 4:
      INT(info->target);
      has_target = true;
      INT(b);
      if (b < 0)
        return LAMA_DISASM_NEGATIVE_CAPTURE_COUNT;
      if ((size_t)b > (bf->code_size - ip) / 5)
        return LAMA_DISASM_TRUNCATED_INSTRUCTION;
      PRINT("CLOSURE L%" PRId32 " %" PRId32, info->target, b);
      for (int32_t i = 0; i < b; i++) {
        BYTE(scope);
        if (scope > 3)
          return LAMA_DISASM_INVALID_CAPTURE_SCOPE;
        INT(a);
        PRINT(" %s %" PRId32, scopes[scope], a);
      }
      break;

    case 5:
      INT(a);
      info->returns_after = true;
      PRINT("CALLC %" PRId32, a);
      break;

    case 6:
      INT(info->target);
      has_target = true;
      INT(a);
      info->returns_after = true;
      PRINT("CALL L%" PRId32 " %" PRId32, info->target, a);
      break;

    case 7:
      STRING(a);
      INT(b);
      PRINT("TAG %" PRId32 " %" PRId32, a, b);
      break;

    case 8:
      INT(a);
      PRINT("ARRAY %" PRId32, a);
      break;

    case 9:
      INT(a);
      INT(b);
      PRINT("FAIL %" PRId32 " %" PRId32, a, b);
      info->continues = false;
      break;

    case 10:
      INT(a);
      PRINT("LINE %" PRId32, a);
      break;

    default:
      FAIL;
    }
    break;

  case 6:
    if (l >= sizeof(pats) / sizeof(pats[0]))
      FAIL;
    PRINT("PATT %s", pats[l]);
    break;

  case 7:
    switch (l) {
    case 0:
      PRINT("READ");
      break;

    case 1:
      PRINT("WRITE");
      break;

    case 2:
      PRINT("LENGTH");
      break;

    case 3:
      PRINT("TO_STRING");
      break;

    case 4:
      INT(a);
      PRINT("MAKE_ARRAY %" PRId32, a);
      break;

    default:
      FAIL;
    }
    break;

  default:
    FAIL;
  }

  if (has_target && (info->target < 0 || (size_t)info->target >= bf->code_size))
    return LAMA_DISASM_INCORRECT_OFFSET;
  info->size = ip - offset;
  if (written != NULL)
    *written = printed;
  return LAMA_DISASM_OK;

#undef READ
#undef INT
#undef BYTE
#undef STRING
#undef PRINT
#undef FAIL
}
