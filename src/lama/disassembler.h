#ifndef LAMA_DISASSEMBLER_H
#define LAMA_DISASSEMBLER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

typedef struct {
  const uint8_t *code;
  size_t code_size;
  size_t strings_size;
  size_t terminated_strings_size;
} LamaBytecode;

typedef struct {
  size_t size;
  int32_t target;
  bool continues;
  bool returns_after;
} LamaInstructionInfo;

typedef enum {
  LAMA_DISASM_OK,
  LAMA_DISASM_TRUNCATED_INSTRUCTION,
  LAMA_DISASM_INVALID_OPCODE,
  LAMA_DISASM_STRING_OFFSET_OUT_OF_BOUNDS,
  LAMA_DISASM_UNTERMINATED_STRING,
  LAMA_DISASM_NEGATIVE_CAPTURE_COUNT,
  LAMA_DISASM_INVALID_CAPTURE_SCOPE,
  LAMA_DISASM_INCORRECT_OFFSET,
  LAMA_DISASM_WRITE_FAILED
} LamaDisasmStatus;

LamaDisasmStatus lama_disassemble_instruction(FILE *output,
                                              const LamaBytecode *bytecode,
                                              size_t offset,
                                              LamaInstructionInfo *info,
                                              size_t *written);

#endif
