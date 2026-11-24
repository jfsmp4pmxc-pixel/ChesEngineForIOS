#ifndef STOCKFISH_BRIDGE_H
#define STOCKFISH_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Starts Stockfish on a background thread (once per process).
/// `argv0` is a path whose *directory* contains the nn-*.nnue network files.
/// Returns 0 when started, 1 if it was already running, <0 on failure.
int sf_start(const char *argv0);

/// Sends one UCI command line (without trailing newline) to the engine.
void sf_send(const char *command);

/// Reads one line printed by the engine into `buffer` (NUL terminated).
/// Returns the line length, -2 when `timeout_ms` elapsed with nothing to read,
/// or -1 when the engine has exited.
int sf_read(char *buffer, int capacity, int timeout_ms);

#ifdef __cplusplus
}
#endif

#endif
