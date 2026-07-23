// argon2_bridge.c — Thin C bridge between V and libargon2
#include "argon2.h"
#include "argon2_bridge.h"
#include <string.h>

int photon_argon2id_hash(const char *password, const char *salt,
                         uint32_t t_cost, uint32_t m_cost, uint32_t parallelism,
                         char *encoded, size_t encoded_len) {
    if (!password || !salt || !encoded || encoded_len == 0) {
        return -1;
    }
    return argon2id_hash_encoded(
        t_cost, m_cost, parallelism,
        password, strlen(password),
        salt, strlen(salt),
        32,  // hash length in bytes
        encoded, encoded_len
    );
}

int photon_argon2id_verify(const char *encoded, const char *password) {
    if (!encoded || !password) {
        return -1;
    }
    return argon2id_verify(encoded, password, strlen(password));
}
