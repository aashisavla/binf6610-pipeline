#!/bin/bash
#SBATCH --job-name=variant-call-smk
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=12:00:00
#SBATCH --output=slurm/%x-%j.out
#
# The head job: Snakemake itself. It submits every rule as its own Slurm job and
# runs only the local rule, publish. Submit it from the repository's top folder:
#   mkdir -p slurm && sbatch slurm/snakemake.sbatch
set -euo pipefail

module load miniconda3/25.9.1
source activate /courses/BINF6610.202710/shared/env/binf6610-workflows

export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache

cd "${SLURM_SUBMIT_DIR}"
snakemake --profile profiles/explorer \
    --config samplesheet=/courses/BINF6610.202710/data/samplesheet-variant8.csv \
             ref=/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa \
             region=chr20:1-10000000 \
             outdir=results
