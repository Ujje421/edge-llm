# Paper 3: Post-Training Quantization for Mobile Deployment — From Q8 to Q4_K_M and the Mathematics of Precision Loss

**Author:** Ujjwal  
**Date:** October 2026  
**Repository:** [github.com/Ujje421/edge-llm](https://github.com/Ujje421/edge-llm)

---

## Abstract

This paper presents a detailed exploration of post-training quantization as applied to a fine-tuned Qwen2.5 0.5B language model deployed on an Android smartphone. We examine the mathematical foundations of weight quantization, the specific behavior of the `Q4_K_M` quantization scheme used by `llama.cpp`, the phenomenon of fallback quantization when tensor dimensions are incompatible with target block sizes, and the empirical impact on both model size and inference quality. Our key finding is that `Q4_K_M` quantization reduces model size by ~30% (531 MB → 373 MB) while preserving the structured output capability required for our expense-extraction task, and that the speed improvement is directly attributable to reduced memory bus pressure rather than reduced compute.

---

## 1. Introduction: What Problem Does Quantization Solve?

As established in Paper 2, the dominant bottleneck of on-device LLM inference is **memory bandwidth** — the physical rate at which the phone's RAM can deliver model weight data to the CPU. For a 531 MB model generating tokens autoregressively, the phone must push approximately 500 MB of weight data through the memory bus for *every single output token*. On a device with ~17 GB/s of theoretical peak memory bandwidth, this physically limits generation to roughly 34 tokens/second at absolute maximum — and in practice, far less due to cache misses, contention, and access pattern inefficiencies.

Quantization attacks this problem at its root: by mathematically compressing each weight value into fewer bits, the total data volume crossing the memory bus per token is reduced. Fewer bytes per token → faster token generation. The tradeoff is a small reduction in the numerical precision of the weights, which can degrade model quality if done carelessly.

---

## 2. Mathematical Foundations of Weight Quantization

### 2.1 What Are Model Weights?

A transformer language model consists of billions of numerical parameters (called "weights") organized into matrices. These matrices perform linear transformations on the input data as it passes through the model's layers. During training, weights are stored as 32-bit floating-point numbers (`float32`), giving each weight ~7 decimal digits of precision.

### 2.2 The Quantization Transform

Quantization maps a continuous range of floating-point values into a discrete set of integer values. For `k`-bit quantization, each weight is mapped to one of `2^k` possible values.

**Uniform quantization formula:**

Given a tensor of weights `W` with minimum value `w_min` and maximum value `w_max`:

```
scale = (w_max - w_min) / (2^k - 1)
zero_point = round(-w_min / scale)
W_quantized = round(W / scale) + zero_point
```

**Dequantization (at inference time):**

```
W_reconstructed = (W_quantized - zero_point) × scale
```

The difference `W - W_reconstructed` is the **quantization error**. This error is the price we pay for compression.

### 2.3 Block Quantization vs. Per-Tensor Quantization

Naive per-tensor quantization (computing a single `scale` and `zero_point` for the entire matrix) is highly lossy because outlier values stretch the quantization range, wasting most of the `2^k` levels on the sparse tails of the distribution.

Modern quantization schemes (including all `llama.cpp` formats) use **block quantization**: the weight tensor is divided into small blocks (typically 32, 64, 128, or 256 consecutive weights), and each block gets its own independent `scale` and `zero_point`. This dramatically reduces quantization error because each block's range is tightly fitted to its local distribution.

---

## 3. The llama.cpp Quantization Zoo

`llama.cpp` implements over a dozen quantization formats. Understanding the naming convention is essential:

### 3.1 Legacy Formats (Q4_0, Q5_0, Q8_0)

| Format | Bits/Weight | Block Size | Extra Data | Notes |
|---|---|---|---|---|
| `Q4_0` | 4.5 BPW | 32 | 1× f16 scale | Simplest 4-bit; no zero-point (symmetric) |
| `Q5_0` | 5.5 BPW | 32 | 1× f16 scale | 5-bit with half-byte trick |
| `Q8_0` | 8.5 BPW | 32 | 1× f16 scale | 8-bit; near-lossless for most models |

"BPW" = Bits Per Weight, including the overhead of storing the per-block scale factor.

### 3.2 K-Quant Formats (Q4_K_S, Q4_K_M, Q6_K)

The "K-Quant" family (introduced by `llama.cpp` contributor ikawrakow) uses a more sophisticated scheme called **super-blocks**: each super-block of 256 weights is subdivided into 8 sub-blocks of 32, with a shared f16 scale for the super-block and per-sub-block q8 scale corrections.

| Format | Avg BPW | Strategy |
|---|---|---|
| `Q4_K_S` | ~4.5 | All layers quantized to q4_K |
| `Q4_K_M` | ~4.8 | Attention value/output layers use q6_K; rest uses q4_K |
| `Q6_K` | ~6.6 | 6-bit K-Quant across all layers |

**`Q4_K_M` is the "Medium" quality variant.** The "M" stands for a mixed-precision strategy: the most sensitive layers (attention value projections and the final output layers in the last ~25% of transformer blocks) are kept at higher precision (q6_K or q8_0), while the less sensitive layers (feed-forward networks, earlier attention blocks) are aggressively compressed to q4_K. This targeted approach preserves model quality where it matters most.

---

## 4. Our Quantization Experiment

### 4.1 Source Model

Our source model is a custom LoRA fine-tune of Qwen2.5 0.5B, merged and exported to GGUF format at `Q8_0` precision. Key specifications:

| Property | Value |
|---|---|
| **Architecture** | Qwen2 (Transformer decoder-only) |
| **Parameters** | ~494 million |
| **Layers** | 24 transformer blocks |
| **Hidden dimension** | 896 |
| **Attention heads** | 14 (with GQA: 2 KV heads) |
| **Vocabulary** | 151,936 tokens (BPE) |
| **Source quantization** | Q8_0 |
| **File size** | 531,067,808 bytes (531 MB) |

### 4.2 The Dimension Compatibility Problem

When we attempted standard `Q4_K_M` quantization, we encountered a systematic issue: **144 out of 290 tensors required fallback quantization.**

The root cause: `Q4_K` requires the tensor's column count to be divisible by 256 (the super-block size). Our model's hidden dimension is 896, which is **not** divisible by 256:

```
896 ÷ 256 = 3.5  → NOT divisible
```

For every weight matrix with 896 columns (which includes the attention Q, K, V, and output projections, plus the feed-forward gate and up projections), `Q4_K` cannot be applied. The quantizer falls back to `Q5_0` (which uses a block size of 32; 896 ÷ 32 = 28, which is an integer).

This is why our final model is **not purely 4-bit** — it is a mixture of Q4_K (for layers with compatible dimensions, primarily the feed-forward down projections with 4864 columns) and Q5_0 (for the 896-column layers). The average bits-per-weight reported by the quantizer is **6.35 BPW**, higher than the ~4.8 BPW you would expect from a pure Q4_K_M quantization.

### 4.3 Tensor-Level Breakdown

The quantizer produced the following distribution across the 290 tensors:

| Tensor Type | Original | Quantized To | Reason |
|---|---|---|---|
| `token_embd.weight` | Q8_0 | Q8_0 | Embedding table preserved (critical for tokenization) |
| `output_norm.weight` | f32 | f32 | Normalization weights kept at full precision |
| `blk.*.attn_q.weight` | Q8_0 | Q5_0 | 896 cols not divisible by 256; fallback |
| `blk.*.attn_k.weight` | Q8_0 | Q5_0 | 896 cols not divisible by 256; fallback |
| `blk.*.attn_v.weight` (layers 0-16) | Q8_0 | Q5_0 | 896 cols not divisible by 256; fallback |
| `blk.*.attn_v.weight` (layers 17-23) | Q8_0 | Q8_0 | K_M strategy: last 25% attention values kept at high precision |
| `blk.*.attn_output.weight` | Q8_0 | Q5_0 | 896 cols not divisible by 256; fallback |
| `blk.*.ffn_down.weight` (layers 0-16) | Q8_0 | Q4_K | 4864 cols divisible by 256 ✓ |
| `blk.*.ffn_down.weight` (layers 17-23) | Q8_0 | Q6_K | K_M strategy: last 25% FFN down layers at higher precision |
| `blk.*.ffn_gate.weight` | Q8_0 | Q5_0 | 896 cols not divisible by 256; fallback |
| `blk.*.ffn_up.weight` | Q8_0 | Q5_0 | 896 cols not divisible by 256; fallback |
| `blk.*.attn_norm.weight` | f32 | f32 | Normalization weights preserved |
| `blk.*.ffn_norm.weight` | f32 | f32 | Normalization weights preserved |
| `blk.*.attn_*.bias` | f32 | f32 | Bias terms preserved |

### 4.4 The `--allow-requantize` Flag

By default, `llama-quantize` refuses to re-quantize a model that is already quantized (i.e., going from Q8_0 to Q4_K_M). This is a safety measure because requantizing introduces **double quantization error** — the weights were already rounded once during the Q8_0 quantization, and rounding them again to Q4/Q5 compounds the precision loss.

We explicitly passed `--allow-requantize` to override this protection:

```bash
llama-quantize --allow-requantize pocket-ai-expense-q8.gguf pocket-ai-expense-q4.gguf Q4_K_M
```

For our use case (structured JSON extraction from expense descriptions), double quantization error was acceptable because:

1. The task is classification-like (extracting category, amount, date) rather than open-ended generation where subtle reasoning matters.
2. The model was fine-tuned specifically for this task, meaning the weight distributions are concentrated around task-relevant values rather than spread across the full range.
3. Empirical testing showed no degradation in structured output accuracy.

Ideally, one would quantize directly from the original f16/f32 weights (before Q8_0). We used the Q8_0 intermediate because it was the artifact available from our training pipeline.

### 4.5 Quantization Command and Output

```bash
llama-quantize.exe --allow-requantize pocket-ai-expense-q8.gguf pocket-ai-expense-q4.gguf Q4_K_M
```

**Key output lines:**

```
llama_model_quantize_impl: model size  =   500.79 MiB (8.50 BPW)
llama_model_quantize_impl: quant size  =   373.71 MiB (6.35 BPW)
llama_model_quantize_impl: WARNING: 144 of 290 tensor(s) required fallback quantization

llama_quantize: quantize time =  2526.69 ms
llama_quantize:    total time =  2526.69 ms
```

The entire quantization completed in **2.5 seconds** on a Windows desktop CPU. This is a trivially cheap operation compared to model training (hours) or fine-tuning (minutes to hours).

---

## 5. Results and Analysis

### 5.1 Size Comparison

| Metric | Q8_0 | Q4_K_M | Reduction |
|---|---|---|---|
| File size | 531 MB | 374 MB | 29.6% |
| Bits per weight | 8.50 | 6.35 | 25.3% |

The 6.35 BPW average (vs. the expected ~4.8 BPW for pure Q4_K_M) is a direct consequence of the dimension-incompatibility fallback discussed in Section 4.2. A model with a hidden dimension divisible by 256 (e.g., 1024, 2048, 4096 — as used by most mainstream architectures like LLaMA, Mistral, GPT-NeoX) would achieve the full Q4_K_M compression ratio.

### 5.2 Inference Speed Impact

Based on the memory bandwidth model from Paper 2:

```
Speed improvement ≈ Q8 size / Q4 size = 531 / 374 = 1.42x
```

Observed improvement: approximately **1.3–1.5x** faster token generation, consistent with the bandwidth-limited model.

### 5.3 Quality Assessment

For our specific task (parsing natural-language expense descriptions into structured JSON), we tested both models with identical prompts:

**Input:** "I spent $42.50 on groceries at Walmart yesterday"

**Q8_0 output:**
```json
{"category": "groceries", "amount": 42.50, "merchant": "Walmart", "date": "yesterday"}
```

**Q4_K_M output:**
```json
{"category": "groceries", "amount": 42.50, "merchant": "Walmart", "date": "yesterday"}
```

For structured extraction tasks with a small, well-defined output space, Q4_K_M quantization produced **identical results** to Q8_0 across our test set. This is expected: the quantization error (typically <1% of weight magnitude for Q4_K_M) is insufficient to shift the model's top-1 token predictions for such a constrained output distribution.

For open-ended generation (creative writing, complex reasoning), Q4_K_M would show more measurable degradation. However, such tasks are not the focus of this application.

---

## 6. Practical Guide: Reproducing the Quantization Pipeline

### Step 1: Build the Quantization Tool

Inside the `llama.cpp` directory:

```bash
mkdir build && cd build
cmake .. -DBUILD_SHARED_LIBS=OFF
cmake --build . --config Release --target llama-quantize
```

This compiles the `llama-quantize` executable using your system's native C++ compiler (MSVC on Windows, GCC/Clang on Linux/macOS). The Android NDK is **not** needed here — the quantization runs on your desktop, not on the phone.

### Step 2: Run Quantization

```bash
./build/bin/Release/llama-quantize --allow-requantize \
    pocket-ai-expense-q8.gguf \
    pocket-ai-expense-q4.gguf \
    Q4_K_M
```

### Step 3: Deploy to Device

```bash
adb push pocket-ai-expense-q4.gguf /sdcard/Download/
```

### Step 4: Update Application Code

In `lib/main.dart`, change the model path:

```dart
'path': '/sdcard/Download/pocket-ai-expense-q4.gguf',
```

---

## 7. Future Directions

### 7.1 Quantize from f16 Instead of Q8

To avoid double quantization error, the ideal pipeline is:

```
Training (f32) → Export to GGUF (f16) → Quantize to Q4_K_M
```

This eliminates the intermediate Q8_0 rounding step and would yield marginally better output quality at the same file size.

### 7.2 Explore IQ4_XS (Importance-Aware Quantization)

`llama.cpp` offers "importance matrix" quantization (`IQ4_XS`, `IQ3_XXS`) that uses calibration data to identify which weights are most important and allocates more precision to them. This can achieve better quality than Q4_K_M at the same or smaller file size, at the cost of a slower quantization process (requires running inference on a calibration dataset).

### 7.3 Test Q2_K and Q3_K for Ultra-Low Memory

For devices with only 4 GB of RAM, even 374 MB may be too large when combined with the KV-cache and OS overhead. Testing Q2_K (~200 MB) and Q3_K (~250 MB) would determine the minimum viable quantization level for our expense-extraction task.

### 7.4 Quantization-Aware Fine-Tuning (QAT)

Rather than quantizing after training (PTQ), QAT incorporates simulated quantization noise during the fine-tuning process itself. This allows the model's weights to "learn" to be robust to quantization, potentially yielding significantly better Q4 quality than our current PTQ approach.

---

## 8. Conclusion

Post-training quantization is not merely a compression trick — it is the **primary performance lever** for on-device LLM inference. By reducing the data volume that must cross the memory bus per token, quantization directly attacks the memory bandwidth wall identified in Paper 2. Our experiment demonstrated a ~30% file size reduction and a corresponding ~1.4x inference speedup, with no measurable degradation in task-specific output quality.

The most important insight from this work is that **quantization quality is model-architecture-dependent**. The hidden dimension of 896 in Qwen2.5 0.5B caused widespread fallback from Q4_K to Q5_0, resulting in a higher-than-expected average BPW. Practitioners selecting models for mobile deployment should prefer architectures with hidden dimensions divisible by 256 (e.g., 1024, 2048, 4096) to maximize the compression ratio of K-Quant formats.
