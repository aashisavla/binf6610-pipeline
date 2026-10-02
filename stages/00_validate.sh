#!/usr/bin/env bash
# stage 0 — validate: the samplesheet and every input file, before any compute.
# Every problem is collected and reported together; nothing is computed on failure.
set -euo pipefail

check_fastq() {   # <sample_id> <R1|R2> <path>  -> 0 if the file is a complete gzip
    local id=$1 label=$2 f=$3
    if [[ -z $f ]];   then err "sample '$id': $label path is empty"; return 1; fi
    if [[ ! -f $f ]]; then err "sample '$id': $label file not found: $f"; return 1; fi
    if [[ ! -s $f ]]; then err "sample '$id': $label file is empty: $f"; return 1; fi
    if ! gzip -t "$f" 2>/dev/null; then
        err "sample '$id': $label is not a complete gzip stream (truncated or corrupt): $f"
        return 1
    fi
    return 0
}

stage_validate() {
    load_sheet
    local n=${#IDS[@]} i j id lib r1 r2 c1 c2 ok1 ok2 ext dict tool found=0

    if (( n == 0 )); then err "samplesheet has no sample rows: $SHEET"; fi

    for ((i = 0; i < n; i++)); do
        id=${IDS[i]}; r1=${R1S[i]}; r2=${R2S[i]}; lib=${LIBS[i]}

        if [[ -z $id ]]; then err "row $((i + 2)): empty sample_id"; continue; fi
        for ((j = 0; j < i; j++)); do
            if [[ ${IDS[j]} == "$id" ]]; then
                err "sample '$id': duplicate sample_id (rows $((j + 2)) and $((i + 2)))"
            fi
        done
        # One-sample run: every row is checked for duplicates, only ours for files.
        if [[ -n $ONLY_SAMPLE && $id != "$ONLY_SAMPLE" ]]; then continue; fi
        found=1

        log "stage 0: checking sample '$id' ($lib)"
        if [[ $id == */* ]]; then err "sample '$id': sample_id must not contain '/'"; fi

        case $lib in
            paired)
                if [[ -z $r2 ]]; then err "sample '$id': library_type is paired but r2_fastq is empty"; fi ;;
            single)
                if [[ -n $r2 ]]; then
                    log "stage 0: WARNING sample '$id' is single-end; ignoring r2_fastq"
                    R2S[i]=""; r2=""
                fi ;;
            *)
                err "sample '$id': unrecognised library_type '${LIBS[i]}' (expected paired or single)" ;;
        esac

        ok1=0; ok2=0
        if check_fastq "$id" R1 "$r1"; then ok1=1; fi
        if [[ $lib == paired && -n $r2 ]]; then
            if check_fastq "$id" R2 "$r2"; then ok2=1; fi
        fi

        # Assert on the data, not just on exit codes.
        if (( ok1 )); then
            c1=$(gzip -dc "$r1" | wc -l | tr -d ' ')
            if (( c1 == 0 )); then err "sample '$id': R1 contains no reads: $r1"
            elif (( c1 % 4 != 0 )); then err "sample '$id': R1 has $c1 lines, not a multiple of 4: $r1"; fi
            if (( ok2 )); then
                c2=$(gzip -dc "$r2" | wc -l | tr -d ' ')
                if (( c1 != c2 )); then err "sample '$id': R1 has $((c1 / 4)) reads but R2 has $((c2 / 4))"; fi
            fi
        fi
    done

    if [[ -n $ONLY_SAMPLE ]] && (( ! found )); then
        err "sample '$ONLY_SAMPLE' is not in the samplesheet: $SHEET"
    fi

    # Reference and tools are checked only when the run goes past stage 0, so
    # `... validate` works on a laptop where the Explorer REF does not exist.
    if (( LAST_IDX > 0 )); then
        if [[ ! -f $REF ]]; then err "reference not found: $REF (set REF=...)"
        else
            for ext in .fai .bwt; do
                if [[ ! -f $REF$ext ]]; then err "reference index missing: $REF$ext"; fi
            done
            dict=${REF%.*}.dict
            if [[ ! -f $dict ]]; then err "sequence dictionary missing: $dict"; fi
        fi
        for tool in fastqc fastp bwa samtools gatk multiqc; do
            if ! command -v "$tool" >/dev/null 2>&1; then err "tool not on PATH: $tool"; fi
        done
    fi

    if (( ${#ERRORS[@]} > 0 )); then
        log "stage 0: found ${#ERRORS[@]} problem(s):"
        for ((i = 0; i < ${#ERRORS[@]}; i++)); do printf '  - %s\n' "${ERRORS[i]}" >&2; done
        exit 1
    fi

    if [[ -n $ONLY_SAMPLE ]]; then
        subset_to_sample
        log "stage 0: sample '$ONLY_SAMPLE' passed validation"
    else
        log "stage 0: $n sample(s) passed validation"
    fi
}
