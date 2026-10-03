package com.example.edgellm

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.pocketai/llama"

    init {
        // Load the C++ library compiled by CMake
        System.loadLibrary("llama_binding")
    }

    // Declare the native JNI function that matches llama_binding.cpp
    private external fun loadModel(modelPath: String, threads: Int): Boolean
    private external fun promptModel(prompt: String): String

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "loadModel") {
                val path = call.argument<String>("path")
                val threads = call.argument<Int>("threads") ?: 4 // Default to 4 threads if not provided

                if (path != null) {
                    // Push the heavy model loading off the UI thread
                    Thread {
                        val success = loadModel(path, threads)
                        runOnUiThread {
                            if (success) {
                                result.success("Model loaded successfully with $threads threads")
                            } else {
                                result.error("LOAD_ERROR", "Failed to load model in C++", null)
                            }
                        }
                    }.start()
                } else {
                    result.error("INVALID_ARGUMENT", "Model path is required", null)
                }
            } else if (call.method == "promptModel") {
                val prompt = call.argument<String>("prompt")
                
                if (prompt != null) {
                    // Push inference completely off the UI thread to prevent ANRs
                    Thread {
                        val response = promptModel(prompt)
                        runOnUiThread {
                            if (response.startsWith("Error:")) {
                                result.error("INFERENCE_ERROR", response, null)
                            } else {
                                result.success(response)
                            }
                        }
                    }.start()
                } else {
                    result.error("INVALID_ARGUMENT", "Prompt is required", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
