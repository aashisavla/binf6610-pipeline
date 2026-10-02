#!/usr/bin/env bash
# stage 2 — trim: adapter and quality trimming with fastp; layout from library_type.
set -euo pipefail

stage_trim() {
    local d=$OUT/02_trim i id base
    local w=$(( THREADS > 16 ? 16 : THREADS ))    # fastp accepts at most 16 workers
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        id=${IDS[i]}; base=$d/$id
        log "trim: '$id' (${LIBS[i]})"
        if [[ ${LIBS[i]} == paired ]]; then
            fastp -i "${R1S[i]}" -I "${R2S[i]}" \
                  -o "$base.trim_R1.fastq.gz" -O "$base.trim_R2.fastq.gz" \
                  --detect_adapter_for_pe -w "$w" \
                  -j "$base.fastp.json" -h "$base.fastp.html" >&2 2>"$base.fastp.log"
            need_file "$base.trim_R2.fastq.gz" "trim '$id'"
        else
            fastp -i "${R1S[i]}" -o "$base.trim_R1.fastq.gz" -w "$w" \
                  -j "$base.fastp.json" -h "$base.fastp.html" >&2 2>"$base.fastp.log"
        fi
        need_file "$base.trim_R1.fastq.gz" "trim '$id'"
        need_file "$base.fastp.json" "trim '$id'"
    done
}
