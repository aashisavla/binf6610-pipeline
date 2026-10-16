# TROUBLESHOOTING

## Week 5: four failures caused on purpose

Weeks 1–4's entries are in this file's Git history (week 4's: commit `5e5ffb6`).

### 1 · Ctrl-C halfway through a laptop smoke run, then the same command

**Command.** The command was `snakemake --profile profiles/laptop --config samplesheet=$HOME/smoke/samplesheet.csv ref=$HOME/smoke/smoke.fa region=smoke_1mb`, started from an empty `work/` and `results/`.
- My first two tries finished (21 of 21 jobs in about 80 s) before I could press Ctrl-C.
- So the third time I ran it in the background and sent it SIGINT, which is what Ctrl-C sends, 3 s after `rule bwa_mem` appeared in its output.

**What it printed when interrupted** (exit 1, after 30 s):
```
Shell command: fastp -w 4 -i /Users/aashisavla/smoke/smoke_01_R1.fastq.gz -I /Users/aashisavla/smoke/smoke_01_R2.fastq.gz -o work/trim/smoke_01_R1.trim.fastq.gz ...
Select jobs to execute...
Terminating processes on user request, this might take some time.
Elapsed time: 0:00:29.862509
WorkflowError:
At least one job did not complete successfully.
```

**The same command again:**
```
Building DAG of jobs...
IncompleteFilesException:
The files below seem to be incomplete. If you are sure that certain files are not incomplete, mark them as complete with

    snakemake --cleanup-metadata <filenames>

To re-generate the files rerun your command with the --rerun-incomplete flag.
Incomplete files:
work/trim/smoke_01_R1.trim.fastq.gz
work/trim/smoke_01_R2.trim.fastq.gz
work/trim/smoke_01.fastp.json
work/trim/smoke_01.fastp.html
```

**What Snakemake said, and why.** It refused to start. smoke_01's fastp job was writing when the interrupt arrived, and Snakemake had marked its four outputs as in progress. Files that exist but were cut off would otherwise be trusted as finished.

**The option it told me to add:** `--rerun-incomplete`. Alternatively, `--cleanup-metadata <filenames>` marks files complete, if I'm sure they are.

**How many jobs ran then.** With `snakemake --profile profiles/laptop --rerun-incomplete --config …`:
```
job                count
bwa_mem                2
fastp_paired           1
markduplicates         3
haplotypecaller        3
multiqc                1
joint_genotype         1
filter                 1
publish                1
all                    1
total                 14
...
14 of 14 steps (100%) done
Elapsed time: 0:00:53.066053
```
- **Ran (14 of 21):** smoke_01's incomplete fastp, plus everything downstream of it and of the alignment that had not finished.
- **Reused (7):** validate, fastqc ×3, fastp for smoke_02 and smoke_03, and bwa_mem for the one sample that had finished aligning.

**Fix.** `--rerun-incomplete` regenerates exactly the files that were cut off.

### 2 · `log: "logs/bwa_mem.log"` in the stage-3 rule, without `{sample}`, then `snakemake -n`

**Command:**
```
sed -i '' 's|"logs/bwa_mem/{sample}.log"|"logs/bwa_mem.log"|' Snakefile
snakemake --profile profiles/laptop -n --config samplesheet=$HOME/smoke/samplesheet.csv ref=$HOME/smoke/smoke.fa region=smoke_1mb
```

**What it printed:**
```
RuleException in file "/Users/aashisavla/binf6610-pipeline/Snakefile", line 154:
Not all output, log and benchmark files of rule bwa_mem contain the same wildcards. This is crucial though, in order to avoid that two or more jobs write to the same file.
```

**Why Snakemake refuses it.**
- bwa_mem runs once per sample, and `{sample}` in its output is what tells the three jobs apart.
- A log without `{sample}` would be the same file, `logs/bwa_mem.log`, for all three jobs. Jobs running at the same time would overwrite each other's log, and a failed job's error could be overwritten by a successful one.
- Snakemake checks this when it reads the Snakefile, before planning any job, even in a dry run.

**Fix.** `log: "logs/bwa_mem/{sample}.log"`, restored with `git checkout -- Snakefile`.

### 3 · Both `wildcard_constraints:` deleted from the stage-2 rules, then `snakemake -n`

**Command:**
```
sed -i '' '/wildcard_constraints:/,+1d' Snakefile
snakemake --profile profiles/laptop -n --config samplesheet=$HOME/smoke/samplesheet.csv ref=$HOME/smoke/smoke.fa region=smoke_1mb
```

**What it printed:**
```
AmbiguousRuleException:
Rules fastp_single and fastp_paired are ambiguous for the file work/trim/smoke_01_R1.trim.fastq.gz.
Consider starting rule output with a unique prefix, constrain your wildcards, or use the ruleorder directive.
Wildcards:
fastp_single: sample=smoke_01
fastp_paired: sample=smoke_01
Expected output files:
fastp_single: work/trim/smoke_01_R1.trim.fastq.gz work/trim/smoke_01.fastp.json work/trim/smoke_01.fastp.html
fastp_paired: work/trim/smoke_01_R1.trim.fastq.gz work/trim/smoke_01_R2.trim.fastq.gz work/trim/smoke_01.fastp.json work/trim/smoke_01.fastp.html
```

**The exception:** `AmbiguousRuleException`.

**The two rules it names:** `fastp_single` and `fastp_paired`.

**The file it names:** `work/trim/smoke_01_R1.trim.fastq.gz`.
- The two rules share output names on purpose, so that bwa_mem's input can be the same pattern for every sample.
- Without the constraints, both rules match `{sample}=smoke_01`, and Snakemake will not guess which one should make the file.
- It names smoke_01 because that is the first sample whose R1 it needed. smoke_01 is paired, so `fastp_single` would even have been given its R2 as a second input.

**Fix.** `wildcard_constraints: sample=one_of(PAIRED)` and `one_of(SINGLE)`, restored with `git checkout -- Snakefile`. Each sample then matches exactly one rule, decided by `library_type` in the samplesheet.

### 4 · `software-deployment-method: apptainer` deleted from `profiles/explorer/profile.yaml`, first Explorer run

**Command.** Deleted the line (not committed), then `sbatch slurm/snakemake.sbatch` as head job 11147638.

**What the head job printed** (`slurm/variant-call-smk-11147638.out`), 16 times:
```
Error in rule fastp_single:
    message: SLURM-job '11147710' failed, SLURM status is: 'FAILED'. Reason: Unknown.For further error details see the cluster/cloud log and the log files of the involved rule(s).
    log: logs/fastp/NA12892.log, /home/savla.aas/binf6610-pipeline/.snakemake/slurm_logs/rule_fastp_single/NA12892/11147710.log (check log file(s) for error details)
...
Exiting because a job execution failed. Look above for error messages
Elapsed time: 0:05:28.492350
```

**Which rules failed:** every one that needs a bioinformatics tool. That was fastqc ×8, fastp_paired ×6 and fastp_single ×2, 16 Slurm jobs, all FAILED.

**The exit status**, from that job's Slurm log, `.snakemake/slurm_logs/rule_fastp_single/NA12892/11147710.log`:
```
78:Command 'set -euo pipefail;  fastp -w 8 -i /courses/BINF6610.202710/data/fastq-variant/NA12892_R1.fastq.gz -o work/trim/NA12892_R1.trim.fastq.gz ... 2> logs/fastp/NA12892.log' returned non-zero exit status 127.
95:srun: error: c0638: task 0: Exited with exit code 1
```
`sacct -X -j 11147710`:
```
JobID                               JobName      State    Elapsed ExitCode
11147710     4b3856b6-13a9-49a7-a9f6-e60cc+     FAILED   00:00:08      1:0
```
- The command exited **127**, bash's code for "command not found".
- sacct shows **1:0** because Snakemake, running inside the job, caught the 127 and exited with its own status 1. The head job's log only says "FAILED, Reason: Unknown", so the job's own log is where the cause is.

**What the rule's own log says** (`logs/fastp/NA12892.log`):
```
/usr/bin/bash: line 1: fastp: command not found
```

**Why.**
- Without `software-deployment-method: apptainer`, Snakemake ignores every rule's `container:` line and runs the command directly on the compute node.
- The head job's environment (`binf6610-workflows`) has Snakemake and cwltool, but not fastp, fastqc, bwa or gatk. Those exist only inside the images.

**What did not fail: validate.**
- It finished: `work/validate/samplesheet.csv` was written at 18:41.
- Its script needs only bash, gzip and awk, which every compute node has. It ran on the bare node and passed.

**Fix.** Put the line back (`git checkout -- profiles/explorer/profile.yaml`) and submitted the same head job again (11148301).

**Did validate run again?** Yes. `snakemake -n` gave the reason:
```
rule validate:
    output: work/validate/samplesheet.csv
    reason: Software environment definition has changed since last execution
```
validate's output existed and its inputs had not changed. But Snakemake records the software each job ran with, and this time the rule runs in its `tools` image instead of on the bare node. So it does not trust the earlier output. The resubmission planned all 46 jobs:
```
validate 1, fastp_paired 6, fastp_single 2, fastqc 8, bwa_mem 8, markduplicates 8,
haplotypecaller 8, multiqc 1, joint_genotype 1, filter 1, publish 1, all 1 — total 46
```
