# Edge LLM (Mobile AI Research Sandbox) 🧠📱

A cutting-edge experimental Flutter application designed to test the limits of running Large Language Models (LLMs) **natively on Android devices** using entirely local compute. 

While the current UI is themed around an "Expense Tracker," this repository serves as a broader **research sandbox**. The core objective is exploring how we can process highly sensitive personal information (like finances, health data, or private messages) directly on-device without ever sending data to cloud APIs. 100% offline, 100% privacy-preserving.

This project bridges a beautiful Flutter frontend with the raw native C++ performance of [`llama.cpp`](https://github.com/ggerganov/llama.cpp) via JNI and Android NDK, allowing AI to parse natural language inputs directly on the phone's CPU architecture.

## ✨ Research Focus & Features
- **Zero-Trust Architecture:** Demonstrates how sensitive personal data can be parsed and categorized by an LLM without leaving the device.
- **Hardware Benchmarking:** Configurable CPU thread allocation via Flutter UI to benchmark performance across asymmetric mobile processors (big.LITTLE architectures).
- **Native Concurrency:** Heavy C++ inference is offloaded to background threads, ensuring a buttery-smooth 60fps UI without ANR (App Not Responding) crashes during long generations.
- **Memory Optimization (Quantization):** heavily experimented with 4-bit/8-bit quantized `.gguf` models to fit massive neural networks within strict mobile RAM constraints.

---

## 🛠️ Tech Stack
* **Frontend:** Flutter & Dart
* **Native Bridge:** Kotlin (MethodChannels, Background Threading)
* **AI Engine:** C++17, JNI, Android NDK, `llama.cpp`

---

## 🚀 Getting Started

Because this project relies on native C++ dependencies, you need to set up the `llama.cpp` source code alongside this repository.

### 1. Clone the Repositories
You must clone `llama.cpp` so that it sits exactly 6 directories above the `pocket_ai_test/android/app/src/main/cpp` folder. The easiest way is to put them side-by-side:

```bash
# Clone this repository
git clone https://github.com/Ujje421/edge-llm.git

# Clone llama.cpp next to it
git clone https://github.com/ggerganov/llama.cpp.git
```

*(Note: If you place `llama.cpp` somewhere else, you will need to update the paths in `android/app/src/main/cpp/CMakeLists.txt`)*

### 2. Download the Model
Due to file size constraints, the AI model is not included in this repository.
1. Download any small parameter quantized model in `.gguf` format (e.g., Llama 3 8B Q4_K_M, or a custom LoRA fine-tune).
2. Place the `.gguf` file in your Android device's `/sdcard/Download/` folder.
3. Rename it to `pocket-ai-expense-q8.gguf` (or update the filename in `lib/main.dart`).

### 3. Build & Run
Ensure you have the **Android NDK** installed via Android Studio.

```bash
cd edge-llm
flutter pub get
flutter run
```

*Note: The first build will take some time as CMake compiles the C++ `llama.cpp` engine for ARM64 architecture.*

---

## 📈 Benchmarking
When you launch the app, use the dropdown menu to select the number of CPU cores to allocate. 
Because Android processors use variable clock speeds (thermal throttling) and asymmetric core designs, **more threads does not always equal faster inference.** 
Test 1, 2, 4, and 6 cores to find the optimal generation speed for your specific device!

---
*Built as a proof-of-concept for Edge AI on mobile.*

---

## 📚 Edge AI Research Papers

This repository includes three in-depth engineering research papers documenting the systems-level challenges of running LLMs natively on smartphones. These are not summaries — they are detailed technical write-ups covering architecture diagrams, hardware benchmarks, mathematical foundations, and root-cause analyses from our hands-on experimentation.

| # | Paper | Length | Topic |
|---|---|---|---|
| 1 | **[Edge AI Architecture: Bridging Flutter, Kotlin, JNI, and C++](docs/01_ARCHITECTURE.md)** | ~2,500 words | Full 5-layer software stack dissection. Covers the JNI memory marshalling boundary, the ANR threading crisis, the end-to-end data flow trace of a single inference (17 steps from Dart to C++ and back), and why Kotlin Coroutines cause thread contention with llama.cpp's internal pthreads. |
| 2 | **[Hardware Bottlenecks: big.LITTLE, Thermal Throttling, and the Memory Wall](docs/02_HARDWARE_BOTTLENECKS.md)** | ~3,000 words | Explains why 8 threads is slower than 2 threads (barrier synchronization across heterogeneous cores), includes real thermal throttling measurements over 60-second sustained inference, and presents the bandwidth arithmetic proving that memory bandwidth — not CPU FLOPS — is the dominant bottleneck. Includes comparison to datacenter A100 GPU bandwidth. |
| 3 | **[Post-Training Quantization: From Q8 to Q4_K_M](docs/03_QUANTIZATION.md)** | ~3,500 words | Mathematical foundations of block quantization, the full llama.cpp quantization format zoo (Q4_0 through Q6_K), tensor-level breakdown of all 290 model tensors showing exactly which layers fell back from Q4_K to Q5_0 (and why: hidden dimension 896 is not divisible by 256), double-quantization error analysis, and future directions including IQ4_XS importance-aware quantization and QAT. |
