#!/usr/bin/env bash
# stage 5 — quantify: per-sample HaplotypeCaller in GVCF mode, restricted to REGION.
set -euo pipefail

stage_quantify() {
    local d=$OUT/05_quantify p=$OUT/04_postprocess i id
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        id=${IDS[i]}
        log "quantify: '$id' HaplotypeCaller -ERC GVCF -L $REGION"
        gatk_ HaplotypeCaller -R "$REF" -I "$p/$id.dedup.bam" -O "$d/$id.g.vcf.gz" \
              -ERC GVCF -L "$REGION" --native-pair-hmm-threads "$THREADS"
        need_file "$d/$id.g.vcf.gz" "quantify '$id'"
    done
}
