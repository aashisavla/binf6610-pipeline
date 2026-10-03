#!/bin/bash -l
# 02_cohort.sbatch — stages 6–9, once, after every array task has succeeded.
# submit.sh submits it with --dependency=afterok:<array id> --kill-on-invalid-dep=yes.
# The software comes from the image at ${SIF} (slurm/pull.sbatch), not from conda.
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
[[ -s "${SIF}" ]] || { echo "no image at ${SIF}: run sbatch pull.sbatch first" >&2; exit 66; }

export THREADS="${SLURM_CPUS_PER_TASK}"
export TMPDIR="/tmp/${SLURM_JOB_ID}"
export FROM_STAGE=merge                  # stages 1–5 ran in the array; stage 0 always runs
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "cohort: on $(hostname), ${THREADS} cpus, run dir ${RUN_ROOT}, image ${SIF}" >&2
apptainer exec --cleanenv \
    --env THREADS="${THREADS}" \
    --env TMPDIR="${TMPDIR}" \
    --env FROM_STAGE="${FROM_STAGE}" \
    --env SLURM_JOB_ID="${SLURM_JOB_ID}" \
    --env SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}" \
    --bind /courses/BINF6610.202710,/scratch/${USER} \
    "${SIF}" \
    bash "${PIPELINE_DIR}/run_pipeline.sh" "${SAMPLESHEET}" "${RUN_ROOT}"
