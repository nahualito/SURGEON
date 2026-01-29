/* src/runtime/hacl_stubs.c */
#include <stdlib.h>
#include <string.h>
#include <stddef.h>

/* Helper to allocate a dummy state buffer */
static void* stub_malloc(size_t size) {
    return calloc(1, size > 0 ? size : 1);
}

/* SHA2 256 Stubs */
void* python_hashlib_Hacl_Hash_SHA2_malloc_256(void) {
    return stub_malloc(256); 
}

void python_hashlib_Hacl_Hash_SHA2_free_256(void* state) {
    free(state);
}

void python_hashlib_Hacl_Hash_SHA2_update_256(void* state, const void* data, size_t len) {
    (void)state; (void)data; (void)len;
}

void python_hashlib_Hacl_Hash_SHA2_digest_256(void* state, void* output) {
    (void)state; // <--- ADDED THIS TO FIX THE ERROR
    memset(output, 0, 32); 
}

void python_hashlib_Hacl_Hash_SHA2_copy_256(void* src, void* dst) {
    if (src && dst) memcpy(dst, src, 256);
}

/* SHA2 512 Stubs */
void* python_hashlib_Hacl_Hash_SHA2_malloc_512(void) {
    return stub_malloc(512);
}

void python_hashlib_Hacl_Hash_SHA2_free_512(void* state) {
    free(state);
}

void python_hashlib_Hacl_Hash_SHA2_update_512(void* state, const void* data, size_t len) {
    (void)state; (void)data; (void)len;
}

void python_hashlib_Hacl_Hash_SHA2_digest_512(void* state, void* output) {
    (void)state; // <--- ADDED THIS TO FIX THE ERROR
    memset(output, 0, 64);
}

void python_hashlib_Hacl_Hash_SHA2_copy_512(void* src, void* dst) {
    if (src && dst) memcpy(dst, src, 512);
}

/* SHA2 224 (Uses 256 state) and 384 (Uses 512 state) */
void* python_hashlib_Hacl_Hash_SHA2_malloc_224(void) { return stub_malloc(256); }
void* python_hashlib_Hacl_Hash_SHA2_malloc_384(void) { return stub_malloc(512); }