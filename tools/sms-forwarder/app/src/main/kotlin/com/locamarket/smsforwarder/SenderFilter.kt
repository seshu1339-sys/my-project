package com.locamarket.smsforwarder

/** The one check made on every SMS: is it from the bank? Only the sender is looked at; anything else is dropped without opening its text. */
object SenderFilter {
    fun parse(list: String): List<String> = list.split(',').map { it.trim().uppercase() }.filter { it.isNotEmpty() && !it.startsWith("XX") }

    /** Operators add a prefix such as AD- or VM-, so the bank's id only has to be inside the sender. */
    fun allowed(sender: String?, senders: List<String>): Boolean {
        val from = sender?.trim()?.uppercase() ?: return false
        return from.isNotEmpty() && senders.any { from.contains(it) }
    }
}
