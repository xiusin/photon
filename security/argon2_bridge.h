// argon2_bridge.h — Thin bridge between V and libargon2
// Links against system libargon2 for argon2id password hashing.
#ifndef PHOTON_ARGON2_BRIDGE_H
#define PHOTON_ARGON2_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

// photon_argon2id_hash — generate an encoded argon2id hash string.
// Returns 0 (ARGON2_OK) on success, non-zero on error.
// encoded buffer must be at least 128 bytes for default parameters.
int photon_argon2id_hash(const char *password, const char *salt,
                         uint32_t t_cost, uint32_t m_cost, uint32_t parallelism,
                         char *encoded, size_t encoded_len);

// photon_argon2id_verify — verify a password against an encoded argon2id hash.
// Returns 0 (ARGON2_OK) on match, non-zero on mismatch or error.
int photon_argon2id_verify(const char *encoded, const char *password);

#endif // PHOTON_ARGON2_BRIDGE_H
