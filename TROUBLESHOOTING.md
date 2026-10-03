# TROUBLESHOOTING

## Week 3: four failures caused on purpose, and three that weren't

Image: `docker.io/aashisavla/variant-call@sha256:77ca64adc13cd0cae3f45f113cf17d8891c39a84f466ad25d6125c4c2bb93d04`, pulled to `/scratch/savla.aas/containers/variant-call.sif` by job 10773634 (COMPLETED, 3:26). Each test run used its own `TAG`, so it wrote to `/scratch/savla.aas/w3-run-<TAG>` and never touched the real run (array 10773637, cohort 10773638).

### 1 · Unpinned recipe: `FROM ubuntu` + bare `apt-get install`, rebuilt with `--pull --no-cache`

Command, in `~/unpinned-test` on the laptop (outside the repo):
```
# Dockerfile:  FROM ubuntu
#              RUN apt-get update && apt-get install -y curl
docker build -t unpinned:day1 .                    # Fri Oct  2 20:39:46 EDT 2026
docker run --rm unpinned:day1 dpkg -l > day1.txt   # 122 lines
docker build --pull --no-cache -t unpinned:day2 .  # Fri Oct  2 21:26:22 EDT 2026
docker run --rm unpinned:day2 dpkg -l > day2.txt
diff day1.txt day2.txt; echo "diff exit: $?"
```
Output:
```
#5 [1/2] FROM docker.io/library/ubuntu:latest@sha256:3595d7fc4286a33fad0fd853a4063e654287a9c3787437d7937c94ca3f7a804e
diff exit: 0
day 1 ubuntu:latest  sha256:3595d7fc4286a33fad0fd853a4063e654287a9c3787437d7937c94ca3f7a804e
day 2 ubuntu:latest  sha256:3595d7fc4286a33fad0fd853a4063e654287a9c3787437d7937c94ca3f7a804e
```

**Aimed at vs got.** I aimed at two package lists that differ. I got identical lists (`diff` exit 0, no lines differ).

**Why.** The assignment was set on the day it was due, so the two builds are 47 minutes apart, not a day. In that window `ubuntu:latest` still pointed at the same digest (`3595d7fc…804e` both times), and the Ubuntu archive published no new versions of the packages `curl` pulls in.

**What the experiment shows.** `--pull --no-cache` did redo both steps: the FROM was re-resolved and `apt-get` ran again. It only reproduced day 1 because nothing upstream had moved yet. The recipe itself pins nothing, so the next time Canonical moves `latest` or updates any of these packages, the same command builds a different image. The 14-day comparison on the slides found 57 packages different.

**Fix.** That is what `containers/Dockerfile` does:
- `FROM mambaorg/micromamba:2.0.5-ubuntu24.04`: a tag, not `latest`.
- Every tool written as `name=version`.
- No `apt-get` at all.
- The image used is pinned by its digest (IMAGE.md).

### 2 · `--bind` removed from `01_persample.sbatch`, one sample

Command: deleted the `--bind /courses/BINF6610.202710,/scratch/${USER}` line, then `AFTER=10773634 TAG=nobind ARRAY=1 NO_COHORT=1 bash slurm/submit.sh`, then `git checkout -- slurm/01_persample.sbatch`.
```
10773639_1      w2-persample-nobind     FAILED   00:00:11      1:0
task 1: sample 'NA12878' on c0617, 4 cpus, run dir /scratch/savla.aas/w3-run-nobind, image /scratch/savla.aas/containers/variant-call.sif
mkdir: cannot create directory '/scratch': Read-only file system
```

**Where it stopped.** Immediately, before stage 0, exit code 1 after 11 s.

**What it couldn't see.** `/scratch`. `run_sample.sh` begins by creating the run directory `/scratch/savla.aas/w3-run-nobind`. Without the bind, `/scratch` does not exist inside the container, and the image's root filesystem is read-only, so `mkdir -p` failed and `set -e` ended the task.

**What else would have failed.** `/courses/BINF6610.202710` (samplesheet, FASTQs, reference) was also invisible, but the run never got that far. What the container did see was its default binds: `$HOME` (the code, so `run_sample.sh` itself started) and `/tmp`.

**Fix.** Restore `--bind /courses/BINF6610.202710,/scratch/${USER}`.

### 3 · `--env THREADS=…` removed from `01_persample.sbatch`, one sample on 8 cores

Command: deleted the `--env THREADS="${THREADS}"` line, then `AFTER=10773634 TAG=nothreads ARRAY=1 NO_COHORT=1 PERSAMPLE_CPUS=8 bash slurm/submit.sh`, then `git checkout`.
```
10773640_1   w2-persample-nothreads  COMPLETED   00:08:50          8      0:0
[main] CMD: bwa mem -t 4 -R @RG\tID:NA12878\tSM:NA12878 /courses/…/GRCh38_full_analysis_set_plus_decoy_hla.fa /scratch/savla.aas/w3-run-nothreads/02_trim/NA12878.trim_R1.fastq.gz …
```
For comparison, the real run (array 10773637, same sample, same 8 cores, with `--env THREADS`):
```
[main] CMD: bwa mem -t 8 -R @RG\tID:NA12878\tSM:NA12878 /courses/…/GRCh38_full_analysis_set_plus_decoy_hla.fa /scratch/savla.aas/w3-run/02_trim/NA12878.trim_R1.fastq.gz …
```

**What happened.** The job held 8 cores, and BWA used 4. `--cleanenv` stopped `THREADS` at the container boundary, so `lib/common.sh` fell back to its default `THREADS=${THREADS:-4}`, and every tool (bwa, samtools, fastp, HaplotypeCaller) got 4.

**Why it matters.** Nothing failed: the state is COMPLETED, exit 0, and the results are valid. Only the `[main] CMD:` line in the BWA log shows that half the reserved cores sat idle.

**Fix.** Carry every variable the job sets and the pipeline reads with `--env`. That is `THREADS` and `TMPDIR` (plus `FROM_STAGE` in the cohort job), and `SLURM_JOB_ID` and `SLURM_CPUS_PER_TASK` for the manifest.

### 4 · `apptainer pull --arch arm64` on Explorer, then run it

Command, on compute node c0584 (interactive job 10773679):
```
export APPTAINER_CACHEDIR=/scratch/$USER/apptainer-cache
apptainer pull --force --arch arm64 arm.sif docker://ubuntu:24.04; echo "pull exit: $?"
apptainer exec arm.sif cat /etc/os-release; echo "run exit: $?"
```
Output:
```
INFO:    Creating SIF file...
pull exit: 0
FATAL:   While checking container encryption: could not open image /scratch/savla.aas/arm.sif: the image's architecture (arm64) could not run on the host's (amd64)
run exit: 255
```

**Pull vs run.** The pull succeeded: Apptainer downloaded and converted an arm64 image onto an amd64 node without complaint, producing a 29 MB `arm.sif`. Only running it failed, with exit 255. `apptainer inspect` on the file printed nothing either; the same architecture check stops it.

**Fix.** Build for the cluster's CPU: `docker build --platform linux/amd64 …`. Then check `docker image inspect --format '{{.Architecture}}'` prints `amd64` before pushing. My image does.

### 5 · Not on purpose: the amd64 build aborted under Rosetta (`exit code: 134`)

```
14.84 Transaction starting
14.85 Unexpected error 9 on netlink descriptor 19.
14.86 bash: line 1:     7 Aborted                 micromamba install --yes --name base …
ERROR: failed to build: … did not complete successfully: exit code: 134
```

**Symptom.** The first `docker build --platform linux/amd64` on the Apple Silicon laptop solved all 166 packages, at the right pinned versions, then aborted as soon as the transaction started.

**How I found it.** The solve output proved the pins resolved, so the failure was in the install step itself. The one error line is from micromamba querying network interfaces over netlink. Docker Desktop was emulating amd64 with Rosetta (on by default), and Rosetta does not support that netlink call.

**Fix.** Turned Rosetta off, so Docker uses QEMU instead. The window was hidden, so I set `"UseVirtualizationFrameworkRosetta": false` in `~/Library/Group Containers/group.com.docker/settings-store.json` and restarted Docker. The same build then finished in 190.9 s, and `docker image inspect --format '{{.Architecture}}'` printed `amd64`.

### 6 · Not on purpose: `multiqc --version` segfaulted inside the image on the laptop

```
fastp 1.3.7
qemu: uncaught target signal 11 (Segmentation fault) - core dumped
bash: line 4:   121 Segmentation fault      multiqc --version
```

**Cause.** QEMU, not the image. multiqc 1.35 loads `polars`, whose compiled runtime uses CPU instructions QEMU's amd64 emulation does not handle.

**Evidence.**
- `ls /opt/conda/conda-meta | grep ^multiqc-` showed `multiqc-1.35-pyhdfd78af_2.json`, so the right version was installed.
- On Explorer's real amd64 CPU, the same image ran `multiqc --version` and printed `1.35` (see `cluster-run-container/versions-image.txt`).

**Fix.** None needed in the image. Version checks belong on the target architecture.

### 7 · Not on purpose: no `tests/print_versions.sh` to run

The brief's step 8 runs `tests/print_versions.sh` "from this archive". I could not find a week-3 tests archive on Canvas, and the manifest page says there is nothing to download this week. So `tests/print_versions.sh` in this repository is a stand-in:
- One line per tool, `<tool> <version>`.
- The version parsers are copied from the course's `lib/write_manifest.sh`.

Run on compute node c0584, in the course environment and then inside the image with `apptainer exec --cleanenv`, the two outputs are identical: `diff` prints nothing, for all seven tools. If the course's script is published, rerunning it is two commands.

---


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
