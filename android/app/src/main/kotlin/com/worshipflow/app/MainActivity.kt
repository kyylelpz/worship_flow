package com.worshipflow.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.sumsg.metronome.MetronomePlugin

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = flutterEngine.plugins.get(MetronomePlugin::class.java)
            as? MetronomePlugin ?: return
        // metronome 2.0.13 omits replies for void operations. Delegate to the
        // registered plugin (one audio engine), then complete its pending call.
        val voidMethods = setOf("init", "play", "pause", "stop", "destroy",
            "setVolume", "setBPM", "setTimeSignature", "setAudioFile")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "metronome")
            .setMethodCallHandler { call, result ->
                try {
                    plugin.onMethodCall(call, result)
                    if (call.method in voidMethods) result.success(null)
                } catch (error: Exception) {
                    result.error("metronome_native_error", error.message, call.method)
                }
            }
    }
}
