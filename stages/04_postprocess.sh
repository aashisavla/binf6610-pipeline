#!/usr/bin/env bash
# stage 4 — postprocess: mark duplicates, index, flagstat.
set -euo pipefail

stage_postprocess() {
    local d=$OUT/04_postprocess a=$OUT/03_align i id out
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        id=${IDS[i]}; out=$d/$id.dedup.bam
        log "postprocess: '$id'"
        gatk_ MarkDuplicates -I "$a/$id.sorted.bam" -O "$out" -M "$d/$id.dup_metrics.txt"
        samtools index -@ "$THREADS" "$out"
        samtools flagstat -@ "$THREADS" "$out" > "$d/$id.flagstat.txt"
        if ! samtools quickcheck "$out"; then die "postprocess '$id': $out failed quickcheck"; fi
        need_file "$out.bai" "postprocess '$id'"
    done
}
