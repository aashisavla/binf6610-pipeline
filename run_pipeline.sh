#!/usr/bin/env bash
# run_pipeline.sh — every sample, stages 0–9 (BINF6610 germline variant calling).
#
# usage:  run_pipeline.sh <samplesheet.csv> <outdir> [last_stage]
# stages: validate qc_raw trim align postprocess quantify merge analyze qc_report publish
#
# FROM_STAGE=<name> skips ahead after stage 0 (the cohort job uses FROM_STAGE=merge,
# once the array has produced every sample's GVCF). Stage 0 always runs.
#
# Laptop smoke run:
#   cd smoke && REF=$PWD/smoke.fa REGION=smoke_1mb bash ~/repo/run_pipeline.sh samplesheet.csv ~/smoke-out
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=${RUN_STARTED:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}

source "${HERE}/lib/common.sh"
for f in "${HERE}"/stages/*.sh; do source "$f"; done

usage() {
    printf 'usage: %s <samplesheet.csv> <outdir> [last_stage]\nstages: %s\n' "$0" "${STAGES[*]}" >&2
    exit 2
}
if [[ $# -lt 2 || $# -gt 3 ]]; then usage; fi
SHEET=$1
LAST=${3:-publish}
FROM_STAGE=${FROM_STAGE:-validate}

LAST_IDX=$(stage_index "$LAST")
FIRST_IDX=$(stage_index "$FROM_STAGE")
if (( LAST_IDX < 0 ));  then die "unknown stage '$LAST' (expected one of: ${STAGES[*]})"; fi
if (( FIRST_IDX < 0 )); then die "unknown FROM_STAGE '$FROM_STAGE'"; fi
if (( FIRST_IDX > LAST_IDX )); then die "FROM_STAGE '$FROM_STAGE' comes after last stage '$LAST'"; fi

setup_out "$2"
log "run_pipeline: sheet=$SHEET outdir=$OUT stages=${STAGES[FIRST_IDX]}..$LAST threads=$THREADS REF=$REF REGION=$REGION"
run_stages "$FIRST_IDX" "$LAST_IDX"
log "run_pipeline: finished through stage '$LAST'"
