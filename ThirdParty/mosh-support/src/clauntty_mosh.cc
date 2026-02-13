/*
 * Clauntty embedded Mosh client wrapper.
 *
 * This adapts upstream Mosh client logic (STMClient) into a library:
 * - no termios/raw mode
 * - no ncurses/terminfo (we provide a fixed xterm-like Display init)
 * - caller provides user input bytes and resize events
 * - caller receives ANSI diffs to apply to its terminal renderer
 *
 * NOTE: This is intended for iOS/macOS embedding, but we keep it portable
 * so we can run a simple Linux harness during development.
 */

#include "clauntty_mosh.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "src/crypto/crypto.h"
#include "src/network/networktransport.h"
#include "src/network/networktransport-impl.h"
#include "src/statesync/completeterminal.h"
#include "src/statesync/user.h"
#include "src/terminal/terminaldisplay.h"
#include "src/terminal/terminalframebuffer.h"
#include "src/util/timestamp.h"

namespace {

struct PendingEvent {
  enum Type { Byte, Resize } type;
  uint8_t byte;
  int cols;
  int rows;

  static PendingEvent makeByte(uint8_t b) {
    PendingEvent e{};
    e.type = Byte;
    e.byte = b;
    e.cols = -1;
    e.rows = -1;
    return e;
  }

  static PendingEvent makeResize(int c, int r) {
    PendingEvent e{};
    e.type = Resize;
    e.byte = 0;
    e.cols = c;
    e.rows = r;
    return e;
  }
};

static void set_err(char* errbuf, size_t errbuf_len, const std::string& msg) {
  if (!errbuf || errbuf_len == 0) {
    return;
  }
  // Best-effort truncation with NUL termination.
  const size_t n = (msg.size() < (errbuf_len - 1)) ? msg.size() : (errbuf_len - 1);
  memcpy(errbuf, msg.data(), n);
  errbuf[n] = 0;
}

static void default_event_cb(clauntty_mosh_event_t, const char*, void*) {}

} // namespace

struct clauntty_mosh_client {
  using NetworkType = Network::Transport<Network::UserStream, Terminal::Complete>;

  std::string ip;
  std::string port;
  std::string key;

  int cols = 0;
  int rows = 0;

  clauntty_mosh_output_cb output_cb = nullptr;
  void* output_ctx = nullptr;
  clauntty_mosh_event_cb event_cb = &default_event_cb;
  void* event_ctx = nullptr;

  std::unique_ptr<NetworkType> network;

  Terminal::Framebuffer local_framebuffer;
  Terminal::Display display;
  std::atomic<bool> output_enabled{true};
  std::atomic<bool> repaint_requested{true};
  bool connected_reported = false;

  std::atomic<bool> running{false};
  std::thread worker;

  std::mutex mu;
  std::deque<PendingEvent> pending;

  clauntty_mosh_client(const char* s_ip,
                       const char* s_port,
                       const char* s_key,
                       int s_cols,
                       int s_rows,
                       clauntty_mosh_output_cb s_out_cb,
                       void* s_out_ctx,
                       clauntty_mosh_event_cb s_evt_cb,
                       void* s_evt_ctx)
    : ip(s_ip ? s_ip : ""),
      port(s_port ? s_port : ""),
      key(s_key ? s_key : ""),
      cols(s_cols),
      rows(s_rows),
      output_cb(s_out_cb),
      output_ctx(s_out_ctx),
      event_cb(s_evt_cb ? s_evt_cb : &default_event_cb),
      event_ctx(s_evt_ctx),
      network(),
      local_framebuffer(static_cast<size_t>(s_cols), static_cast<size_t>(s_rows)),
      display(false)
  {
    // blank initial input stream and remote terminal state
    Network::UserStream blank;
    Terminal::Complete initial_remote(static_cast<size_t>(s_cols), static_cast<size_t>(s_rows));
    network.reset(new NetworkType(blank, initial_remote, key.c_str(), ip.c_str(), port.c_str()));
    network->set_send_delay(1); // minimal delay on outgoing keystrokes

    // Tell server the initial terminal size.
    network->get_current_state().push_back(Parser::Resize(s_cols, s_rows));
  }

  void drain_pending() {
    std::deque<PendingEvent> local;
    {
      std::lock_guard<std::mutex> lock(mu);
      local.swap(pending);
    }

    if (!network || network->shutdown_in_progress()) {
      return;
    }

    for (const auto& e : local) {
      if (e.type == PendingEvent::Byte) {
        network->get_current_state().push_back(Parser::UserByte(static_cast<char>(e.byte)));
      } else if (e.type == PendingEvent::Resize) {
        network->get_current_state().push_back(Parser::Resize(e.cols, e.rows));
        // Force a full redraw on local terminal after resize.
        repaint_requested.store(true, std::memory_order_relaxed);
      }
    }
  }

  void emit_frame() {
    if (!network) {
      return;
    }
    if (!output_enabled.load(std::memory_order_relaxed)) {
      return;
    }

    const Terminal::Framebuffer& remote_fb = network->get_latest_remote_state().state.get_fb();
    const bool incremental = !repaint_requested.load(std::memory_order_relaxed);
    const std::string diff = display.new_frame(incremental, local_framebuffer, remote_fb);
    if (!diff.empty() && output_cb) {
      output_cb(reinterpret_cast<const uint8_t*>(diff.data()), diff.size(), output_ctx);
    }
    repaint_requested.store(false, std::memory_order_relaxed);
    local_framebuffer = remote_fb;
  }

  bool still_connecting() const {
    return network && (network->get_remote_state_num() == 0);
  }

  void maybe_report_connected() {
    if (connected_reported) {
      return;
    }
    if (network && network->get_remote_state_num() != 0) {
      connected_reported = true;
      event_cb(CLAUNTTY_MOSH_EVENT_CONNECTED, nullptr, event_ctx);
    }
  }

  void loop() {
    // Mirror STMClient behavior: disable core dumps for safety.
    Crypto::disable_dumping_core();

    while (running.load(std::memory_order_relaxed)) {
      try {
        freeze_timestamp();

        drain_pending();
        emit_frame();
        maybe_report_connected();

        int wait_time_ms = network ? network->wait_time() : 250;
        if (still_connecting()) {
          wait_time_ms = std::min(wait_time_ms, 250);
        }
        if (wait_time_ms < 0) {
          wait_time_ms = 250;
        }

        // select() on network fds
        bool ready = false;
        if (network) {
          const std::vector<int> fds = network->fds();
          fd_set readfds;
          FD_ZERO(&readfds);
          int maxfd = -1;
          for (int fd : fds) {
            if (fd >= 0) {
              FD_SET(fd, &readfds);
              if (fd > maxfd) {
                maxfd = fd;
              }
            }
          }

          struct timeval tv;
          tv.tv_sec = wait_time_ms / 1000;
          tv.tv_usec = (wait_time_ms % 1000) * 1000;

          int ret = 0;
          if (maxfd >= 0) {
            ret = ::select(maxfd + 1, &readfds, nullptr, nullptr, &tv);
          } else {
            // No fds? Just sleep for the timeout.
            ret = 0;
            std::this_thread::sleep_for(std::chrono::milliseconds(wait_time_ms));
          }

          if (ret > 0) {
            for (int fd : fds) {
              if (fd >= 0 && FD_ISSET(fd, &readfds)) {
                ready = true;
                break;
              }
            }
          }
        }

        freeze_timestamp();

        if (ready && network) {
          network->recv();
        }

        if (network) {
          network->tick();
          std::string& send_error = network->get_send_error();
          if (!send_error.empty()) {
            event_cb(CLAUNTTY_MOSH_EVENT_NETWORK_ERROR, send_error.c_str(), event_ctx);
            send_error.clear();
          }
        }
      } catch (const Network::NetworkException& e) {
        event_cb(CLAUNTTY_MOSH_EVENT_NETWORK_ERROR, e.what(), event_ctx);
        // Mimic upstream: short sleep on network exceptions.
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
        freeze_timestamp();
      } catch (const Crypto::CryptoException& e) {
        event_cb(CLAUNTTY_MOSH_EVENT_CRYPTO_ERROR, e.what(), event_ctx);
        if (e.fatal) {
          break;
        }
      } catch (const std::exception& e) {
        event_cb(CLAUNTTY_MOSH_EVENT_EXIT, e.what(), event_ctx);
        break;
      }
    }

    event_cb(CLAUNTTY_MOSH_EVENT_EXIT, nullptr, event_ctx);
  }
};

clauntty_mosh_client_t* clauntty_mosh_client_create(const char* ip,
                                                    const char* port,
                                                    const char* key,
                                                    int cols,
                                                    int rows,
                                                    clauntty_mosh_output_cb output_cb,
                                                    void* output_ctx,
                                                    clauntty_mosh_event_cb event_cb,
                                                    void* event_ctx,
                                                    char* errbuf,
                                                    size_t errbuf_len)
{
  try {
    if (!ip || !port || !key) {
      set_err(errbuf, errbuf_len, "Missing ip/port/key");
      return nullptr;
    }
    if (cols <= 0 || rows <= 0) {
      set_err(errbuf, errbuf_len, "Invalid cols/rows");
      return nullptr;
    }
    if (!output_cb) {
      set_err(errbuf, errbuf_len, "Missing output callback");
      return nullptr;
    }
    return new clauntty_mosh_client(ip, port, key, cols, rows, output_cb, output_ctx, event_cb, event_ctx);
  } catch (const std::exception& e) {
    set_err(errbuf, errbuf_len, e.what());
    return nullptr;
  }
}

void clauntty_mosh_client_start(clauntty_mosh_client_t* client) {
  if (!client) {
    return;
  }
  if (client->running.exchange(true)) {
    return;
  }
  client->worker = std::thread([client]() { client->loop(); });
}

void clauntty_mosh_client_stop(clauntty_mosh_client_t* client) {
  if (!client) {
    return;
  }
  const bool was_running = client->running.exchange(false);
  if (!was_running) {
    return;
  }
  if (client->worker.joinable()) {
    client->worker.join();
  }
}

void clauntty_mosh_client_destroy(clauntty_mosh_client_t* client) {
  if (!client) {
    return;
  }
  clauntty_mosh_client_stop(client);
  delete client;
}

void clauntty_mosh_client_set_output_enabled(clauntty_mosh_client_t* client, int enabled) {
  if (!client) {
    return;
  }
  const bool e = enabled != 0;
  client->output_enabled.store(e, std::memory_order_relaxed);
  if (e) {
    // Local framebuffer may be stale; force a full repaint on next frame.
    client->repaint_requested.store(true, std::memory_order_relaxed);
  }
}

void clauntty_mosh_client_send_input(clauntty_mosh_client_t* client, const uint8_t* bytes, size_t len) {
  if (!client || !bytes || len == 0) {
    return;
  }
  std::lock_guard<std::mutex> lock(client->mu);
  for (size_t i = 0; i < len; i++) {
    client->pending.push_back(PendingEvent::makeByte(bytes[i]));
  }
}

void clauntty_mosh_client_send_resize(clauntty_mosh_client_t* client, int cols, int rows) {
  if (!client || cols <= 0 || rows <= 0) {
    return;
  }
  std::lock_guard<std::mutex> lock(client->mu);
  client->pending.push_back(PendingEvent::makeResize(cols, rows));
}
