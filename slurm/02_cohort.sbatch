#!/bin/bash -l
# 02_cohort.sbatch — stages 6–9, once, after every array task has succeeded.
# submit.sh submits it with --dependency=afterok:<array id> --kill-on-invalid-dep=yes.
#SBATCH --job-name=w2-cohort
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=2
#SBATCH --mem=6G
#SBATCH --time=00:30:00
#SBATCH --export=NONE
#SBATCH --output=logs/cohort_%j.out
set -euo pipefail
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

export THREADS="${SLURM_CPUS_PER_TASK}"
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

set +u                                   # conda's activate scripts read unset variables
module load "${CONDA_MODULE}"
source activate "${CONDA_ENV}"
set -u

echo "cohort: on $(hostname), ${THREADS} cpus, run dir ${RUN_ROOT}" >&2
FROM_STAGE=merge bash "${PIPELINE_DIR}/run_pipeline.sh" "${SAMPLESHEET}" "${RUN_ROOT}"

CG=/sys/fs/cgroup$(awk -F: '/^0::/{print $3}' /proc/self/cgroup)
echo "memory.peak bytes: $(cat "$CG/memory.peak" 2>/dev/null || echo unavailable)" >&2
