# IMAGE

## Base image
mambaorg/micromamba:2.0.5-ubuntu24.04
mambaorg/micromamba@sha256:1c62a28916ad7a4533555a542a5410e55ea2ed2c1e29f00c8fc3f1c8add111d5

## Versions pinned
bwa=0.7.19 samtools=1.24 bcftools=1.24 gatk4=4.6.2.0 fastqc=0.12.1 fastp=1.3.7 multiqc=1.35 git=2.47.1

## The pushed image
docker.io/aashisavla/variant-call@sha256:77ca64adc13cd0cae3f45f113cf17d8891c39a84f466ad25d6125c4c2bb93d04

To rerun this pipeline in a year, the recipe is not enough: `containers/Dockerfile` pins the
seven tools and git, but every dependency it does not name (htslib, openjdk, Python, perl and the
rest) would be re-resolved on the day of the rebuild, and the micromamba tag can be moved. What
gives back the exact software is the digest under **The pushed image**: `apptainer pull
docker://aashisavla/variant-call@sha256:…` returns the same bytes for as long as Docker Hub keeps
the image, whatever has happened to the tag `1.0`, to bioconda or to `/scratch` (emptied monthly,
which deletes the `.sif`). The rest of what a rerun needs is the code at the commit recorded as
`git_sha` in `cluster-run-container/manifest.json`, the reference and samplesheet under
`/courses/BINF6610.202710/data/`, and the same `--cpus-per-task` (bwa mem's batching depends on
the thread count). **Base image** and **Versions pinned** say what the image was built from; if
the pushed image is ever deleted, they are the starting point for a rebuild that is close but not
byte-identical.
