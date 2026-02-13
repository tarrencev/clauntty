// Minimal Linux harness for the embedded Mosh client wrapper.
// Not used by the iOS app; intended for local validation.

#include "clauntty_mosh.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>

static void on_output(const uint8_t* bytes, size_t len, void* /*ctx*/) {
  // Write directly to stdout to let the terminal interpret the ANSI diffs.
  // Note: this will not look great in CI logs; it's for manual testing.
  fwrite(bytes, 1, len, stdout);
  fflush(stdout);
}

static void on_event(clauntty_mosh_event_t event, const char* message, void* /*ctx*/) {
  const char* name = "unknown";
  switch (event) {
    case CLAUNTTY_MOSH_EVENT_CONNECTED: name = "connected"; break;
    case CLAUNTTY_MOSH_EVENT_NETWORK_ERROR: name = "network_error"; break;
    case CLAUNTTY_MOSH_EVENT_CRYPTO_ERROR: name = "crypto_error"; break;
    case CLAUNTTY_MOSH_EVENT_EXIT: name = "exit"; break;
  }
  fprintf(stderr, "[mosh_test] event=%s msg=%s\n", name, message ? message : "(nil)");
}

static bool parse_mosh_connect_line(const std::string& line, std::string& port_out, std::string& key_out) {
  // Format: "MOSH CONNECT <port> <key>"
  const std::string prefix = "MOSH CONNECT ";
  if (line.rfind(prefix, 0) != 0) {
    return false;
  }
  const std::string rest = line.substr(prefix.size());
  const size_t sp = rest.find(' ');
  if (sp == std::string::npos) {
    return false;
  }
  port_out = rest.substr(0, sp);
  key_out = rest.substr(sp + 1);
  while (!key_out.empty() && (key_out.back() == '\n' || key_out.back() == '\r')) {
    key_out.pop_back();
  }
  return !port_out.empty() && !key_out.empty();
}

int main() {
  FILE* fp = popen("mosh-server new 2>/dev/null", "r");
  if (!fp) {
    perror("popen");
    return 1;
  }

  char buf[4096];
  std::string port;
  std::string key;
  while (fgets(buf, sizeof(buf), fp)) {
    std::string line(buf);
    if (parse_mosh_connect_line(line, port, key)) {
      break;
    }
  }

  const int status = pclose(fp);
  (void)status;

  if (port.empty() || key.empty()) {
    fprintf(stderr, "Failed to parse MOSH CONNECT line.\n");
    return 1;
  }

  fprintf(stderr, "Connecting to 127.0.0.1:%s with key %s\n", port.c_str(), key.c_str());

  char errbuf[256];
  errbuf[0] = 0;
  clauntty_mosh_client_t* client = clauntty_mosh_client_create(
    "127.0.0.1",
    port.c_str(),
    key.c_str(),
    /*cols=*/80,
    /*rows=*/24,
    &on_output,
    nullptr,
    &on_event,
    nullptr,
    errbuf,
    sizeof(errbuf)
  );
  if (!client) {
    fprintf(stderr, "create failed: %s\n", errbuf);
    return 1;
  }

  clauntty_mosh_client_start(client);

  // Give it a moment to connect, then send a command.
  std::this_thread::sleep_for(std::chrono::seconds(1));
  const char* cmd = "echo hello-from-clauntty-mosh && uname -a\r";
  clauntty_mosh_client_send_input(client, reinterpret_cast<const uint8_t*>(cmd), strlen(cmd));

  std::this_thread::sleep_for(std::chrono::seconds(2));
  clauntty_mosh_client_stop(client);
  clauntty_mosh_client_destroy(client);
  return 0;
}

