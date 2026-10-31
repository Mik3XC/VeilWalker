// C ABI of rust/vw-tor (src/lib.rs). Every call blocks: call off the main thread.
// After a call returns -1, vw_last_error() on the same thread says why.
#ifndef VW_TOR_H
#define VW_TOR_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int32_t status;
    uint8_t *body;
    size_t body_len;
} VwHttpResponse;

/// Bootstraps Arti. 0 when connected (or already running), -1 on error or timeout.
int32_t vw_tor_start(const char *state_dir, const char *cache_dir, uint32_t timeout_ms);

/// Tears down Arti. Safe when not running.
void vw_tor_stop(void);

/// 1 if Arti is running, else 0.
int32_t vw_tor_is_running(void);

/// Why the last call on this thread failed. Free with vw_string_free.
char *vw_last_error(void);
void vw_string_free(char *s);

/// One HTTP/1.1 request to an http://<name>.onion URL over Tor.
/// headers: "Name: value" lines separated by '\n', or NULL. 0 on success (any HTTP status), -1 on error.
int32_t vw_http(const char *method, const char *url, const char *headers,
                const uint8_t *body, size_t body_len, uint32_t timeout_ms,
                VwHttpResponse *out);

/// Frees the body vw_http allocated in *r.
void vw_http_response_free(VwHttpResponse *r);

#ifdef __cplusplus
}
#endif

#endif
