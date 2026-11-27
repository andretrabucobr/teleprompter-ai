package __PACKAGE__

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.InetAddress
import java.util.concurrent.Executors
import javax.jmdns.JmDNS
import javax.jmdns.ServiceInfo
import org.vosk.Model
import org.vosk.Recognizer
import org.json.JSONObject
import java.io.File
import java.util.zip.ZipInputStream

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val voiceExecutor = Executors.newSingleThreadExecutor()
    private var voiceModel: Model? = null
    private var voiceRecognizer: Recognizer? = null
    private var dns: JmDNS? = null
    private var multicast: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flowtext/local_voice")
            .setMethodCallHandler { call, result ->
                if (call.method == "available") {
                    val available = try {
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            SpeechRecognizer.isOnDeviceRecognitionAvailable(applicationContext)
                    } catch (_: Exception) {
                        false
                    }
                    result.success(available)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flowtext/vosk")
            .setMethodCallHandler { call, result ->
                voiceExecutor.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "start" -> {
                                closeVoice()
                                val model = Model(prepareVoiceModel().absolutePath)
                                voiceModel = model
                                voiceRecognizer = Recognizer(model, 16000.0f)
                                null
                            }
                            "pcm" -> {
                                val pcm = call.arguments as? ByteArray ?: error("PCM inválido")
                                val recognizer = voiceRecognizer ?: error("Vosk inativo")
                                val isFinal = recognizer.acceptWaveForm(pcm, pcm.size)
                                val obj = JSONObject(if (isFinal) recognizer.result else recognizer.partialResult)
                                mapOf("text" to obj.optString(if (isFinal) "text" else "partial"), "final" to isFinal)
                            }
                            "reset" -> { voiceRecognizer?.reset(); null }
                            "stop" -> { closeVoice(); null }
                            else -> error("Método Vosk desconhecido")
                        }
                        runOnUiThread { result.success(value) }
                    } catch (e: Throwable) {
                        if (call.method == "start") closeVoice()
                        runOnUiThread { result.error("VOSK", e.message ?: e.javaClass.simpleName, null) }
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flowtext/lan_name")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val ip = call.argument<String>("ip")
                        val port = call.argument<Int>("port")
                        if (ip == null || port == null) {
                            result.error("INVALID", "Endereço local inválido", null)
                        } else {
                            executor.execute {
                                try {
                                    closeDns()
                                    val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                                    multicast = wifi.createMulticastLock("FlowText").apply {
                                        setReferenceCounted(false)
                                        acquire()
                                    }
                                    val address = InetAddress.getByAddress("flowtext", InetAddress.getByName(ip).address)
                                    val responder = JmDNS.create(address, "flowtext")
                                    dns = responder
                                    responder.registerService(ServiceInfo.create("_http._tcp.local.", "FlowText", port, "path=/"))
                                    val name = responder.hostName
                                    runOnUiThread { result.success(name) }
                                } catch (e: Exception) {
                                    closeDns()
                                    runOnUiThread { result.error("MDNS", e.message, null) }
                                }
                            }
                        }
                    }
                    "stop" -> executor.execute {
                        closeDns()
                        runOnUiThread { result.success(null) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun prepareVoiceModel(): File {
        val root = File(filesDir, "flowtext-vosk-pt-0.3")
        val marker = File(root, ".ready")
        val model = File(root, "vosk-model-small-pt-0.3")
        if (marker.isFile && model.isDirectory) return model
        root.deleteRecursively()
        root.mkdirs()
        val base = root.canonicalPath + File.separator
        assets.open("flowtext-vosk.zip").use { input ->
            ZipInputStream(input).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val target = File(root, entry.name)
                    require(target.canonicalPath.startsWith(base)) { "Caminho inválido no modelo" }
                    if (entry.isDirectory) target.mkdirs()
                    else {
                        target.parentFile?.mkdirs()
                        target.outputStream().use { out -> zip.copyTo(out) }
                    }
                    zip.closeEntry()
                }
            }
        }
        check(model.isDirectory) { "Modelo Vosk ausente" }
        marker.writeText("0.3")
        return model
    }

    private fun closeVoice() {
        try { voiceRecognizer?.close() } catch (_: Throwable) {}
        voiceRecognizer = null
        try { voiceModel?.close() } catch (_: Throwable) {}
        voiceModel = null
    }

    private fun closeDns() {
        try { dns?.close() } catch (_: Exception) {}
        dns = null
        try { if (multicast?.isHeld == true) multicast?.release() } catch (_: Exception) {}
        multicast = null
    }

    override fun onDestroy() {
        executor.execute { closeDns() }
        executor.shutdown()
        voiceExecutor.execute { closeVoice() }
        voiceExecutor.shutdown()
        super.onDestroy()
    }
}
