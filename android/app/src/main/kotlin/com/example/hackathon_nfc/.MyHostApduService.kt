package com.example.hackathon_nfc

import android.content.Context
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Log
import java.nio.charset.StandardCharsets

class MyHostApduService : HostApduService() {
    companion object {
        private val STATUS_OK = byteArrayOf(0x90.toByte(), 0x00)
        private val STATUS_UNKNOWN = byteArrayOf(0x6F.toByte(), 0x00)
        
        // The exact SELECT APDU that the receiver sends
        private val SELECT_AID = byteArrayOf(
            0x00.toByte(), 0xA4.toByte(), 0x04.toByte(), 0x00.toByte(), 0x07.toByte(), // CLA INS P1 P2 Lc
            0xF0.toByte(), 0x01.toByte(), 0x02.toByte(), 0x03.toByte(), 0x04.toByte(), 0x05.toByte(), 0x06.toByte() // AID
        )
    }

    override fun processCommandApdu(apdu: ByteArray?, extras: Bundle?): ByteArray {
        Log.d("HCE", "APDU received: ${apdu?.joinToString("") { "%02x".format(it) }}")
        
        if (apdu != null && apdu.contentEquals(SELECT_AID)) {
            Log.d("HCE", "SELECT matched – preparing alias response")
            
            // Read the Cliq alias from SharedPreferences
            val prefs = applicationContext
                .getSharedPreferences("HCE_PREF", Context.MODE_PRIVATE)
            val alias = prefs.getString("payload", "default-alias") ?: "default-alias"
            
            // Convert alias to UTF-8 bytes
            val aliasBytes = alias.toByteArray(StandardCharsets.UTF_8)
            Log.d("HCE", "Alias: $alias, bytes length: ${aliasBytes.size}")
            
            // Build the response that matches what the receiver expects:
            // [0x03][length][alias_bytes] + STATUS_OK
            val response = ByteArray(2 + aliasBytes.size + 2)
            response[0] = 0x03.toByte() // TLV tag
            response[1] = aliasBytes.size.toByte() // length
            System.arraycopy(aliasBytes, 0, response, 2, aliasBytes.size)
            response[response.size - 2] = 0x90.toByte() // SW1
            response[response.size - 1] = 0x00.toByte() // SW2
            
            Log.d("HCE", "Responding with ${response.size} bytes: ${response.joinToString("") { "%02x".format(it) }}")
            return response
        }
        
        Log.d("HCE", "Unknown APDU - expected SELECT AID")
        return STATUS_UNKNOWN
    }

    override fun onDeactivated(reason: Int) {
        Log.d("HCE", "HCE Deactivated: reason=$reason")
    }
}