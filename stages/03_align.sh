#!/usr/bin/env bash
# stage 3 — align: BWA-MEM to REF with a read group whose SM is the sample_id; sort.
set -euo pipefail

stage_align() {
    local d=$OUT/03_align t=$OUT/02_trim i id r1 r2 bam n
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        id=${IDS[i]}; bam=$d/$id.sorted.bam
        r1=$t/$id.trim_R1.fastq.gz; r2=""
        if [[ ${LIBS[i]} == paired ]]; then r2=$t/$id.trim_R2.fastq.gz; fi
        log "align: '$id' with $THREADS threads"
        bwa mem -t "$THREADS" -R "@RG\tID:${id}\tSM:${id}" "$REF" "$r1" ${r2:+"$r2"} 2>"$d/$id.bwa.log" \
            | samtools sort -@ "$THREADS" -T "${TMPDIR:-/tmp}/$id.sort" -o "$bam" -
        if ! samtools quickcheck "$bam"; then die "align '$id': $bam failed samtools quickcheck"; fi
        n=$(samtools view -@ "$THREADS" -c -F 4 "$bam")
        if (( n == 0 )); then die "align '$id': no mapped reads in $bam (see $d/$id.bwa.log)"; fi
        log "align: '$id' $n mapped reads"
    done
}
