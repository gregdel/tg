# tg

`tg` is a Linux-only, transmit-only traffic generator built on AF_XDP and
written in Zig, optimized for high‑rate packet generation directly from user
space.
It creates one dedicated thread per NIC TX queue and drives AF_XDP sockets
bound to those queues for predictable performance and NUMA‑friendly CPU
affinity.

### Features

- Transmit‑only AF_XDP packet generator (no RX path), focusing on high‑rate,
  low‑latency packet transmission from user space.
- Per‑TX‑queue worker threads, each pinned to the CPU set configured for that
  queue under `/sys/class/net/<dev>/queues/tx-*/xps_cpus`.
- YAML configuration of packet templates with protocol “layers” (Ethernet,
  IPv4/IPv6, UDP, etc.).
- Flexible `Range` abstraction for each field.
- Fully static, musl‑targeted binary with statically linked `libbpf` and
  `libxdp` for deployment on minimal systems.
- Attach XDP programs to NICs: pass / drop.

### Architecture overview

`tg` uses AF_XDP sockets to bypass most of the kernel network stack and operate
directly on UMEM‑backed packet buffers in user space. Each worker thread owns
its UMEM and AF_XDP socket, which is bound to a single NIC TX queue, avoiding
sharing and locking between threads.


The threading model is derived from Linux’s per‑queue transmit scheduling,
using the `xps_cpus` mask to map queues to CPUs. By setting the thread’s CPU
affinity before creating UMEM and the AF_XDP socket, `tg` keeps memory and NIC
queue access local to the intended core.

### Requirements

- **OS**: Linux with AF_XDP support enabled in the kernel (XDP and AF_XDP
  address family).
- **Compiler**: Zig 0.15.2.
