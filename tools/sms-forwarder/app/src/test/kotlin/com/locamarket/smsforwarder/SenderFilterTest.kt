package com.locamarket.smsforwarder

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SenderFilterTest {
    private val bank = SenderFilter.parse("HDFCBK, hdfcbn")

    @Test
    fun theBankIsRecognisedWithAnyOperatorPrefix() {
        assertTrue(SenderFilter.allowed("AD-HDFCBK", bank))
        assertTrue(SenderFilter.allowed("vm-hdfcbn-s", bank))
    }

    @Test
    fun everyoneElseIsDropped() {
        assertFalse(SenderFilter.allowed("AD-AMAZON", bank))
        assertFalse(SenderFilter.allowed("+919876543210", bank))
        assertFalse(SenderFilter.allowed("", bank))
        assertFalse(SenderFilter.allowed(null, bank))
    }

    @Test
    fun placeholdersAndEmptySettingsLetNothingThrough() {
        assertEquals(emptyList<String>(), SenderFilter.parse("XX-SENDER-ID"))
        assertFalse(SenderFilter.allowed("AD-HDFCBK", SenderFilter.parse("")))
    }
}
