# Edge LLM (Edge AI Expense Tracker) 🧠📱

A cutting-edge Flutter application that runs Large Language Models (LLMs) **natively on your Android device** using entirely local compute. No cloud APIs, no internet required, and 100% privacy-preserving.

This project bridges a beautiful Flutter UI with the raw native C++ performance of [`llama.cpp`](https://github.com/ggerganov/llama.cpp) via JNI and Android NDK, allowing the AI to process natural language inputs (like extracting expense data) directly on the phone's CPU.

## ✨ Features
- **100% Local Inference:** Zero data leaves your device.
- **Dynamic Threading:** Configurable CPU thread allocation via Flutter UI to benchmark performance across different mobile processors (big.LITTLE architectures).
- **Asynchronous Execution:** Heavy C++ inference is offloaded to background threads, ensuring a buttery-smooth 60fps UI without ANR (App Not Responding) crashes.
- **Modern "Bento Box" UI:** A clean, satisfying, pastel-themed interface.
- **Quantized AI:** Optimized for 4-bit/8-bit quantized `.gguf` models to fit within mobile RAM constraints.

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
