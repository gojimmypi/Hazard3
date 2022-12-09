/* user_settings.h
 *
 * Copyright (C) 2006-2022 wolfSSL Inc.
 *
 * This file is part of wolfSSL.
 *
 * wolfSSL is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * wolfSSL is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1335, USA
 */

/* Example Settings for SiFive HiFive1 */

#ifndef WOLFSSL_USER_SETTINGS_H
#define WOLFSSL_USER_SETTINGS_H

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------- */
/* Hazard3 */
/* ------------------------------------------------------------------------- */
#undef  WOLFSSL_HAZARD3
#define WOLFSSL_HAZARD3

#define NO_MAIN_FUNCTION

/* ------------------------------------------------------------------------- */
/* Platform */
/* ------------------------------------------------------------------------- */

#undef  WOLFSSL_GENERAL_ALIGNMENT
#define WOLFSSL_GENERAL_ALIGNMENT   4

#undef  SINGLE_THREADED
#define SINGLE_THREADED

#undef  WOLFSSL_SMALL_STACK
#define WOLFSSL_SMALL_STACK

#undef  WOLFSSL_USER_IO
#define WOLFSSL_USER_IO


/* ------------------------------------------------------------------------- */
/* Math Configuration */
/* ------------------------------------------------------------------------- */
#undef  SIZEOF_LONG_LONG
#define SIZEOF_LONG_LONG 8

#undef USE_FAST_MATH

#undef  TFM_TIMING_RESISTANT
#define TFM_TIMING_RESISTANT

/* ------------------------------------------------------------------------- */
/* Asymmetric */
/* ------------------------------------------------------------------------- */
/* RSA */
/* Not enabled due to memory constraints on HiFive1 */
#undef NO_RSA
#define NO_RSA

#undef HAVE_ECC
#if 1
    #define HAVE_ECC

    /* Manually define enabled curves */
    #undef  ECC_USER_CURVES
    #define ECC_USER_CURVES

    #ifdef ECC_USER_CURVES
        /* Manual Curve Selection, FP_MAX_BITS must be adjusted accordingly */
        // #define HAVE_ECC192
        // #define HAVE_ECC224
        // #define HAVE_ECC384
        // #define HAVE_ECC521
    #endif

    /* Fixed point cache (speeds repeated operations against same private key) */
    #undef  FP_ECC
    //#define FP_ECC
    #ifdef FP_ECC
        /* Bits / Entries */
        #undef  FP_ENTRIES
        #define FP_ENTRIES  2
        #undef  FP_LUT
        #define FP_LUT      4
    #endif

    /* Optional ECC calculation method */
    /* Note: doubles heap usage, but slightly faster */
    #undef  ECC_SHAMIR
    //#define ECC_SHAMIR

    /* Reduces heap usage, but slower */
    #undef  ECC_TIMING_RESISTANT
    #define ECC_TIMING_RESISTANT

    /* Enable cofactor support */
    #undef  HAVE_ECC_CDH
    //#define HAVE_ECC_CDH

    /* Validate import */
    #undef  WOLFSSL_VALIDATE_ECC_IMPORT
    //#define WOLFSSL_VALIDATE_ECC_IMPORT

    /* Compressed Key Support */
    #undef  HAVE_COMP_KEY
    //#define HAVE_COMP_KEY

    /* Use alternate ECC size for ECC math */
    #ifdef USE_FAST_MATH
        #ifdef NO_RSA
            /* Custom fastmath size if not using RSA */
            /* MAX = ROUND32(ECC BITS 256) + SIZE_OF_MP_DIGIT(32) */
            #undef  FP_MAX_BITS
            #define FP_MAX_BITS     (256 + 32)
        #else
            #undef  ALT_ECC_SIZE
            /* Disable alternate ECC size, since it uses HEAP allocations.
                Heap is limited resource  */
            #define ALT_ECC_SIZE
        #endif
    #endif
#endif

/* DH */
#undef  NO_DH

#define NO_DH

/* ------------------------------------------------------------------------- */
/* Disable Features */
/* ------------------------------------------------------------------------- */
#undef  NO_WOLFSSL_SERVER
#define NO_WOLFSSL_SERVER

#undef  NO_WOLFSSL_CLIENT
#define NO_WOLFSSL_CLIENT

#undef  NO_CRYPT_TEST
#define NO_CRYPT_TEST

#undef  NO_CRYPT_BENCHMARK
#define NO_CRYPT_BENCHMARK

#undef  WOLFCRYPT_ONLY
#define WOLFCRYPT_ONLY

/* In-lining of misc.c functions */
/* If defined, must include wolfcrypt/src/misc.c in build */
/* Slower, but about 1k smaller */
#undef  NO_INLINE
//#define NO_INLINE

#undef  NO_FILESYSTEM
#define NO_FILESYSTEM

#undef  NO_WRITEV
#define NO_WRITEV

#undef  NO_MAIN_DRIVER
#define NO_MAIN_DRIVER

//#undef  NO_DEV_RANDOM
//#define NO_DEV_RANDOM

#undef  NO_DSA
#define NO_DSA

#undef  NO_RC4
#define NO_RC4

#undef  NO_OLD_TLS
#define NO_OLD_TLS

#undef  NO_PSK
#define NO_PSK

#undef  NO_MD4
#define NO_MD4

#undef  NO_PWDBASED
#define NO_PWDBASED

#undef  NO_CODING
#define NO_CODING

#undef  NO_ASN_TIME
#define NO_ASN_TIME

#undef  NO_CERTS
//#define NO_CERTS

#undef  NO_SIG_WRAPPER
#define NO_SIG_WRAPPER

#define WOLFSSL_SP_NO_256
#define WOLFSSL_SP_NO_3072
#define SMALL_SESSION_CACHE
#define NO_AES_CBC
#define NO_DEV_URANDOM
#define WOLFSSL_NO_SIGALG
#define NO_RESUME_SUITE_CHECK
#define WOLFSSL_AEAD_ONLY

#define GCM_SMALL
#define USE_SLOW_SHA
#define USE_SLOW_SHA256
#define USE_SLOW_SHA512
#define WOLFSSL_SHA3_SMALL
#define ECC_USER_CURVES
#define WC_DISABLE_RADIX_ZERO_PAD
#define WOLFSSL_SP_SMALL

/* ??
#define LEANPSK
#define LEANTLS
 */


/* causes unrecognized opcode errors
#define WOLFSSL_SP_MATH_ALL
#define WOLFSSL_SP_RISCV32
*/

#ifdef __cplusplus
}
#endif

#endif /* WOLFSSL_USER_SETTINGS_H */
