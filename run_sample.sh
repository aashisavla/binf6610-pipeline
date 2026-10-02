#!/usr/bin/env bash
# run_sample.sh — ONE sample, stages 0–5. An array task calls this for its row.
#
# usage:  run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last_stage]
#
# Declines stages 6–9: they need every sample at once, and a task that ran them
# would write a one-sample "cohort", once per task, each overwriting the last.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=${RUN_STARTED:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}

source "${HERE}/lib/common.sh"
for f in "${HERE}"/stages/*.sh; do source "$f"; done

usage() {
    printf 'usage: %s <samplesheet.csv> <outdir> <sample_id> [last_stage]\nstages: %s (per sample: up to %s)\n' \
        "$0" "${STAGES[*]}" "$LAST_PER_SAMPLE" >&2
    exit 2
}
if [[ $# -lt 3 || $# -gt 4 ]]; then usage; fi
SHEET=$1
ONLY_SAMPLE=$3
LAST=${4:-$LAST_PER_SAMPLE}

if [[ -z $ONLY_SAMPLE ]]; then die "empty sample_id: refusing to run (an empty name selects nothing)"; fi
LAST_IDX=$(stage_index "$LAST")
MAX_IDX=$(stage_index "$LAST_PER_SAMPLE")
if (( LAST_IDX < 0 )); then die "unknown stage '$LAST' (expected one of: ${STAGES[*]})"; fi
if (( LAST_IDX > MAX_IDX )); then
    die "run_sample.sh runs stages 0-${MAX_IDX} only; '$LAST' needs every sample at once — use run_pipeline.sh"
fi

setup_out "$2"
log "run_sample: sample='$ONLY_SAMPLE' sheet=$SHEET outdir=$OUT last=$LAST threads=$THREADS REF=$REF REGION=$REGION"
run_stages 0 "$LAST_IDX"
log "run_sample: '$ONLY_SAMPLE' finished through stage '$LAST'"
