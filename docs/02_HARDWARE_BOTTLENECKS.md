# Paper 2: Hardware Constraints of Mobile LLM Inference — Asymmetric Cores, Thermal Throttling, and the Memory Wall

**Author:** Ujjwal  
**Date:** October 2026  
**Repository:** [github.com/Ujje421/edge-llm](https://github.com/Ujje421/edge-llm)

---

## Abstract

This paper investigates the hardware-level constraints that dominate the performance characteristics of on-device Large Language Model (LLM) inference on Android smartphones. We examine three phenomena that have no equivalent in datacenter GPU deployments: asymmetric core scheduling (ARM big.LITTLE), dynamic thermal throttling under sustained compute loads, and the memory bandwidth wall that fundamentally limits token generation throughput. Our findings demonstrate that naive parallelization strategies (maximizing thread count) are counterproductive on mobile, and that the true bottleneck of mobile LLM inference is not computational throughput (FLOPS) but memory bandwidth (GB/s). This paper is grounded in hands-on experimentation on a physical OnePlus Nord CE4 Lite (CPH2793) running Android 16 (API 36).

---

## 1. Introduction

The prevailing assumption among developers first approaching Edge AI is that mobile CPUs are simply "too slow" to run a meaningful language model. This assumption is incorrect. Modern ARM processors — even mid-range chipsets like the Qualcomm Snapdragon 695 — are capable of executing the mathematical operations (primarily matrix-vector multiplications) required for transformer inference at reasonable speeds.

The actual constraints are more subtle and more physical:

1. **Core heterogeneity:** Not all CPU cores are equal.
2. **Thermal budgets:** The phone cannot sustain peak performance indefinitely.
3. **Memory bandwidth:** The RAM bus cannot deliver data to the CPU fast enough.

Understanding these three constraints is essential for anyone attempting to deploy AI models on edge devices. Each is explored in depth below.

---

## 2. Asymmetric Core Scheduling (ARM big.LITTLE)

### 2.1 Background

Since ARM's introduction of the big.LITTLE architecture in 2011, virtually all Android smartphones ship with heterogeneous CPU configurations. A typical modern SoC (System on Chip) contains:

- **Performance cores ("big"):** 1–4 high-clock-speed cores optimized for single-threaded burst performance. These cores have larger caches, wider execution pipelines, and out-of-order execution capabilities.
- **Efficiency cores ("LITTLE"):** 4–6 low-power cores designed for background tasks, notification processing, and idle-state maintenance. These cores sacrifice raw throughput for dramatically lower power consumption.

For example, the Qualcomm Snapdragon 695 in our test device features:

| Core Type | Count | Max Clock | Cache | Purpose |
|---|---|---|---|---|
| Cortex-A78 (big) | 2 | 2.2 GHz | 512 KB L2 | Performance bursts |
| Cortex-A55 (LITTLE) | 6 | 1.8 GHz | 128 KB L2 | Background / efficiency |

### 2.2 The Threading Paradox

When configuring `llama.cpp`, the `n_threads` parameter controls how many OS threads are spawned for the parallelized portions of the transformer forward pass (primarily the matrix multiplications in the attention and feed-forward layers).

**The naive assumption:** More threads = more parallelism = faster inference.

**The observed reality:** On our test device, we measured the following approximate token generation rates:

| Threads | Tokens/sec | Notes |
|---|---|---|
| 1 | ~1.2 | Single big core; clean but slow |
| 2 | ~2.0 | Both big cores saturated; optimal |
| 4 | ~1.8 | 2 big + 2 LITTLE; slight degradation |
| 6 | ~1.3 | 2 big + 4 LITTLE; significant degradation |
| 8 | ~0.9 | All cores; worst performance |

Performance **peaked at 2 threads** and then declined as more threads were added. At 8 threads, performance was worse than using a single core.

### 2.3 Root Cause Analysis

LLM inference using `llama.cpp` parallelizes matrix multiplications across threads using a barrier-based synchronization model. The computation for each transformer layer is split into chunks, distributed across `n_threads` worker threads, and then synchronized at a barrier before proceeding to the next layer.

The critical insight is that **the barrier forces all threads to wait for the slowest thread to finish its chunk.** When the workload is distributed across both big and LITTLE cores, the big cores complete their chunks in, say, 2 milliseconds, while the LITTLE cores (running at lower clock speeds with smaller caches) take 5 milliseconds. The big cores sit idle for 3 milliseconds per layer, per token.

Over a 24-layer transformer generating 100 tokens, this idle time accumulates to:

```
3 ms × 24 layers × 100 tokens = 7,200 ms = 7.2 seconds of wasted compute
```

This is not a software bug — it is a fundamental consequence of synchronous parallelism across heterogeneous hardware.

### 2.4 Why the OS Cannot Help

One might expect the Android kernel's scheduler (EAS — Energy Aware Scheduling) to preferentially assign all `llama.cpp` threads to big cores. In practice, EAS optimizes for *energy efficiency*, not raw throughput. When it detects multiple CPU-bound threads, it deliberately distributes them across both core clusters to balance thermal load and power consumption. The scheduler is working correctly from its perspective — it simply has different optimization objectives than we do.

Overriding the scheduler (via `sched_setaffinity` or `cpuset` cgroups) requires root access, which is not available on consumer devices. Therefore, **the only reliable mitigation is to limit `n_threads` to the number of big cores**, ensuring the scheduler has no reason to involve the efficiency cluster.

### 2.5 Practical Recommendation

For any given device:

1. Determine the number of high-performance cores (check `/proc/cpuinfo` or the chipset specification).
2. Set `n_threads` equal to that number.
3. Set `n_threads_batch` to the same value (batch processing during prompt evaluation benefits from the same constraint).

We exposed this as a runtime-configurable dropdown in the Flutter UI, allowing end users to benchmark their specific device without modifying source code.

---

## 3. Thermal Throttling Under Sustained Inference

### 3.1 The Thermal Budget

Smartphones lack active cooling systems (fans, liquid cooling loops). Heat dissipation relies entirely on passive conduction through the chassis. Every watt of power consumed by the CPU is converted to heat that must radiate through the phone's body.

When the CPU sustains high utilization for extended periods (as it does during LLM inference), the die temperature rises. Once it crosses a manufacturer-defined threshold (typically 80–95°C), the SoC's thermal management firmware forcibly reduces the CPU clock speed — a process called **dynamic frequency scaling** or **thermal throttling**.

### 3.2 Observed Behavior

During a sustained inference session on our test device (continuous token generation for 60+ seconds), we observed the following pattern:

```
Time (s)    CPU Freq (GHz)    Tokens/sec    Die Temp (°C)
0-10        2.2               ~2.0          45
10-20       2.2               ~2.0          62
20-30       2.0               ~1.7          75
30-45       1.6               ~1.3          82
45-60       1.4               ~1.0          85 (throttled)
60+         1.2               ~0.8          87 (sustained throttle)
```

After approximately 30 seconds of continuous inference, the device throttled the big cores from 2.2 GHz down to 1.4 GHz, reducing token generation throughput by approximately 50%.

### 3.3 Implications for Edge AI

This has profound implications for conversational AI on mobile:

1. **Short prompts are fast; long prompts degrade.** A 50-token generation completes before thermal throttling engages. A 500-token generation will experience significant slowdown in the second half.

2. **Benchmarking is misleading.** Measuring tokens/sec on the first inference after a cold start gives an optimistically high number. Sustained throughput under thermal pressure is the true performance envelope.

3. **Quantization helps thermally.** A smaller model (Q4 vs Q8) performs fewer memory accesses per token, which reduces total power consumption, which reduces heat generation, which delays the onset of throttling. This creates a compounding benefit: Q4 is not just faster due to bandwidth — it stays faster for longer.

### 3.4 Mitigation Strategies

- **Reduce model size** via quantization (see Paper 3).
- **Insert cooling pauses** between inference calls if implementing a multi-turn conversation.
- **Monitor thermal state** via Android's `ThermalManager` API and warn the user or reduce thread count dynamically when the device approaches thermal limits.
- **Limit context length** to keep individual generations short, completing before throttling engages.

---

## 4. The Memory Bandwidth Wall

### 4.1 The True Bottleneck

This section addresses the single most important hardware constraint in mobile LLM inference. It is counterintuitive, widely misunderstood, and explains most of the performance characteristics we observe.

**The bottleneck of LLM inference is not compute. It is memory bandwidth.**

### 4.2 Why Bandwidth Matters More Than FLOPS

During the autoregressive token generation phase (as opposed to the initial prompt processing phase), the model generates one token at a time. For each token, the engine must:

1. Read the *entire* weight tensor for each layer from RAM into CPU registers.
2. Perform a matrix-vector multiplication (the current token's hidden state × the weight matrix).
3. Write the result back.
4. Repeat for all layers.

The matrix-vector multiplication for a single token is computationally lightweight — it involves multiplying a vector of dimension `d_model` (e.g., 896 for our Qwen2.5 0.5B model) against a weight matrix. The arithmetic is fast. But the weight matrix must be physically loaded from DRAM into the CPU's cache hierarchy for every single token.

### 4.3 The Arithmetic

Let us calculate the theoretical maximum tokens/sec for our setup:

**Model:** Qwen2.5 0.5B, Q8_0 quantization  
**Weight file size:** 531 MB  
**Approximate weight data accessed per token:** ~500 MB (nearly the entire model, minus embeddings cached separately)  

**Device LPDDR4X memory bandwidth:** ~17 GB/s (theoretical peak for a dual-channel configuration)

```
Theoretical max tokens/sec = Bandwidth / Weight size per token
                           = 17,000 MB/s ÷ 500 MB/token
                           = 34 tokens/sec (absolute theoretical maximum)
```

In practice, we achieve approximately 2 tokens/sec. The 17x gap between theoretical and observed is explained by:

1. **Cache misses and TLB pressure.** The model does not fit in L1/L2 cache (~512 KB combined), so every access goes to DRAM via the memory controller.
2. **Memory access patterns.** Quantized weight lookups involve non-sequential access patterns that defeat hardware prefetchers.
3. **Shared bandwidth.** The GPU, display controller, and OS kernel all share the same memory bus. The CPU does not get exclusive access.
4. **Memory controller overhead.** LPDDR4X has non-trivial latency per request (~50ns), and thousands of requests are needed per layer.
5. **Synchronization overhead.** Inter-thread barriers consume cycles on every layer.

### 4.4 Why Quantization Directly Attacks This Wall

If the model is quantized from Q8 (8 bits per weight, 531 MB) to Q4 (4 bits per weight, 373 MB), the amount of data that must cross the memory bus per token drops by approximately 30%. This directly translates to a proportional speedup in the bandwidth-limited regime:

```
Improvement factor = 531 / 373 = ~1.42x
```

In practice, we observed approximately a 1.3–1.5x speedup from Q8 to Q4, consistent with this prediction. The speedup is real, measurable, and grounded in physics.

### 4.5 Comparison to GPU Inference

For context, an NVIDIA A100 GPU has ~2 TB/s of HBM2e bandwidth — approximately **120x** the bandwidth of a mobile LPDDR4X configuration. This is the primary reason why datacenter GPUs can generate 50–100+ tokens/sec with 70B-parameter models, while a smartphone struggles to reach 2 tokens/sec with a 0.5B-parameter model. The compute capability gap is far smaller; the bandwidth gap is enormous.

This also explains why simply "adding a mobile GPU" (via Vulkan compute) provides modest improvements for LLM inference: the mobile GPU shares the same LPDDR memory bus as the CPU. The bandwidth ceiling does not change.

---

## 5. Experimental Setup

All measurements in this paper were collected on the following hardware and software configuration:

| Component | Specification |
|---|---|
| **Device** | OnePlus Nord CE4 Lite (CPH2793) |
| **SoC** | Qualcomm Snapdragon 695 5G |
| **CPU** | 2× Cortex-A78 @ 2.2 GHz + 6× Cortex-A55 @ 1.8 GHz |
| **RAM** | 8 GB LPDDR4X |
| **OS** | Android 16 (API 36) |
| **Model** | Qwen2.5 0.5B (custom LoRA fine-tune for expense extraction) |
| **Quantizations tested** | Q8_0 (531 MB), Q4_K_M (373 MB) |
| **Inference engine** | llama.cpp (commit from late 2026, v0.5.0-dev) |
| **Build toolchain** | Android NDK r27, CMake 3.22.1, Clang 18 |

---

## 6. Conclusion

The three hardware constraints documented in this paper — core heterogeneity, thermal throttling, and memory bandwidth — are not bugs to be fixed. They are physical realities of the mobile platform. Any serious Edge AI deployment must be designed around them, not in spite of them.

The key takeaways for practitioners:

1. **Thread count must match big-core count**, not total core count. Over-threading causes synchronization-induced slowdowns.
2. **Sustained performance is lower than burst performance.** Design for the thermally-throttled steady state, not the first-second peak.
3. **Memory bandwidth is the dominant bottleneck.** Reducing model size (via quantization) is the most effective single optimization because it directly reduces the data volume crossing the memory bus per token.

These findings inform our quantization strategy, detailed in Paper 3.
