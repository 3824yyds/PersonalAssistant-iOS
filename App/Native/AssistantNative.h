#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
char * pa_generate(const char *path, const char *prompt, int max_tokens, uint64_t request_id);
void pa_cancel(uint64_t request_id);
void pa_release(void);
void pa_free(char *value);
const char *pa_error(void);
#ifdef __cplusplus
}
#endif
