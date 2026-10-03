#!/bin/bash -l
# 01_persample.sbatch — stages 0–5 for ONE sample, as one task of the array.
# Task N runs row N of the samplesheet. Submit with submit.sh, from slurm/.
# The software comes from the image at ${SIF} (slurm/pull.sbatch), not from conda.
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
[[ -s "${SIF}" ]] || { echo "no image at ${SIF}: run sbatch pull.sbatch first" >&2; exit 66; }

export THREADS="${SLURM_CPUS_PER_TASK}"
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "task ${SLURM_ARRAY_TASK_ID}: sample '${SAMPLE}' on $(hostname), ${THREADS} cpus, run dir ${RUN_ROOT}, image ${SIF}" >&2
apptainer exec --cleanenv \
    --env THREADS="${THREADS}" \
    --env TMPDIR="${TMPDIR}" \
    --env SLURM_JOB_ID="${SLURM_JOB_ID}" \
    --env SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}" \
    --bind /courses/BINF6610.202710,/scratch/${USER} \
    "${SIF}" \
    bash "${PIPELINE_DIR}/run_sample.sh" "${SAMPLESHEET}" "${RUN_ROOT}" "${SAMPLE}"
