package io.github.leonfox28.tidemeld.core.accounts

import androidx.core.util.AtomicFile
import io.github.leonfox28.tidemeld.core.session.SessionCipher
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

interface AccountStorage {
    suspend fun load(): List<SocialAccount>

    suspend fun save(accounts: List<SocialAccount>)
}

/** A separate encrypted vault leaves the legacy installation's session intact during migration. */
class EncryptedAccountStorage(file: File, private val cipher: SessionCipher) : AccountStorage {
    private val atomic = AtomicFile(file)

    override suspend fun load(): List<SocialAccount> =
        withContext(Dispatchers.IO) {
            try {
                val data = cipher.decrypt(atomic.readFully()).decodeToString()
                Json.parseToJsonElement(data).jsonArray.mapNotNull {
                    runCatching { SocialAccount.fromJson(it.jsonObject) }.getOrNull()
                }
            } catch (_: java.io.FileNotFoundException) {
                emptyList()
            }
        }

    override suspend fun save(accounts: List<SocialAccount>) =
        withContext(Dispatchers.IO) {
            val data =
                cipher.encrypt(
                    JsonArray(accounts.map { it.toJson() }).toString().encodeToByteArray()
                )
            val stream = atomic.startWrite()
            try {
                stream.write(data)
                atomic.finishWrite(stream)
            } catch (error: Exception) {
                atomic.failWrite(stream)
                throw error
            }
        }
}

class MemoryAccountStorage : AccountStorage {
    private var saved = emptyList<SocialAccount>()

    override suspend fun load() = saved

    override suspend fun save(accounts: List<SocialAccount>) {
        saved = accounts
    }
}
