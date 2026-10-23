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

# --- week 6: AWS Batch -------------------------------------------------------
# Build from the top of the repository:
#   docker build --platform linux/amd64 -f aws/Dockerfile -t variant-call .

# new: the AWS CLI, copied from AWS's own image
COPY --from=public.ecr.aws/aws-cli/aws-cli:2.37.12 /usr/local/aws-cli /usr/local/aws-cli
USER root
RUN ln -s /usr/local/aws-cli/v2/current/bin/aws /usr/local/bin/aws
USER $MAMBA_USER

# new: the pipeline, and the script the job runs
COPY --chown=$MAMBA_USER:$MAMBA_USER . /pipeline/
COPY --chown=$MAMBA_USER:$MAMBA_USER aws/batch_run.sh /usr/local/bin/batch_run.sh
