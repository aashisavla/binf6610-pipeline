# variant-call: the ten stages of weeks 1-4 as Snakemake rules, connected by file names.
# Snakemake works backwards from the files rule all asks for.
#
#   snakemake --profile profiles/laptop \
#       --config samplesheet=$HOME/smoke/samplesheet.csv ref=$HOME/smoke/smoke.fa region=smoke_1mb

configfile: "config.yaml"

# A mistyped key on the command line (regoin=) would be added to config without a word.
KNOWN = {"samplesheet", "ref", "region", "outdir", "platform", "executor", "containers"}
unknown = sorted(set(config) - KNOWN)
if unknown:
    raise ValueError(f"unknown config key(s): {', '.join(unknown)}")

import csv
import os
import re

PIPELINE = {"name": "variant-call", "version": "1.0.0"}
OUT = config["outdir"]
BIN = os.path.join(workflow.basedir, "bin")       # bin/ is not on the PATH: call scripts by their path
IMAGES = {name: f"docker://{image}" for name, image in config["containers"].items()}

REF = config["ref"]                                                     # the FASTA
REF_FAI = REF + ".fai"
REF_BWA = [REF + ext for ext in (".amb", ".ann", ".bwt", ".pac", ".sa")]  # bwa's index
REF_DICT = os.path.splitext(REF)[0] + ".dict"                           # smoke.dict, not smoke.fa.dict

SHEET = config["samplesheet"]
with open(SHEET) as fh:
    ROWS = list(csv.DictReader(fh))
SAMPLES = [row["sample_id"] for row in ROWS]
PAIRED = [row["sample_id"] for row in ROWS if row["library_type"] == "paired"]
SINGLE = [row["sample_id"] for row in ROWS if row["library_type"] == "single"]


def resolve(path):
    return path if os.path.isabs(path) else os.path.join(os.path.dirname(SHEET), path)


READS = {
    row["sample_id"]: [resolve(row["r1_fastq"])]
    + ([resolve(row["r2_fastq"])] if row["library_type"] == "paired" else [])
    for row in ROWS
}


def one_of(names):
    """A wildcard pattern matching exactly
    these sample names, or nothing at all."""
    return "|".join(map(re.escape, names)) \
        if names else "(?!)"


def xmx(wildcards, resources):
    """The JVM heap: 80 % of the job's memory, at least 1 GB."""
    mem_mb = getattr(resources, "mem_mb", 2000)
    return max(int(mem_mb * 0.8 / 1024), 1)


def trimmed(wildcards):
    s = wildcards.sample
    if s in PAIRED:
        return [f"work/trim/{s}_R1.trim.fastq.gz", f"work/trim/{s}_R2.trim.fastq.gz"]
    return [f"work/trim/{s}_R1.trim.fastq.gz"]


rule all:
    input:
        f"{OUT}/cohort.filtered.vcf.gz",
        f"{OUT}/variants.tsv",
        f"{OUT}/multiqc_report.html",
        f"{OUT}/samples.tsv",
        f"{OUT}/manifest.json",


# Stage 0 · validate — the samplesheet, every FASTQ and the reference, before any compute.
# Its output is a copy of the samplesheet, made only if the checks pass, and every rule
# that reads FASTQs takes it as an input: no sample starts until the checks have passed.
rule validate:
    input:
        sheet=SHEET,
        fastqs=[fq for reads in READS.values() for fq in reads],
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
        ref_dict=REF_DICT,
    output:
        "work/validate/samplesheet.csv",
    log:
        "logs/validate.log",
    container: IMAGES["tools"]
    shell:
        "({BIN}/validate_samplesheet.sh {input.sheet} {input.ref} {input.ref_dict} && cp {input.sheet} {output}) 2> {log}"


# Stage 1 · qc_raw — FastQC on the reads as they arrived, one folder per sample.
rule fastqc:
    input:
        reads=lambda wc: READS[wc.sample],
        checked=rules.validate.output,
    output:
        directory("work/fastqc/{sample}"),
    log:
        "logs/fastqc/{sample}.log",
    threads: 2
    container: IMAGES["fastqc"]
    shell:
        "(mkdir -p {output} && fastqc -q -t {threads} -o {output} {input.reads}) 2> {log}"


# Stage 2 · trim — the week-1 fastp commands. Paired and single-end samples make
# different files, so stage 2 is two rules, each limited to its own samples.
rule fastp_paired:
    input:
        reads=lambda wc: READS[wc.sample],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        r2="work/trim/{sample}_R2.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(PAIRED),
    log:
        "logs/fastp/{sample}.log",
    threads: 8
    container: IMAGES["fastp"]
    shell:
        "fastp -w {threads} -i {input.reads[0]} -I {input.reads[1]}"
        " -o {output.r1} -O {output.r2} --detect_adapter_for_pe"
        " -j {output.json} -h {output.html} 2> {log}"


rule fastp_single:
    input:
        reads=lambda wc: READS[wc.sample],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(SINGLE),
    log:
        "logs/fastp/{sample}.log",
    threads: 8
    container: IMAGES["fastp"]
    shell:
        "fastp -w {threads} -i {input.reads[0]} -o {output.r1}"
        " -j {output.json} -h {output.html} 2> {log}"


# Stage 3 · align — BWA-MEM into a sorted BAM; the read group's SM is the sample_id.
rule bwa_mem:
    input:
        reads=trimmed,
        ref=REF,
        ref_bwa=REF_BWA,
    output:
        bam="work/align/{sample}.sorted.bam",
    log:
        "logs/bwa_mem/{sample}.log",
    threads: 8
    container: IMAGES["bwa"]
    shell:
        r"""
        (bwa mem -t {threads} -R '@RG\tID:{wildcards.sample}\tSM:{wildcards.sample}' {input.ref} {input.reads} \
            | samtools sort -@ {threads} -T {resources.tmpdir}/{wildcards.sample}.sort -o {output.bam} -) 2> {log}
        samtools quickcheck {output.bam}
        {BIN}/check_mapped.sh {output.bam} 80 2>> {log}
        """


# Stage 4 · postprocess — mark duplicates, index, and alignment statistics for MultiQC.
rule markduplicates:
    input:
        bam="work/align/{sample}.sorted.bam",
    output:
        bam="work/dedup/{sample}.dedup.bam",
        bai="work/dedup/{sample}.dedup.bam.bai",
        metrics="work/dedup/{sample}.dup_metrics.txt",
        flagstat="work/dedup/{sample}.flagstat.txt",
    log:
        "logs/markduplicates/{sample}.log",
    params:
        xmx=xmx,
    container: IMAGES["gatk"]
    shell:
        """
        (gatk --java-options "-Xmx{params.xmx}g -Djava.io.tmpdir={resources.tmpdir}" MarkDuplicates \
            -I {input.bam} -O {output.bam} -M {output.metrics}
         samtools index {output.bam}
         samtools flagstat {output.bam} > {output.flagstat}) 2> {log}
        """


# Stage 5 · quantify — per-sample HaplotypeCaller in GVCF mode, restricted to the region.
rule haplotypecaller:
    input:
        bam="work/dedup/{sample}.dedup.bam",
        bai="work/dedup/{sample}.dedup.bam.bai",
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        gvcf="work/gvcf/{sample}.g.vcf.gz",
        tbi="work/gvcf/{sample}.g.vcf.gz.tbi",
    log:
        "logs/haplotypecaller/{sample}.log",
    params:
        region=config["region"],
        xmx=xmx,
    threads: 8
    container: IMAGES["gatk"]
    shell:
        """
        gatk --java-options "-Xmx{params.xmx}g -Djava.io.tmpdir={resources.tmpdir}" HaplotypeCaller \
            -R {input.ref} -I {input.bam} -O {output.gvcf} \
            -ERC GVCF -L {params.region} --native-pair-hmm-threads {threads} 2> {log}
        """


# Stage 6 · merge — joint genotyping across every sample: CombineGVCFs, then GenotypeGVCFs,
# the same tools as weeks 2-4. Its inputs are every sample's GVCF and index.
rule joint_genotype:
    input:
        gvcfs=expand("work/gvcf/{sample}.g.vcf.gz", sample=SAMPLES),
        tbis=expand("work/gvcf/{sample}.g.vcf.gz.tbi", sample=SAMPLES),
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        vcf="work/joint/cohort.vcf.gz",
        tbi="work/joint/cohort.vcf.gz.tbi",
    log:
        "logs/joint_genotype.log",
    params:
        region=config["region"],
        variants=lambda wc, input: " ".join(f"-V {g}" for g in input.gvcfs),
        xmx=xmx,
    container: IMAGES["gatk"]
    shell:
        """
        (gatk --java-options "-Xmx{params.xmx}g -Djava.io.tmpdir={resources.tmpdir}" CombineGVCFs \
            -R {input.ref} -L {params.region} {params.variants} -O work/joint/cohort.g.vcf.gz
         gatk --java-options "-Xmx{params.xmx}g -Djava.io.tmpdir={resources.tmpdir}" GenotypeGVCFs \
            -R {input.ref} -L {params.region} -V work/joint/cohort.g.vcf.gz -O {output.vcf}) 2> {log}
        """


# Stage 7 · analyze — the GATK Best Practices hard filters, SNPs and indels separately,
# then variants.tsv, one line per record of the filtered VCF.
rule filter:
    input:
        vcf="work/joint/cohort.vcf.gz",
        tbi="work/joint/cohort.vcf.gz.tbi",
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        vcf=f"{OUT}/cohort.filtered.vcf.gz",
        tbi=f"{OUT}/cohort.filtered.vcf.gz.tbi",
        table=f"{OUT}/variants.tsv",
    log:
        "logs/filter.log",
    params:
        xmx=xmx,
    container: IMAGES["gatk"]
    shell:
        r"""
        G="gatk --java-options -Xmx{params.xmx}g"
        mkdir -p work/filter
        (
        $G SelectVariants -R {input.ref} -V {input.vcf} --select-type-to-include SNP -O work/filter/snps.vcf.gz
        $G SelectVariants -R {input.ref} -V {input.vcf} --select-type-to-include INDEL \
            --select-type-to-include MIXED -O work/filter/indels.vcf.gz

        $G VariantFiltration -R {input.ref} -V work/filter/snps.vcf.gz -O work/filter/snps.filtered.vcf.gz \
            --filter-expression "QD < 2.0"              --filter-name QD2 \
            --filter-expression "FS > 60.0"             --filter-name FS60 \
            --filter-expression "MQ < 40.0"             --filter-name MQ40 \
            --filter-expression "SOR > 3.0"             --filter-name SOR3 \
            --filter-expression "MQRankSum < -12.5"     --filter-name MQRankSum-12.5 \
            --filter-expression "ReadPosRankSum < -8.0" --filter-name ReadPosRankSum-8
        $G VariantFiltration -R {input.ref} -V work/filter/indels.vcf.gz -O work/filter/indels.filtered.vcf.gz \
            --filter-expression "QD < 2.0"               --filter-name QD2 \
            --filter-expression "FS > 200.0"             --filter-name FS200 \
            --filter-expression "ReadPosRankSum < -20.0" --filter-name ReadPosRankSum-20

        $G MergeVcfs -I work/filter/snps.filtered.vcf.gz -I work/filter/indels.filtered.vcf.gz -O {output.vcf}
        ) 2> {log}

        printf 'chrom\tpos\tref\talt\tqual\tfilter\n' > {output.table}
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER\n' {output.vcf} >> {output.table}
        """


# Stage 8 · qc_report — one report across the cohort, given the reports themselves, not .
rule multiqc:
    input:
        fastqc=expand("work/fastqc/{sample}", sample=SAMPLES),
        fastp=expand("work/trim/{sample}.fastp.json", sample=SAMPLES),
        dups=expand("work/dedup/{sample}.dup_metrics.txt", sample=SAMPLES),
        flagstat=expand("work/dedup/{sample}.flagstat.txt", sample=SAMPLES),
    output:
        f"{OUT}/multiqc_report.html",
    log:
        "logs/multiqc.log",
    container: IMAGES["multiqc"]
    shell:
        "(multiqc -q -f -o work/multiqc {input} && cp work/multiqc/multiqc_report.html {output}) 2> {log}"


# Stage 9 · publish — the course's rule: samples.tsv and manifest.json.
PUBLISH_SHEET = rules.validate.output
PUBLISH_RESULTS = [*rules.filter.output, *rules.multiqc.output]
include: "rules/publish.smk"
