# containers/Dockerfile — the pipeline's software, pinned to the course conda environment.
#
# Build for Explorer's CPU (amd64), even on an Apple Silicon laptop:
#   docker build --platform linux/amd64 -t aashisavla/variant-call:1.0 containers/
#
# Versions are the course environment's (conda env export -p /courses/BINF6610.202710/shared/env/binf6610).
# git is not in that environment: stage 9 needs it for the manifest's git_sha.
FROM mambaorg/micromamba:2.0.5-ubuntu24.04

RUN micromamba install --yes --name base --channel conda-forge --channel bioconda \
        bwa=0.7.19 \
        samtools=1.24 \
        bcftools=1.24 \
        gatk4=4.6.2.0 \
        fastqc=0.12.1 \
        fastp=1.3.7 \
        multiqc=1.35 \
        git=2.47.1 \
    && micromamba clean --all --yes

# apptainer exec does not run the micromamba entrypoint, so put the env on PATH directly.
ENV PATH=/opt/conda/bin:$PATH
