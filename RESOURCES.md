# RESOURCES

Fill every `<…>` from your own `seff` / `sacct` output; paste it verbatim.

## Per-sample job (01_persample.sbatch, stages 0–5)

| | --cpus-per-task | --mem | --time |
|---|---|---|---|
| first request | 8 | 16G | 01:00:00 |
| measured (largest of the 8 tasks) | CPU efficiency <x %>, ≈<cores busy> cores busy | MaxRSS <x G>, memory.peak <x G> | Elapsed <hh:mm:ss> |
| set to | <n> | <x G> | <hh:mm:ss> |

**Why.** <one or two sentences: e.g. peak memory was X, so Y leaves headroom; the slowest task took Z, so the limit is ~2–3× Z; the core-count runs below showed …>

```
<paste: sacct -j <ARRAY_ID> --format=JobID,JobName%22,State,Elapsed,MaxRSS,AllocCPUS>
```
```
<paste: seff <ARRAY_ID>_1>
```

## Cohort job (02_cohort.sbatch, stages 6–9)

| | --cpus-per-task | --mem | --time |
|---|---|---|---|
| first request | 4 | 16G | 02:00:00 |
| measured | <…> | <…> | <…> |
| set to | <…> | <…> | <…> |

**Why.** <…>

```
<paste: seff <COHORT_ID>>
```

## Core-count comparison (same sample, row 1)

Submitted with `TAG=cpuN PERSAMPLE_CPUS=N ARRAY=1 NO_COHORT=1 bash slurm/submit.sh`, N = 2, 4, 8.

| --cpus-per-task | Elapsed | CPU Utilized / wall-clock (cores busy) |
|---|---|---|
| 2 | <…> | <…> |
| 4 | <…> | <…> |
| 8 | <…> | <…> |

```
<paste: sacct -j <id2>,<id4>,<id8> --format=JobID,JobName%22,State,Elapsed,AllocCPUS,MaxRSS>
```

**Decision.** <e.g. 4→8 cores cut wall clock by only X %, so N is the setting: beyond it the extra cores sit mostly idle (HaplotypeCaller and MarkDuplicates are largely single-threaded).>
