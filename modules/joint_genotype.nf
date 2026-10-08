// Stage 6 · merge — joint genotyping across every sample: CombineGVCFs, then GenotypeGVCFs,
// the same tools as weeks 2 and 3. Its inputs are every sample's GVCF and index at once.
process JOINT_GENOTYPE {
    container params.containers.gatk

    input:
    path gvcfs
    path tbis
    path ref
    path ref_index
    path ref_dict
    val  region

    output:
    path 'cohort.vcf.gz',     emit: vcf
    path 'cohort.vcf.gz.tbi', emit: tbi

    script:
    def xmx  = Math.max((task.memory.toGiga() * 0.8) as int, 1)
    def vcfs = [gvcfs].flatten().collect { "-V ${it}" }.sort().join(' ')
    """
    gatk --java-options "-Xmx${xmx}g -Djava.io.tmpdir=." CombineGVCFs \\
        -R ${ref} -L ${region} ${vcfs} -O cohort.g.vcf.gz
    gatk --java-options "-Xmx${xmx}g -Djava.io.tmpdir=." GenotypeGVCFs \\
        -R ${ref} -L ${region} -V cohort.g.vcf.gz -O cohort.vcf.gz
    """
}
