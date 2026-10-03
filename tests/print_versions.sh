#!/usr/bin/env bash
# Stand-in for the course's tests/print_versions.sh: one line per tool, "<tool> <version>",
# using the same version parsers as lib/write_manifest.sh.
set -euo pipefail
v() { printf '%s %s\n' "$1" "$( (eval "$2") 2>/dev/null | head -1 || true)"; }
v bwa      "bwa 2>&1 | awk '/^Version/ { print \$2 }'"
v samtools "samtools --version | awk 'NR == 1 { print \$2 }'"
v bcftools "bcftools --version | awk 'NR == 1 { print \$2 }'"
v gatk4    "gatk --version 2>&1 | awk '/Toolkit/ { sub(/^v/, \"\", \$NF); print \$NF }'"
v fastqc   "fastqc --version | awk '{ sub(/^v/, \"\", \$2); print \$2 }'"
v fastp    "fastp --version 2>&1 | awk '{ print \$2 }'"
v multiqc  "multiqc --version | awk '{ print \$NF }'"
