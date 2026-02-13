#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct clauntty_mosh_client clauntty_mosh_client_t;

typedef void (*clauntty_mosh_output_cb)(const uint8_t* bytes, size_t len, void* ctx);

typedef enum clauntty_mosh_event {
  CLAUNTTY_MOSH_EVENT_CONNECTED = 1,
  CLAUNTTY_MOSH_EVENT_NETWORK_ERROR = 2,
  CLAUNTTY_MOSH_EVENT_CRYPTO_ERROR = 3,
  CLAUNTTY_MOSH_EVENT_EXIT = 4,
} clauntty_mosh_event_t;

typedef void (*clauntty_mosh_event_cb)(clauntty_mosh_event_t event, const char* message, void* ctx);

/*
 * Create a Mosh client session object.
 *
 * ip: numeric IP string (mosh prefers numeric to avoid DNS changes; caller resolves if needed)
 * port: UDP port returned by `mosh-server new`
 * key: session key returned by `mosh-server new` (22-char base64 without ==)
 *
 * cols/rows: initial terminal size
 *
 * output_cb is called with ANSI/ECMA-48 escape sequences to apply to the terminal.
 * event_cb is called with notable lifecycle/errors.
 *
 * Returns NULL on error. If errbuf is provided, it will be filled with a human-readable message.
 */
clauntty_mosh_client_t* clauntty_mosh_client_create(
  const char* ip,
  const char* port,
  const char* key,
  int cols,
  int rows,
  clauntty_mosh_output_cb output_cb,
  void* output_ctx,
  clauntty_mosh_event_cb event_cb,
  void* event_ctx,
  char* errbuf,
  size_t errbuf_len
);

void clauntty_mosh_client_start(clauntty_mosh_client_t* client);
void clauntty_mosh_client_stop(clauntty_mosh_client_t* client);
void clauntty_mosh_client_destroy(clauntty_mosh_client_t* client);

// Enable/disable emitting terminal output frames (ANSI diffs) to the output callback.
// When re-enabled, the client will force a repaint on the next frame.
void clauntty_mosh_client_set_output_enabled(clauntty_mosh_client_t* client, int enabled);

void clauntty_mosh_client_send_input(clauntty_mosh_client_t* client, const uint8_t* bytes, size_t len);
void clauntty_mosh_client_send_resize(clauntty_mosh_client_t* client, int cols, int rows);

#ifdef __cplusplus
} // extern "C"
#endif
