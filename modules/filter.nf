// Stage 7 · analyze — the GATK Best Practices hard filters, SNPs and indels separately,
// as in weeks 1-3; then variants.tsv, one line per record of the filtered VCF.
process FILTER {
    container params.containers.gatk

    input:
    path vcf
    path tbi
    path ref
    path ref_index
    path ref_dict

    output:
    path 'cohort.filtered.vcf.gz', emit: vcf
    path 'variants.tsv',           emit: table

    script:
    def xmx  = Math.max((task.memory.toGiga() * 0.8) as int, 1)
    def gatk = "gatk --java-options \"-Xmx${xmx}g -Djava.io.tmpdir=.\""
    """
    ${gatk} SelectVariants -R ${ref} -V ${vcf} --select-type-to-include SNP -O snps.vcf.gz
    ${gatk} SelectVariants -R ${ref} -V ${vcf} --select-type-to-include INDEL \\
        --select-type-to-include MIXED -O indels.vcf.gz

    ${gatk} VariantFiltration -R ${ref} -V snps.vcf.gz -O snps.filtered.vcf.gz \\
        --filter-expression "QD < 2.0"              --filter-name QD2 \\
        --filter-expression "FS > 60.0"             --filter-name FS60 \\
        --filter-expression "MQ < 40.0"             --filter-name MQ40 \\
        --filter-expression "SOR > 3.0"             --filter-name SOR3 \\
        --filter-expression "MQRankSum < -12.5"     --filter-name MQRankSum-12.5 \\
        --filter-expression "ReadPosRankSum < -8.0" --filter-name ReadPosRankSum-8
    ${gatk} VariantFiltration -R ${ref} -V indels.vcf.gz -O indels.filtered.vcf.gz \\
        --filter-expression "QD < 2.0"               --filter-name QD2 \\
        --filter-expression "FS > 200.0"             --filter-name FS200 \\
        --filter-expression "ReadPosRankSum < -20.0" --filter-name ReadPosRankSum-20

    ${gatk} MergeVcfs -I snps.filtered.vcf.gz -I indels.filtered.vcf.gz -O cohort.filtered.vcf.gz

    printf 'chrom\\tpos\\tref\\talt\\tqual\\tfilter\\n' > variants.tsv
    bcftools query -f '%CHROM\\t%POS\\t%REF\\t%ALT\\t%QUAL\\t%FILTER\\n' cohort.filtered.vcf.gz >> variants.tsv
    """
}
