#!/usr/bin/env bash
# submit.sh — two sbatch calls and one dependency.
#
#   bash slurm/submit.sh                       the real run: every row, then the cohort job
#
# Optional, one submission at a time (values in front of bash):
#   TAG=x          name the jobs w2-persample-x / w2-cohort-x; they write to /scratch/$USER/w2-run-x
#   ARRAY=1-3      which samplesheet rows to run (default: every row)
#   NO_COHORT=1    submit the array only
#   PERSAMPLE_CPUS / PERSAMPLE_MEM / PERSAMPLE_TIME / COHORT_*   override conf/slurm.env
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"   # sbatch from slurm/, so SLURM_SUBMIT_DIR is slurm/
source conf/slurm.env
mkdir -p logs                         # sbatch does not create the --output folder

N=$(awk -F',' 'NR > 1 && NF { n++ } END { print n + 0 }' "${SAMPLESHEET}")
ARRAY=${ARRAY:-1-${N}}
TAG=${TAG:-}
SUFFIX=${TAG:+-${TAG}}

ARRAY_ID=$(sbatch --parsable -p "${PARTITION}" -A "${ACCOUNT}" \
    --job-name="w2-persample${SUFFIX}" --array="${ARRAY}" \
    --cpus-per-task="${PERSAMPLE_CPUS}" --mem="${PERSAMPLE_MEM}" --time="${PERSAMPLE_TIME}" \
    01_persample.sbatch)
ARRAY_ID=${ARRAY_ID%%;*}
echo "array   ${ARRAY_ID}  w2-persample${SUFFIX}  rows ${ARRAY} of ${N}  ${PERSAMPLE_CPUS} cpus ${PERSAMPLE_MEM} ${PERSAMPLE_TIME}"

if [[ -n ${NO_COHORT:-} ]]; then
    echo "cohort  not submitted (NO_COHORT set)"
    exit 0
fi

COHORT_ID=$(sbatch --parsable -p "${PARTITION}" -A "${ACCOUNT}" \
    --job-name="w2-cohort${SUFFIX}" \
    --cpus-per-task="${COHORT_CPUS}" --mem="${COHORT_MEM}" --time="${COHORT_TIME}" \
    --dependency=afterok:${ARRAY_ID} --kill-on-invalid-dep=yes \
    02_cohort.sbatch)
COHORT_ID=${COHORT_ID%%;*}
echo "cohort  ${COHORT_ID}  w2-cohort${SUFFIX}  afterok:${ARRAY_ID}"
echo "watch:  squeue -u ${USER}    sacct -j ${ARRAY_ID},${COHORT_ID} --format=JobID,JobName%22,State,Elapsed,MaxRSS,AllocCPUS,ExitCode"
