#!/usr/bin/env bash
# stage 1 — qc_raw: FastQC on the raw reads.
set -euo pipefail

stage_qc_raw() {
    local d=$OUT/01_qc_raw i
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        log "qc_raw: '${IDS[i]}'"
        fastqc -q -t "$THREADS" -o "$d" "${R1S[i]}" ${R2S[i]:+"${R2S[i]}"} >&2
    done
    if ! ls "$d"/*_fastqc.zip >/dev/null 2>&1; then die "qc_raw: no FastQC output in $d"; fi
}
