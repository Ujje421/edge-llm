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

As part of this project, we have documented the severe hardware constraints of running AI natively on smartphones, and the software methodologies required to overcome them. 

Please read our detailed engineering write-ups:

1. **[Edge AI Architecture: Bridging Flutter, Kotlin, and C++](docs/01_ARCHITECTURE.md)**  
   *How we prevented Android from fatally crashing (ANR) by abstracting synchronous JNI workloads into Kotlin background threads.*
2. **[Hardware Bottlenecks: big.LITTLE and Memory Bandwidth](docs/02_HARDWARE_BOTTLENECKS.md)**  
   *Why allocating 8 threads is slower than 4 threads, and why the physical RAM bus—not the CPU—is the true bottleneck of Mobile AI.*
3. **[Overcoming Memory Walls via Post-Training Quantization](docs/03_QUANTIZATION.md)**  
   *How we achieved a near-linear token generation speedup by mathematically compressing an 8-bit model down to 4-bits, artificially widening the memory bandwidth.*
