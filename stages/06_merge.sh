#!/usr/bin/env bash
# stage 6 — merge: joint genotyping across every sample (CombineGVCFs, GenotypeGVCFs).
set -euo pipefail

stage_merge() {
    local d=$OUT/06_merge g=$OUT/05_quantify i
    local -a vargs=()
    mkdir -p "$d"
    # Every sample in the sheet must have its GVCF: never genotype a partial cohort.
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        need_file "$g/${IDS[i]}.g.vcf.gz" "merge: GVCF for sample '${IDS[i]}'"
        vargs+=(-V "$g/${IDS[i]}.g.vcf.gz")
    done
    log "merge: CombineGVCFs over ${#IDS[@]} sample(s)"
    gatk_ CombineGVCFs -R "$REF" -L "$REGION" "${vargs[@]}" -O "$d/cohort.g.vcf.gz"
    log "merge: GenotypeGVCFs"
    gatk_ GenotypeGVCFs -R "$REF" -L "$REGION" -V "$d/cohort.g.vcf.gz" -O "$d/cohort.vcf.gz"
    need_file "$d/cohort.vcf.gz" merge
    log "merge: $(count_records "$d/cohort.vcf.gz") joint-genotyped records"
}
