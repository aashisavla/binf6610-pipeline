#!/bin/bash -l
# 01_persample.sbatch — stages 0–5 for ONE sample, as one task of the array.
# Task N runs row N of the samplesheet. Submit with submit.sh, from slurm/.
#SBATCH --job-name=w2-persample
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=4
#SBATCH --mem=10G
#SBATCH --time=00:30:00
#SBATCH --export=NONE
#SBATCH --output=logs/persample_%A_%a.out
set -euo pipefail
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

# The array index is the samplesheet row, counting from the first row below the header.
SAMPLE=$(awk -F',' -v n="${SLURM_ARRAY_TASK_ID}" 'NR == n + 1 { print $1 }' "${SAMPLESHEET}")
[[ -n "${SAMPLE}" ]] || { echo "task ${SLURM_ARRAY_TASK_ID}: no row ${SLURM_ARRAY_TASK_ID} in ${SAMPLESHEET}" >&2; exit 64; }

# Deliberate failure for the afterok exercise: TAG=fail3 makes task 3 exit 1.
if [[ ${SLURM_JOB_NAME} == *-fail"${SLURM_ARRAY_TASK_ID}" ]]; then
    echo "task ${SLURM_ARRAY_TASK_ID} (${SAMPLE}): deliberate failure (${SLURM_JOB_NAME})" >&2
    exit 1
fi

export THREADS="${SLURM_CPUS_PER_TASK}"
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

set +u                                   # conda's activate scripts read unset variables
module load miniconda3/25.9.1
source activate "${CONDA_ENV}"
set -u

echo "task ${SLURM_ARRAY_TASK_ID}: sample '${SAMPLE}' on $(hostname), ${THREADS} cpus, run dir ${RUN_ROOT}" >&2
bash "${PIPELINE_DIR}/run_sample.sh" "${SAMPLESHEET}" "${RUN_ROOT}" "${SAMPLE}"

# Exact peak memory of this job (MaxRSS is sampled every 30 s and can miss it).
CG=/sys/fs/cgroup$(awk -F: '/^0::/{print $3}' /proc/self/cgroup)
echo "memory.peak bytes: $(cat "$CG/memory.peak" 2>/dev/null || echo unavailable)" >&2
