# RESOURCES

All measurements are from Explorer, partition `courses`, on 2 October 2026.

- **Real run:** array 10763575 (8 tasks), cohort 10763583.
- **Core-count runs:** row 1 (NA12878) only, submitted as `TAG=cpuN PERSAMPLE_CPUS=N ARRAY=1 NO_COHORT=1 bash slurm/submit.sh`.
- **Peak memory:** taken from cgroup `memory.peak`, printed at the end of every job. MaxRSS is sampled every 30 s and can miss a peak.

## Per-sample job (`01_persample.sbatch`, stages 0–5)

| | --cpus-per-task | --mem | --time |
|---|---|---|---|
| first request | 8 | 16G | 01:00:00 |
| measured, 8 real tasks | CPU efficiency 34–37 % → ≈2.7–3.0 cores busy | memory.peak 6.96–8.40 GB (max: task 7) · seff 6.74–7.70 GB | 5:09 – 11:10 |
| **set to** | **4** | **10G** | **00:30:00** |

**Memory.** The peak is the same at every core count: 7.05 GB at 2 cores, 7.26 GB at 4 and 7.51 GB at 8, all for NA12878. So memory is dominated by the BWA index (~5.5 GB, loaded once whatever the thread count), not by threads. The largest peak over the 8 samples was 8.40 GB. 10G leaves ~19 % headroom and frees 6 GB per task for other jobs.

**Time.** The slowest task took 11:10. 00:30:00 is ~2.7× that, which allows for a slower node or I/O contention on /scratch. It is still short enough that a hung task is killed within half an hour, rather than holding a node for the full hour.

**Cores.** See the comparison below. Doubling from 4 to 8 bought 5 %, so 4.

```
$ seff 10763575_1
Cores per node: 8
CPU Utilized: 00:21:31
CPU Efficiency: 34.41% of 01:02:32 core-walltime
Job Wall-clock time: 00:07:49
Memory Utilized: 6.74 GB

$ seff 10763575_7
Cores per node: 8
CPU Utilized: 00:32:58
CPU Efficiency: 36.90% of 01:29:20 core-walltime
Job Wall-clock time: 00:11:10
Memory Utilized: 7.70 GB

memory.peak bytes, tasks 1–8:
7486902272  7504916480  6964682752  7475859456  7005540352  7518068736  8403886080  7878733824
```

## Core-count comparison: same sample (row 1, NA12878), stages 0–5

| --cpus-per-task | job | wall clock | CPU utilized | cores busy (CPU ÷ wall) | efficiency | memory.peak |
|---|---|---|---|---|---|---|
| 2 | 10763623_1 | 13:30 | 20:06 | 1.49 | 74 % | 7.05 GB |
| 4 | 10763625_1 | 8:55 | 19:45 | 2.21 | 55 % | 7.26 GB |
| 8 | 10763634_1 | 8:30 | 23:01 | 2.71 | 34 % | 7.51 GB |

```
$ seff 10763623_1          $ seff 10763625_1          $ seff 10763634_1
Cores per node: 2          Cores per node: 4          Cores per node: 8
CPU Utilized: 00:20:06     CPU Utilized: 00:19:45     CPU Utilized: 00:23:01
CPU Efficiency: 74.44%     CPU Efficiency: 55.37%     CPU Efficiency: 33.85%
Wall-clock: 00:13:30       Wall-clock: 00:08:55       Wall-clock: 00:08:30
Memory Utilized: 6.51 GB   Memory Utilized: 6.65 GB   Memory Utilized: 6.79 GB
```

**Decision: 4 cores.**
- **2 → 4** cut wall clock by 34 % (13:30 → 8:55).
- **4 → 8** cut it by 5 % (8:55 → 8:30). The extra four cores raised busy cores only from 2.2 to 2.7, so most of them sat idle.
- **Why the scaling stops.** BWA-MEM and `samtools sort` scale with `$THREADS`. MarkDuplicates is single-threaded, and HaplotypeCaller is mostly single-threaded (`--native-pair-hmm-threads` only parallelises one step). Those two take a fixed share of each task that more cores cannot shorten.
- **Payoff.** At 4 cores, all eight tasks fit in half the reservation (32 cores instead of 64), for about 25 s more per task.

## Cohort job (`02_cohort.sbatch`, stages 6–9)

| | --cpus-per-task | --mem | --time |
|---|---|---|---|
| first request | 4 | 16G | 02:00:00 |
| measured (10763583) | <CPU efficiency> → <cores busy> | memory.peak <x GB> · seff <x GB> | <Elapsed> |
| **set to** | <…> | <…> | <…> |

```
<paste: seff 10763583>
<paste: memory.peak line from logs/cohort_10763583.out>
```

**Why.** <CombineGVCFs and GenotypeGVCFs are single-threaded, so cores busy should be ≈1: drop to 2 if seff confirms it. Set --mem to the peak plus ~25 %, and --time to ~2–3× the elapsed time.>
