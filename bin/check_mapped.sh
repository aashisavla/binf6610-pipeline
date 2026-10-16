#!/usr/bin/env bash
# check_mapped.sh <bam> <min_percent> — fail unless at least <min_percent> % of the
# BAM's primary reads are mapped. Asserts on the data, not just on bwa's exit code:
# an empty or mostly-unmapped BAM is a failure, not a result.
set -euo pipefail
BAM=${1:?usage: check_mapped.sh <bam> <min_percent>}
MIN=${2:?usage: check_mapped.sh <bam> <min_percent>}
total=$(samtools view -c -F 0x900 "$BAM")
mapped=$(samtools view -c -F 0x904 "$BAM")
if (( total == 0 )); then echo "check_mapped: $BAM has no reads" >&2; exit 1; fi
pct=$(( 100 * mapped / total ))
echo "check_mapped: $BAM: $mapped of $total primary reads mapped ($pct %)" >&2
if (( pct < MIN )); then echo "check_mapped: below the minimum of $MIN %" >&2; exit 1; fi
