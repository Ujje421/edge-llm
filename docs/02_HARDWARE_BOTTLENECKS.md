# Hardware Bottlenecks: big.LITTLE and Memory Bandwidth

## 1. Introduction
Unlike cloud-based LLM deployments that run on homogeneous server racks, Edge AI must contend with the chaotic, highly-constrained physical realities of a smartphone. This paper explores two severe hardware bottlenecks discovered during our testing: asymmetric core scheduling and memory bandwidth limits.

## 2. The Asymmetric Core Dilemma (big.LITTLE)
Modern Android processors do not use identical cores. To save battery, they utilize ARM's "big.LITTLE" architecture, pairing 1 or 2 high-performance cores with several low-power efficiency cores.

### The Threading Paradox
When configuring `llama.cpp`, developers traditionally assume that allocating more CPU threads results in faster processing. Our benchmarks proved the opposite: allocating 8 threads yielded significantly slower token generation than allocating 4 threads.

### Explanation
LLM inference is highly sequential. If 8 threads are allocated, the Android OS is forced to distribute the workload across the "LITTLE" efficiency cores. Because the operation must remain synchronized, the ultra-fast "big" cores end up sitting idle, waiting for the slow efficiency cores to finish their matrix mathematics. We concluded that thread allocation must never exceed the physical count of high-performance cores on the target device.

## 3. The Physical Limitation: Memory Bandwidth
The most pervasive myth in Mobile AI is that smartphone CPUs lack the mathematical throughput (FLOPS) to run an LLM. Our research indicates that the processor is rarely the bottleneck; the bottleneck is **Memory Bandwidth**.

### The Math
To generate a single token, an LLM must push its entire weight file through the processor. If a model weighs 1 GB, generating 10 tokens a second requires the phone's RAM bus to physically transfer 10 GB of data to the CPU every single second. 
Most mid-range mobile devices simply do not have a wide enough RAM bus to sustain this throughput, resulting in the CPU "starving" for data. Overcoming this physical limitation requires aggressive software-side compression (Quantization).
