# L1-split-cache
L1 Split Cache Simulator
Designed and simulation of a split L1 cache for a new 32- bit processor which can be used with up to three other processors in a shared memory configuration. The system employs a MESI protocol to ensure cache coherence.
 L1 instruction cache is four-way set associative and consists of 16K sets and 64- byte lines. L1 data cache is eight-way set associative and consists of 16K sets of 64- byte lines. The L1 data cache is write-back using write allocate and is write-back except for the first write to a line which is write-through. Both caches employ LRU replacement policy and are backed by a shared L2 cache. The cache hierarchy employs inclusivity.
