#ifndef NAMI_ENGINE_H
#define NAMI_ENGINE_H

/// Starts the Go torrent engine (once) and returns the port of its HTTP API
/// on 127.0.0.1, or -1 on failure.
extern int NamiStart(char *dataDir);

#endif
