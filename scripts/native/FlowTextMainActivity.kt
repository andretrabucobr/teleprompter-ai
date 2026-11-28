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

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
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

    private fun closeDns() {
        try { dns?.close() } catch (_: Exception) {}
        dns = null
        try { if (multicast?.isHeld == true) multicast?.release() } catch (_: Exception) {}
        multicast = null
    }

    override fun onDestroy() {
        executor.execute { closeDns() }
        executor.shutdown()
        super.onDestroy()
    }
}
