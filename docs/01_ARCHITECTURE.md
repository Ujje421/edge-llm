# Paper 1: Edge AI Architecture — Bridging Flutter, Dart, Kotlin, JNI, and C++ for On-Device LLM Inference

**Author:** Ujjwal  
**Date:** October 2026  
**Repository:** [github.com/Ujje421/edge-llm](https://github.com/Ujje421/edge-llm)

---

## Abstract

This paper presents the full systems-level architecture of Edge LLM, an Android application that executes Large Language Model (LLM) inference entirely on-device using a multi-layered software stack: Flutter/Dart for the cross-platform UI, Kotlin for Android lifecycle management and concurrency control, JNI (Java Native Interface) for the managed-to-native boundary crossing, and C++17 with `llama.cpp` for the raw tensor computation. We document each layer's responsibilities, failure modes, and the specific engineering decisions made to prevent data corruption, thread starvation, and OS-level process termination during inference. This paper is intended for engineers who want to understand *why* running an LLM on a phone is architecturally different from running one on a server.

---

## 1. Introduction: Why Architecture Matters for Edge AI

Running an LLM on a cloud server is, from a systems perspective, straightforward. The model lives in GPU VRAM. A Python process loads it, accepts HTTP requests, runs inference, and returns JSON. The operating system is permissive — there are no hard deadlines, no mandatory UI responsiveness requirements, and effectively unlimited memory.

A smartphone inverts every one of these assumptions:

| Constraint | Server | Android Device |
|---|---|---|
| **Memory** | 64–256 GB RAM, 24–80 GB VRAM | 6–12 GB shared RAM (no discrete VRAM) |
| **Threading** | No UI thread; all threads are equal | Strict Main Thread with a 5-second liveness deadline |
| **Thermal** | Active liquid/air cooling | Passive thermal dissipation; CPU throttles under sustained load |
| **Process lifecycle** | Process runs until explicitly killed | OS may kill background processes at any time to reclaim memory |
| **Power** | Unlimited (wall socket) | Battery-constrained; sustained high CPU draws drain rapidly |

These constraints are not theoretical — they manifest as hard crashes, thermal throttling, and user-facing jank within seconds of naive LLM execution. Our architecture was designed to navigate all of them simultaneously.

---

## 2. The Full Software Stack

The application consists of five distinct layers, each with a well-defined responsibility boundary:

```
┌─────────────────────────────────────┐
│  Layer 5: Flutter/Dart UI           │  ← User interaction, state management
│  (lib/main.dart)                    │
├─────────────────────────────────────┤
│  Layer 4: Platform Channel          │  ← Serialized method calls across the
│  (MethodChannel)                    │     Dart ↔ Kotlin boundary
├─────────────────────────────────────┤
│  Layer 3: Kotlin Activity           │  ← Android lifecycle, thread spawning,
│  (MainActivity.kt)                  │     JNI call dispatch
├─────────────────────────────────────┤
│  Layer 2: JNI Bridge                │  ← Managed ↔ Native memory marshalling
│  (System.loadLibrary)               │
├─────────────────────────────────────┤
│  Layer 1: C++ Inference Engine      │  ← Tensor math, tokenization, sampling
│  (llama_binding.cpp + llama.cpp)    │
└─────────────────────────────────────┘
```

### 2.1 Layer 1: The C++ Inference Engine

At the bottom of the stack sits `llama.cpp`, an open-source C/C++ implementation of the LLaMA transformer architecture. Our binding file (`llama_binding.cpp`) exposes exactly two functions to the JNI layer:

```cpp
// Loads the .gguf model file from disk into RAM and initializes the KV-cache
extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_edgellm_MainActivity_loadModel(
    JNIEnv* env, jobject, jstring model_path, jint threads);

// Accepts a UTF-8 prompt string, tokenizes it, runs autoregressive generation,
// and returns the decoded output as a Java String
extern "C" JNIEXPORT jstring JNICALL
Java_com_example_edgellm_MainActivity_promptModel(
    JNIEnv* env, jobject, jstring j_prompt);
```

**Critical design decisions in this layer:**

1. **Global state via static pointers.** The loaded model (`llama_model*`) and context (`llama_context*`) are stored as file-scoped static variables. This is intentional: the model must persist in memory across multiple `promptModel` calls without reloading the 300–500 MB weight file each time. The tradeoff is that the binding is inherently single-model and not thread-safe for concurrent inference — an acceptable constraint for a single-user mobile device.

2. **Thread count injection.** The `n_threads` and `n_threads_batch` parameters on `llama_context_params` are set at model-load time based on a value passed down from the Flutter UI. This allows runtime benchmarking without recompilation. The implications of thread count selection are explored extensively in Paper 2.

3. **Greedy sampling with temperature.** For the expense-tracking use case, we use a low temperature (0.1–0.3) to produce deterministic, structured JSON output. Higher temperatures introduce randomness that is desirable for creative text but destructive for structured data extraction.

### 2.2 Layer 2: The JNI Boundary

JNI is the mechanism by which Kotlin (running on the Android Runtime / ART) calls into native C++ code compiled by the NDK. This boundary is the most failure-prone layer in the entire stack.

**Why JNI is dangerous:**

- **String marshalling.** Java/Kotlin strings are UTF-16 encoded and garbage-collected. C++ expects null-terminated UTF-8 byte arrays in manually managed memory. Every string crossing the JNI boundary requires an explicit `GetStringUTFChars` / `ReleaseStringUTFChars` pair. Forgetting the release causes a native memory leak that the Dalvik/ART garbage collector cannot detect or reclaim.

- **Exception propagation.** C++ exceptions do not cross the JNI boundary. If `llama.cpp` throws (e.g., due to a corrupt `.gguf` file), the exception is lost and the JVM enters an undefined state. We guard against this with `try/catch(...)` blocks in the native code that convert C++ exceptions into JNI `FindClass("java/lang/RuntimeException")` throws.

- **Thread affinity.** A `JNIEnv*` pointer is only valid on the thread that received it. If inference is moved to a background thread (which it must be — see Section 3), the background thread must call `AttachCurrentThread` on the JavaVM to obtain its own valid `JNIEnv*`. Failure to do this results in an immediate SIGSEGV (segmentation fault) crash.

### 2.3 Layer 3: Kotlin Activity and Concurrency

The `MainActivity.kt` file serves three purposes:

1. **Lifecycle host.** It manages the Android Activity lifecycle (`onCreate`, `onDestroy`). Model loading is triggered here.
2. **Platform Channel listener.** It registers a `MethodChannel` handler that listens for serialized method calls from the Dart/Flutter layer.
3. **Thread dispatcher.** It spawns background `java.lang.Thread` instances for all JNI calls and marshals results back to the UI thread via `runOnUiThread`.

The concurrency model is detailed in Section 3.

### 2.4 Layer 4: Platform Channel

Flutter's `MethodChannel` is a serialization protocol. When the Dart code calls:

```dart
await platform.invokeMethod('loadModel', {'path': '...', 'threads': 4});
```

Flutter serializes the method name and arguments into a binary message, sends it across an inter-process communication (IPC) pipe to the native Android side, where Kotlin deserializes it and dispatches the appropriate handler. The return value follows the reverse path.

**Key limitation:** `MethodChannel` is asynchronous from Dart's perspective (it returns a `Future`) but the Kotlin handler runs synchronously on the platform thread. If the handler performs heavy work (like inference), it blocks the platform thread, which in turn blocks the Dart `Future` and freezes the Flutter UI. This is the root cause of the ANR problem described in Section 3.

### 2.5 Layer 5: Flutter/Dart UI

The topmost layer is a standard Flutter `StatefulWidget` that manages:

- A text input field for the user's natural-language expense description.
- A dropdown selector for CPU thread count (1–8).
- A "Load Engine" button that triggers model initialization.
- A "Submit" button that triggers inference.
- A response display area that renders the LLM's structured output.

All state transitions (`_isLoading`, `_response`, `_threadCount`) are managed via `setState()` and trigger immediate UI rebuilds.

---

## 3. The ANR Crisis: Why Naive Inference Kills the App

### 3.1 Android's Liveness Contract

The Android operating system enforces a strict contract: the Main Thread (also called the UI Thread) must process each input event (touch, draw, animation frame) within approximately 16 milliseconds (to maintain 60fps rendering). If the Main Thread is blocked for more than **5 seconds**, the system raises an ANR (Application Not Responding) dialog and offers the user the option to force-kill the process.

This is not a suggestion or a best practice — it is an enforced OS-level deadline.

### 3.2 The Problem

In our initial implementation, the `MethodChannel` handler in Kotlin called `loadModel` and `promptModel` directly on the platform thread (which runs on the Main Thread):

```kotlin
// BROKEN: This blocks the Main Thread for 10+ seconds
channel.setMethodCallHandler { call, result ->
    when (call.method) {
        "promptModel" -> {
            val response = promptModel(prompt)  // Blocks for 10-15 seconds
            result.success(response)
        }
    }
}
```

A single inference call to our 500 MB model could take 10–30 seconds depending on prompt length, thread count, and thermal state. The OS would kill the app every single time.

### 3.3 The Solution: Dedicated Background Threads

We refactored the Kotlin layer to dispatch all JNI calls onto dedicated `java.lang.Thread` instances:

```kotlin
"promptModel" -> {
    val prompt = call.argument<String>("prompt") ?: ""
    Thread {
        val response = promptModel(prompt)  // Runs on background thread
        runOnUiThread {
            result.success(response)  // Returns result on Main Thread
        }
    }.start()
}
```

**Why `java.lang.Thread` instead of Kotlin Coroutines?**

Kotlin Coroutines with `Dispatchers.Default` use a shared thread pool sized to the number of CPU cores. When `llama.cpp` is configured with, say, 4 threads internally, and the coroutine dispatcher also allocates threads from the same pool, the two systems compete for the same physical cores. This can cause thread contention, priority inversion, and unpredictable scheduling delays.

By using a raw `java.lang.Thread`, we guarantee that the JNI call runs on a single, dedicated OS thread that does not interfere with Kotlin's coroutine machinery. The `llama.cpp` engine then internally spawns its own pthreads (via `std::thread`) for parallelized matrix multiplication, giving us clean separation between the orchestration thread and the compute threads.

### 3.4 The `runOnUiThread` Contract

After inference completes on the background thread, we must return the result to the Main Thread before calling `result.success()`. This is because Flutter's Platform Channel protocol requires that result callbacks are invoked on the same thread that received the original method call (the Main Thread).

`runOnUiThread` is a convenience method on `Activity` that posts a `Runnable` to the Main Thread's `Looper` message queue, ensuring it executes on the next available UI frame.

---

## 4. Memory Architecture: How 500 MB of Weights Live in Mobile RAM

### 4.1 The Loading Process

When `loadModel` is called, the following sequence occurs:

1. `llama_model_load_from_file()` opens the `.gguf` file and memory-maps (mmap) the weight tensors directly from the filesystem. This means the OS does not necessarily copy all 500 MB into physical RAM immediately — it maps virtual address space to the file on disk and loads pages on demand as the inference engine accesses them.

2. `llama_init_from_model()` allocates the KV-cache (Key-Value cache) used for autoregressive generation. The KV-cache size depends on the model's context window and the number of attention heads. For our Qwen2.5 0.5B model with a 2048-token context, the KV-cache is relatively small (~50–100 MB).

3. After initialization, the total resident memory footprint is approximately:
   - **Model weights:** 300–530 MB (depending on quantization level)
   - **KV-cache:** ~50–100 MB
   - **Scratch buffers:** ~20–50 MB
   - **Total:** ~400–680 MB

On a device with 8 GB of RAM, this leaves approximately 3–4 GB for the Android OS, other apps, and the Flutter rendering engine. This is tight but viable.

### 4.2 Memory Pressure and OOM

If the user switches to another heavy application while Edge LLM is loaded, Android's Low Memory Killer (LMK) daemon may terminate our process to reclaim RAM. The model weights are then lost and must be reloaded from disk on the next launch. This is an inherent limitation of mobile Edge AI — the model competes with every other app for a shared, scarce resource.

---

## 5. Build System: CMake, NDK, and Cross-Compilation

### 5.1 The Compilation Pipeline

The C++ code is compiled by the Android NDK's Clang toolchain, targeting the `arm64-v8a` ABI (64-bit ARM). The build is orchestrated by CMake, which is invoked automatically by Gradle during `flutter build apk`.

Our `CMakeLists.txt` performs the following:

1. Sets the CMake minimum version and project name.
2. Locates the `llama.cpp` source tree (expected 6 directories above the `cpp/` folder).
3. Compiles the core `llama.cpp` source files (`llama.cpp`, `ggml.cpp`, `ggml-cpu.cpp`, `ggml-alloc.cpp`, `ggml-backend.cpp`, `ggml-quants.cpp`, `unicode.cpp`, `unicode-data.cpp`) into a static library.
4. Compiles our `llama_binding.cpp` JNI wrapper into a shared library (`.so`).
5. Links the two together with the Android `log` library for `__android_log_print` support.

### 5.2 Why Static Linking?

We compile `llama.cpp` as a static library (`.a`) rather than a shared library (`.so`) to avoid dynamic linker issues on Android. Shared libraries must be explicitly loaded at runtime via `System.loadLibrary()`, and having multiple `.so` files with interdependencies can cause load-order failures on certain Android versions. A single monolithic `.so` containing both our JNI bindings and the full `llama.cpp` engine eliminates this class of bugs entirely.

---

## 6. Data Flow: End-to-End Trace of a Single Inference

To make the architecture concrete, here is the exact sequence of events when a user types "I spent $15 on coffee at Starbucks" and taps Submit:

```
1. [Dart]    User taps "Submit" → setState({_isLoading: true})
2. [Dart]    platform.invokeMethod('promptModel', {'prompt': '...'})
3. [Dart]    MethodChannel serializes args to binary StandardMethodCodec
4. [IPC]     Binary message crosses Dart → Kotlin process boundary
5. [Kotlin]  MethodCallHandler receives call on Platform Thread (Main Thread)
6. [Kotlin]  Spawns new java.lang.Thread
7. [Thread]  Background thread calls JNI: promptModel(jstring)
8. [JNI]     GetStringUTFChars converts UTF-16 Java String to UTF-8 C char*
9. [C++]     llama_tokenize() converts char* to token IDs using BPE tokenizer
10. [C++]    For each output token:
             a. llama_decode() runs forward pass (matrix multiplications across all layers)
             b. llama_sampler_sample() selects next token based on logits + temperature
             c. llama_token_to_piece() converts token ID back to UTF-8 string fragment
             d. Append fragment to output buffer
             e. Check for EOS (end-of-sequence) token → break if found
11. [C++]    Return complete output string
12. [JNI]    NewStringUTF converts C char* back to Java String
13. [Thread] runOnUiThread { result.success(response) }
14. [Kotlin] Result posted to Main Thread's Looper queue
15. [IPC]    Binary response crosses Kotlin → Dart boundary
16. [Dart]   Future completes → setState({_response: '...', _isLoading: false})
17. [Dart]   Flutter rebuilds widget tree, rendering the response
```

Total wall-clock time for this sequence: **5–30 seconds** depending on model size, quantization, thread count, output length, and thermal state.

---

## 7. Limitations and Future Work

1. **Single-model constraint.** The current architecture supports only one loaded model at a time due to global static state in the C++ layer. Supporting model swapping would require explicit deallocation (`llama_free` / `llama_model_free`) before loading a new model.

2. **No streaming.** The current implementation waits for the entire generation to complete before returning the result. A production system should stream tokens back to the UI one at a time using a callback mechanism (e.g., `invokeMethod` from Kotlin to Dart for each token).

3. **No GPU acceleration.** All inference runs on the CPU. Android devices with Qualcomm Adreno or ARM Mali GPUs could potentially use Vulkan compute shaders via `llama.cpp`'s experimental Vulkan backend for significant speedups.

4. **No context persistence.** Each prompt is independent — there is no multi-turn conversation support. Implementing this would require preserving the KV-cache between calls.

---

## 8. Conclusion

The architecture presented here is not a toy demo. It is a minimal but complete production pathway for embedding transformer-based language models into mobile applications. Every layer — from the Flutter widget tree down to the pthread-level matrix multiplications — was designed with the physical constraints of mobile hardware in mind. The key insight is that Edge AI is not primarily an AI problem; it is a **systems engineering** problem. The model itself is a static artifact. The challenge is building the software infrastructure around it that respects the operating system's liveness contracts, the hardware's memory bandwidth limits, and the user's expectation of a responsive interface.
