# TROUBLESHOOTING

## Week 2: four failures caused on purpose, and one that wasn't

Each test run was submitted with its own `TAG`, so it wrote to `/scratch/$USER/w2-run-<TAG>` and never touched the real run (array 10763575, cohort 10763583).

### 1 · `--time=00:02:00`

Submitted with `TAG=timeout PERSAMPLE_TIME=00:02:00 ARRAY=1 NO_COHORT=1 bash slurm/submit.sh`.

```
10763635_1     w2-persample-timeout    TIMEOUT   00:02:11          8      0:0
[14:02:04] === stage 3: align ===
[14:02:04] align: 'NA12878' with 8 threads
slurmstepd: error: *** JOB 10763635 ON c0662 CANCELLED AT 2026-10-02T14:02:37 DUE TO TIME LIMIT ***
```

**Where it stopped.** It was killed 33 s into stage 3, while BWA was still loading the index.

**What was left on disk.**
- `02_trim/` was complete: both trimmed FASTQs (87,230,844 and 91,236,895 bytes) and the fastp reports.
- `03_align/` held only `NA12878.bwa.log`.
- No partial BAM reached `/scratch`, because `samtools sort` writes its temporary files to `-T ${TMPDIR}` (`/tmp/<jobid>` on the node), which the EXIT trap removes.

**State.** `TIMEOUT`, Elapsed 2:11 (the limit plus Slurm's kill grace period).

### 2 · One task exits 1, cohort job on `afterok`

Submitted with `TAG=fail3 ARRAY=2-3 bash slurm/submit.sh`. Task 3 exits 1 before running anything, because its job name ends in `-fail3`.

```
JobID                       JobName      State ExitCode               Start                 End      Reason
10763637            w2-cohort-fail3  CANCELLED      0:0                None 2026-10-02T14:09:19  Dependency
10763636_2       w2-persample-fail3  COMPLETED      0:0 2026-10-02T14:00:27 2026-10-02T14:09:07        None
10763636_3       w2-persample-fail3     FAILED      1:0 2026-10-02T14:00:27 2026-10-02T14:00:52        None
task 3 (NA12892): deliberate failure (w2-persample-fail3)
```

**What happened to the cohort job.** It never started: it was `CANCELLED` with `Reason=Dependency`.

**When.** Not seconds after task 3 failed (14:00:52), but 12 s after the *last* task ended (task 2, 14:09:07). It stayed PENDING (Dependency) while task 2 was still running. Slurm evaluates `afterok` on an array once every task has finished; only then is the dependency known to be unsatisfiable, and `--kill-on-invalid-dep=yes` cancels it.

**Why not `afterany`.** With `afterany`, the cohort job would have started at 14:09 on one GVCF instead of two. Stage 6 would stop it here, because `merge` calls `need_file` on every sample's GVCF before genotyping. But that is a second line of defence, not the barrier.

### 3 · `--array` past the end of the samplesheet

Submitted with `TAG=range ARRAY=8-9 NO_COHORT=1 bash slurm/submit.sh`. I used 8–9 instead of 1–9 so as not to rerun seven samples for nothing; task 9 is the same either way.

```
10763638_8       w2-persample-range  COMPLETED   00:09:05          8      0:0
10763638_9       w2-persample-range     FAILED   00:00:13          8     64:0
task 9: no row 9 in /courses/BINF6610.202710/data/samplesheet-variant8.csv
```

**What task 9 did.** Its awk lookup returned an empty `SAMPLE`, and the guard in `01_persample.sbatch` exited 64 within 13 s, before the environment was even loaded.

**Without the guard.** `run_sample.sh` also refuses an empty `sample_id`. If both checks were missing, the pipeline itself would treat `ONLY_SAMPLE=""` as "no filter" (that is how `run_pipeline.sh` runs every sample). Task 9 would then process all eight samples, racing tasks 1–8 on the same output files, and still exit 0. That gives nine COMPLETED tasks for eight results, with possibly corrupted BAMs.

### 4 · `scancel` mid-write, then resubmit

Submitted with `TAG=cancel ARRAY=1 NO_COHORT=1 bash slurm/submit.sh`, then `scancel` once the log reached stage 3, then the same command again.

```
10763641_1      w2-persample-cancel CANCELLED+   00:02:03      0:0
10763641_1.+                  batch  CANCELLED   00:02:04     0:15
slurmstepd: error: *** JOB 10763641 ON c0666 CANCELLED AT 2026-10-02T14:02:32 ***
10763685_1      w2-persample-cancel  COMPLETED   00:07:30          8      0:0     (resubmission)
```

**Not quite mid-write.** The cancel landed 44 s into stage 3, when BWA had barely finished loading its index. `03_align/` held only `NA12878.bwa.log`, with no partial BAM, for the same reason as in #1: sort temp files live in `${TMPDIR}`. `02_trim/` was complete, stamped 14:01:48.

**Did the rerun trust what was left?** No.
- After the rerun, every file in `02_trim/` is stamped 14:05:16, so stage 2 ran again. The sizes are identical, so fastp is deterministic here.
- `03_align/NA12878.sorted.bam` (105,849,839 bytes) appeared at 14:06:37.
- The pipeline has no skip-if-exists: every stage rewrites its outputs from its inputs.
- That costs ~3.5 min of repeated trimming, but it is the safe choice. A skip would have to trust a file that `need_file` only checks for being non-empty, and a cancel can leave a truncated file that is non-empty.

### 5 · Not on purpose: every task failed in stage 1 (FastQC `-d`)

```
10763534_1             w2-persample     FAILED   00:00:53      1:0      (all 8 tasks FAILED 1:0)
10763542                  w2-cohort  CANCELLED   00:00:00      0:0
Failed to process /tmp/10763535
java.io.FileNotFoundException: /tmp/10763535 (Is a directory)
```

**Symptom.** All eight tasks of the first submission failed within a minute, and the cohort job was cancelled by `afterok`.

**How it was found.** The log's last stage line was `=== stage 1: qc_raw ===`. Grepping for `exception` showed FastQC trying to open `/tmp/10763535`, the job's own `${TMPDIR}`, as an input file.

**Cause.** I had added `-d "$TMP_ROOT"` to send FastQC's temp files to `${TMPDIR}`. The FastQC on Explorer did not take `-d` as an option with a value, so the path became an input. FastQC exited non-zero, and `set -e` stopped the task.

**Fix.** Removed `-d` (commit `0e4a9a0`; FastQC needs negligible temp space), then resubmitted as 10763575. All eight tasks completed.

---

## Week 1

### 1. Stage 9 would exit 70 on macOS: the system bash is 3.2

**Symptom.** Before the first full run, reading `lib/write_manifest.sh` showed a guard that exits 70 unless `BASH_VERSINFO` ≥ 4.3. `run_acceptance.sh` has the same guard.

**Evidence.** `bash --version` inside the `binf6610` env printed `GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)`. So `bash run_pipeline.sh` and the `bash "${HERE}/lib/write_manifest.sh"` call in stage 9 were both resolving to `/bin/bash`. macOS ships bash 3.2 because later versions are GPLv3.

**Cause.** The env didn't provide its own bash, so `PATH` fell through to the system one.

**Fix.** Ran `conda install -c conda-forge bash` into the env, then `hash -r`. `bash --version` now reports `5.2.37`. The full run then reached stage 9 and wrote `manifest.json`.

`run_pipeline.sh` itself is kept bash-3.2-safe anyway: no `declare -A`, no `mapfile`, no `${x,,}`, and no `"${arr[@]}"` on a possibly-empty array under `set -u`. That way stage 0 still runs if someone launches it with `/bin/bash`.

### 2. `git push` failed: "Repository not found"

**Symptom.** `git push -u origin main` returned `remote: Repository not found`, both before and after pasting a token.

**Evidence.**
- Opening `https://github.com/aashisavla/binf6610-pipeline` in a browser gave a 404. So the problem wasn't authentication: the repository didn't exist.
- Separately, the first `git remote add origin https://github.com/<your-username>/…` had printed `zsh: no such file or directory: your-username`. zsh parses `<` as an input redirection, so that `remote add` never ran.

**Fix.** Created the repository through the GitHub API:
`curl -H "Authorization: token $TOKEN" https://api.github.com/user/repos -d '{"name":"binf6610-pipeline","private":false}'`
The response contained the repo's `html_url`, and the next `git push` succeeded.

### 3. GATK warnings: `libgkl_compression.dylib … incompatible architecture`

**Symptom.** Every GATK step logged `have 'x86_64', need 'arm64'` for the Intel GKL native library, followed by `IntelInflater is not supported, using Java.util.zip.Inflater`.

**Evidence it is harmless.**
- `MergeVcfs` reported `Tool returned: 0`.
- The stage-7 VCF has the columns `smoke_01 smoke_02 smoke_03` (2965 records, 2928 PASS).
- Scored against the wgsim truth files, the share of planted SNVs called non-reference was:

| sample | found | recall |
|---|---|---|
| smoke_01 | 850 / 850 | 100 % |
| smoke_02 | 828 / 829 | 99.9 % |
| smoke_03 (single-end, ~9×) | 798 / 866 | 92.1 % |

**Cause.** GKL ships only an x86_64 dylib, and this is an Apple Silicon Mac, so GATK falls back to Java's zlib. That's slower, not wrong. No fix needed on the laptop; Explorer is x86_64.

### Verification

The manifest's `git_sha` is `b6f1899…` with no `-dirty`: I committed before the run that went into `smoke-run/`. The acceptance suite passes all eight tests that don't need sequencing data.
