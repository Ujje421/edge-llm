# Overcoming Memory Walls via Post-Training Quantization

## 1. Introduction
Because Mobile AI is fundamentally constrained by Memory Bandwidth (as explored in our Hardware Research), shrinking the physical file size of the LLM is the only viable path to achieving real-time token generation on a smartphone. This paper outlines our use of Post-Training Quantization to manipulate memory physics.

## 2. What is Quantization?
Neural networks are traditionally trained using 16-bit or 32-bit floating-point numbers (f16/f32) to represent the weights of the model. Quantization is the mathematical process of rounding these highly-precise weights into smaller, lower-precision integers (like 8-bit or 4-bit) after the model has already been trained. 

## 3. The Q8 to Q4 Experiment
Our baseline testing was conducted using an 8-bit quantized model (`Q8_0`). This model occupied **531 MB** of RAM and provided high reasoning accuracy, but suffered from slow generation speeds due to the device's memory bus struggling to feed 531 MB to the CPU per token.

### The Conversion
Using the `llama.cpp` quantization toolchain, we aggressively compressed the model down to a 4-bit representation (`Q4_K_M`):
```bash
llama-quantize --allow-requantize pocket-ai-q8.gguf pocket-ai-q4.gguf Q4_K_M
```

### The Results
The resulting file weighed only **373 MB** (a ~30% reduction). 
By reducing the physical footprint of the model, we artificially "widened" the phone's memory bandwidth. The RAM was able to pass the 373 MB file to the CPU significantly faster, resulting in a **near-linear speedup in generation time**. Because we utilized the `K_M` (K-Quant Medium) algorithm, the critical attention layers retained higher bit-rates, ensuring that the 4-bit compression caused statistically negligible loss in the AI's logical coherence.

## 4. Conclusion
For Edge AI applications handling sensitive personal data offline, `Q4_K_M` quantization currently represents the optimal intersection of speed, memory footprint, and intelligence for Android deployments.
