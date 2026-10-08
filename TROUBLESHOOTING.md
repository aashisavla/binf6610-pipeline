# TROUBLESHOOTING

## Week 4: four failures caused on purpose

Weeks 1–3's entries are in this file's Git history (commit `48940d2` and earlier).

### 1 · Ctrl-C halfway through a laptop smoke run, then `-resume`

Command:
```
nextflow run main.nf -profile docker \
    --samplesheet ~/smoke/samplesheet.csv --ref ~/smoke/smoke.fa --region smoke_1mb
# Ctrl-C while HAPLOTYPECALLER was running
nextflow run main.nf -profile docker -resume \
    --samplesheet ~/smoke/samplesheet.csv --ref ~/smoke/smoke.fa --region smoke_1mb
```

What it printed when stopped (run `romantic_jepsen`, status ERR):
```
[1f/b046eb] VALIDATE                   | 1 of 1 ✔
[ec/b61fdc] FASTQC (smoke_02)          | 3 of 3 ✔
[2b/d18d2d] FASTP (smoke_01)           | 3 of 3 ✔
[b5/a2622f] BWA_MEM (smoke_02)         | 3 of 3 ✔
[88/e248d7] MARKDUPLICATES (smoke_01)  | 3 of 3 ✔
[ed/c02ea0] HAPLOTYPECALLER (smoke_01) | 0 of 3
[72/ff607e] MULTIQC                    | 0 of 1
WARN: Killing running tasks (4)
```

The resumed run (`extravagant_murdock`, status OK):
```
Duration    : 1m 19s
CPU hours   : 0.1 (44.2% cached)
Succeeded   : 7
Cached      : 13
```
From `nextflow log extravagant_murdock -f name,status,exit,hash`:
```
VALIDATE CACHED 0 1f/b046eb          FASTQC ×3 CACHED          FASTP ×3 CACHED
BWA_MEM ×3 CACHED (b5/a2622f …)      MARKDUPLICATES ×3 CACHED (88/e248d7 …)
HAPLOTYPECALLER ×3 COMPLETED         MULTIQC COMPLETED
JOINT_GENOTYPE COMPLETED             FILTER COMPLETED          PUBLISH COMPLETED
```

**Which tasks were cached:** the 13 that had finished before Ctrl-C. Their work-folder hashes are identical in both runs (`1f/b046eb`, `b5/a2622f`, `88/e248d7`, …), so the same inputs and the same script gave the same task, and Nextflow reused its outputs.

**Which ran again (7):**
- the 4 tasks Ctrl-C killed mid-run: 3 HAPLOTYPECALLER and MULTIQC;
- the 3 that had never started: JOINT_GENOTYPE, FILTER and PUBLISH.

PUBLISH also has `cache false`, so it would rerun anyway.

The same thing happened on Explorer after failure 4: head job 10929846 logged 33 `Cached process` lines (VALIDATE 1, FASTQC 8, FASTP 8, BWA_MEM 8, MARKDUPLICATES 8) and resubmitted only HAPLOTYPECALLER ×8 and what follows it.

**Fix.** Nothing to fix; this is the behaviour to rely on. `-resume` is also in `slurm/nextflow.sbatch`.

### 2 · The reference as a queue channel in the BWA_MEM call

Command, in `main.nf`, then restored with `git checkout -- main.nf`:
```
BWA_MEM(FASTP.out.reads, channel.fromPath(params.ref), ref_index)
nextflow run main.nf -profile docker -ansi-log false --outdir /tmp/nf-break2 \
    --samplesheet ~/smoke/samplesheet.csv --ref ~/smoke/smoke.fa --region smoke_1mb
```
What it printed (run `angry_hirsch`):
```
[f6/2ea488] Submitted process > BWA_MEM (smoke_03)
[99/c5c2a9] Submitted process > MARKDUPLICATES (smoke_03)
[88/83be51] Submitted process > HAPLOTYPECALLER (smoke_03)
[6f/41cee6] Submitted process > JOINT_GENOTYPE
[e3/071af4] Submitted process > FILTER
[75/6773c0] Submitted process > PUBLISH
Outputs:  /tmp/nf-break2  vcf: cohort.filtered.vcf.gz … manifest: manifest.json
$ gzip -dc /tmp/nf-break2/cohort.filtered.vcf.gz | grep -m1 '^#CHROM' | cut -f10-
smoke_03
```

**How many samples BWA_MEM ran:** 1 of 3.
- FASTQC and FASTP ran for all three samples.
- `channel.fromPath(params.ref)` is a queue channel holding one item, so it paired with the first sample's reads to arrive (smoke_03) and was then empty. smoke_01 and smoke_02 had no reference to pair with, so they never aligned.

**What stopped the run: nothing.**
- Every downstream task ran on the one sample, and the run finished with all five outputs.
- The cohort VCF has a single column, `smoke_03`. MultiQC still shows all three samples' FastQC and fastp reports, which makes the run look complete.
- This is a silent failure: only counting the VCF's sample columns shows it.

**Fix.** The reference must be a value, `ref = file(params.ref)` (and `files()` for its indexes), so every sample's task can read it.

### 3 · The backslash taken off `\$(…)` in BWA_MEM's script block

Command, in `modules/bwa_mem.nf`, then restored with `git checkout`:
```
mapped=\$(samtools view -c -F 4 ${meta.id}.sorted.bam)   →   mapped=$(samtools view -c -F 4 ${meta.id}.sorted.bam)
nextflow run main.nf -profile docker -ansi-log false --outdir /tmp/nf-break3 …
```
What it printed (run `gloomy_solvay`):
```
ERROR ~ Error executing process > 'BWA_MEM (smoke_03)'
  Process `BWA_MEM (smoke_03)` terminated with an error exit status (2)
Work dir:  /Users/aashisavla/binf6610-pipeline/work/f5/e5bd42eaf52f38792f70c2278e6b99
WARN: Killing running tasks (4)
```
The task's `.command.sh`, read from that work folder:
```
#!/bin/bash -euo pipefail
...
# Assert on the data, not just the exit code: an empty BAM is a failure.
mapped=smoke_03samtools view -c -F 4 smoke_03.sorted.bam)
(( mapped > 0 )) || { echo "smoke_03: no mapped reads (see .bwa.log)" >&2; exit 1; }
```
Its `.command.err`:
```
/Users/aashisavla/binf6610-pipeline/work/f5/e5bd42eaf52f38792f70c2278e6b99/.command.sh: line 8: syntax error near unexpected token `)'
```
And `bash .command.run` in that folder:
```
.command.sh: line 8: syntax error near unexpected token `)'
bash .command.run exit: 2
```

**What happened.** Nextflow did not stop before the run. It treated the unescaped `$` as the start of a Groovy interpolation and wrote a broken line into `.command.sh`:
- `$(` was replaced: `mapped=smoke_03samtools …`;
- on the next line, `${meta.id}.bwa.log` lost its value and became `.bwa.log`.

Bash only saw the damage when it reached line 8: syntax error, exit 2.

**What `bash .command.run` showed.** It reran the task in the same container and failed identically. The mistake is baked into `.command.sh`, so rerunning the task cannot fix it; only the source can.

**Fix.** Every `$` that bash should see is `\$` inside a script block: `mapped=\$(samtools …)`.

### 4 · `time = '2m'` for HAPLOTYPECALLER on the first Explorer run

Command, in the `explorer` profile of `nextflow.config`, not committed, before the first `sbatch slurm/nextflow.sbatch` (head job 10929646):
```
withName: 'HAPLOTYPECALLER' {
    time = '2m'
}
```
What it printed, in `nf-head-10929646.out`:
```
ERROR ~ Error executing process > 'HAPLOTYPECALLER (NA07357)'
Caused by:
  Process `HAPLOTYPECALLER (NA07357)` terminated with an error exit status (140)
Command exit status:
  140
Work dir:
  /scratch/savla.aas/nextflow_work/60/dae23ae2d515847b6992cb81418c7a
```
`sacct -X -j 10929773,10929774,10929777,10929778 -o JobID,JobName%22,State,Elapsed,Timelimit,ExitCode`:
```
JobID                       JobName      State    Elapsed  Timelimit ExitCode
10929773     nf-HAPLOTYPECALLER_(N+     FAILED   00:01:22   00:02:00     12:0
10929774     nf-HAPLOTYPECALLER_(N+     FAILED   00:01:21   00:02:00     12:0
10929777     nf-HAPLOTYPECALLER_(N+     FAILED   00:01:12   00:02:00     12:0
10929778     nf-HAPLOTYPECALLER_(N+     FAILED   00:01:12   00:02:00     12:0
```
The last lines of the task's `.command.log`, where GATK stopped:
```
23:30:09.707 INFO  ProgressMeter -        chr20:1635898              0.8                  8350           9977.1
```

**The exit status Nextflow reported:** 140, which is 128 + 12, the task killed by signal 12 (SIGUSR2).

**sacct:** State FAILED (not TIMEOUT), ExitCode 12:0, Elapsed 1:12–1:22 against a Timelimit of 2:00.
- Nextflow asks Slurm to send it a warning signal before a job's time limit, and stops the task itself when the warning arrives.
- So each job ended 38–48 s before its limit, was recorded as FAILED, and never reached TIMEOUT.
- HaplotypeCaller had got to `chr20:1635898`, about 16 % of the 10 Mb region.

**Fix.** Removed the 2-minute override (`git checkout -- nextflow.config`, back to `time = '1h'` from the `BWA_MEM|HAPLOTYPECALLER` block). Then resubmitted the head job as 10929846: `-resume` reused all 33 tasks up to MARKDUPLICATES and reran HAPLOTYPECALLER ×8 onwards. cpus, memory and time are not part of the task hash, so only the failed tasks, and what follows them, ran again.
