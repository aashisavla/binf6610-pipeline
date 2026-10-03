#!/bin/bash
# pull.sbatch — fetch the pipeline image onto Explorer as a .sif, by digest.
# Converting the image peaks near 8 GiB of memory, so it runs as a job, not on the login node.
#   cd ~/binf6610-pipeline/slurm && mkdir -p logs && sbatch pull.sbatch
#SBATCH -A binf6610.202710 -p courses
#SBATCH -c 4 --mem=16G -t 00:30:00
#SBATCH -o logs/pull-%j.out
set -euo pipefail
export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache   # never the home directory: its quota is fixed
mkdir -p "${APPTAINER_CACHEDIR}" /scratch/${USER}/containers
apptainer pull --force /scratch/${USER}/containers/variant-call.sif \
    docker://aashisavla/variant-call@sha256:77ca64adc13cd0cae3f45f113cf17d8891c39a84f466ad25d6125c4c2bb93d04
