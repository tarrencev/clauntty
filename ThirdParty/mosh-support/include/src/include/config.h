#pragma once

/*
 * Minimal config.h for building upstream Mosh as an embeddable library (iOS/macOS/Linux).
 *
 * Upstream Mosh normally generates this file via autotools. For Clauntty we provide
 * a conservative, cross-platform subset to avoid running autotools in Xcode builds.
 *
 * If you update the upstream Mosh revision and see new missing macros at build time,
 * extend this file intentionally rather than reintroducing autotools.
 */

/* AES backend selection for OCB (ocb_internal.cc). */
#if defined(__APPLE__)
#define USE_APPLE_COMMON_CRYPTO_AES 1
#define USE_OPENSSL_AES 0
#else
#define USE_APPLE_COMMON_CRYPTO_AES 0
#define USE_OPENSSL_AES 1
#endif
#define USE_NETTLE_AES 0

/* libc / headers */
#define HAVE_POSIX_MEMALIGN 1
#define HAVE_STRINGS_H 1

/* Endianness helpers (ocb_internal.cc) */
#if defined(__linux__)
#define HAVE_ENDIAN_H 1
#define HAVE_SYS_ENDIAN_H 0
#elif defined(__APPLE__)
#define HAVE_ENDIAN_H 0
#define HAVE_SYS_ENDIAN_H 1
#else
#define HAVE_ENDIAN_H 0
#define HAVE_SYS_ENDIAN_H 0
#endif

/* Compiler builtins */
#define HAVE_DECL___BUILTIN_BSWAP64 1
#define HAVE_DECL___BUILTIN_CTZ 1

/* Fallbacks (may or may not exist; only used if the builtin is missing) */
#define HAVE_DECL_BSWAP64 0
#define HAVE_DECL_FFS 1

/* Network headers / options */
#define HAVE_SYS_UIO_H 1

/* These are best-effort; if a platform rejects the sockopts they are handled. */
#define HAVE_IP_MTU_DISCOVER 1
#define HAVE_IP_RECVTOS 1

/* Time sources */
#define HAVE_CLOCK_GETTIME 1
#if defined(__APPLE__)
#define HAVE_MACH_ABSOLUTE_TIME 1
#else
#define HAVE_MACH_ABSOLUTE_TIME 0
#endif
#define HAVE_GETTIMEOFDAY 1

/* select/pselect */
#define HAVE_PSELECT 1
#define FD_ISSET_IS_CONST 0

/* Optional headers */
#define HAVE_TERMIO_H 0

