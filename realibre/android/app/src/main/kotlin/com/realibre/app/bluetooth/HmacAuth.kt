package com.realibre.app.bluetooth

import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Two-pass HMAC-SHA256 handshake that must complete before any Cmd 0x03/0x04
 * is accepted by the buds:
 *
 *  1. Client sends Cmd 0x01 with 16 cryptographically random bytes.
 *  2. Buds reply Cmd 0x01: [status(1)] [HMAC(key, client_random)(32)] [earbud_random(16)].
 *  3. Client verifies the signature locally.
 *  4. Client sends Cmd 0x02: [0x0A] + HMAC(key, earbud_random).
 *  5. Buds confirm with Cmd 0x02 — session unlocked.
 */
object HmacAuth {

    class AuthException(message: String) : Exception(message)

    /** Fresh 16-byte cryptographically random client challenge. */
    fun newClientChallenge(random: SecureRandom = SecureRandom()): ByteArray {
        val bytes = ByteArray(ProtocolConstants.CHALLENGE_SIZE)
        random.nextBytes(bytes)
        return bytes
    }

    /** HMAC-SHA256 over [message] keyed with the shared secret. */
    fun sign(message: ByteArray, key: ByteArray = ProtocolConstants.HMAC_KEY): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(message)
    }

    /** Constant-time equality to avoid timing side channels. */
    fun verify(expected: ByteArray, actual: ByteArray): Boolean =
        expected.size == actual.size && MessageDigest.isEqual(expected, actual)

    /**
     * Parse and verify the earbud's Cmd 0x01 reply.
     * Layout: [0]=status, [1..32]=HMAC(key, client_random), [33..48]=earbud_random.
     * Returns the earbud's 16-byte challenge on success.
     */
    fun verifyChallengeReply(replyPayload: ByteArray, clientRandom: ByteArray): ByteArray {
        val minLen = 1 + ProtocolConstants.HMAC_SIZE + ProtocolConstants.CHALLENGE_SIZE
        if (replyPayload.size < minLen) {
            throw AuthException("auth reply too short: ${replyPayload.size} bytes, expected >= $minLen")
        }
        val status = replyPayload[ProtocolConstants.AUTH_STATUS_OFFSET].toInt() and 0xFF
        if (status != 0x00) throw AuthException("earbud rejected challenge (status=0x%02X".format(status) + ")")

        val sig = replyPayload.copyOfRange(
            ProtocolConstants.AUTH_SIG_OFFSET,
            ProtocolConstants.AUTH_SIG_OFFSET + ProtocolConstants.HMAC_SIZE,
        )
        val expectedSig = sign(clientRandom)
        if (!verify(expectedSig, sig)) throw AuthException("earbud signature mismatch")

        return replyPayload.copyOfRange(
            ProtocolConstants.AUTH_EARBUD_RANDOM_OFFSET,
            ProtocolConstants.AUTH_EARBUD_RANDOM_OFFSET + ProtocolConstants.CHALLENGE_SIZE,
        )
    }

    /** Build the Cmd 0x02 payload: [0x0A] + HMAC(key, earbud_random). */
    fun buildResponsePayload(earbudRandom: ByteArray): ByteArray {
        require(earbudRandom.size == ProtocolConstants.CHALLENGE_SIZE) {
            "earbud challenge must be ${ProtocolConstants.CHALLENGE_SIZE} bytes"
        }
        val out = ByteArray(1 + ProtocolConstants.HMAC_SIZE)
        out[0] = 0x0A
        sign(earbudRandom).copyInto(out, 1)
        return out
    }
}
