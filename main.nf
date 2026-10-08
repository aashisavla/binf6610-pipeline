// variant-call: the ten stages of weeks 1-3 as Nextflow processes.
// Eight human genomes (or the three smoke samples) in, one filtered cohort VCF out.
include { VALIDATE }        from './modules/validate'
include { FASTQC }          from './modules/fastqc'
include { FASTP }           from './modules/fastp'
include { BWA_MEM }         from './modules/bwa_mem'
include { MARKDUPLICATES }  from './modules/markduplicates'
include { HAPLOTYPECALLER } from './modules/haplotypecaller'
include { JOINT_GENOTYPE }  from './modules/joint_genotype'
include { FILTER }          from './modules/filter'
include { MULTIQC }         from './modules/multiqc'
include { PUBLISH }         from './modules/publish'

workflow {
    main:
    // The reference is a value: every sample's task reads the same files.
    ref       = file(params.ref)                                // the FASTA
    ref_index = files("${params.ref}.*")                        // its .fai and the BWA index
    ref_dict  = file("${ref.parent}/${ref.baseName}.dict")      // GATK's sequence dictionary
    sheet     = file(params.samplesheet)

    // One item per sample: [meta, reads], with meta = [id: ..., single_end: ...].
    // Columns are read by name; relative FASTQ paths are relative to the samplesheet.
    ch_samples = channel.fromPath(sheet)
        .splitCsv(header: true)
        .map { row ->
            def meta = [id: row.sample_id, single_end: row.library_type == 'single']
            def r1 = sheet.parent.resolve(row.r1_fastq)
            def reads = meta.single_end ? [r1] : [r1, sheet.parent.resolve(row.r2_fastq)]
            [meta, reads]
        }

    // Stage 0 checks every FASTQ and the reference before anything else starts.
    VALIDATE(sheet, ch_samples.map { _meta, reads -> reads }.collect(),
             ref, ref_index, ref_dict)

    // Every sample waits for stage 0: combine pairs each with VALIDATE's one output.
    ch_checked = ch_samples
        .combine(VALIDATE.out.sheet)
        .map { meta, reads, _validated -> [meta, reads] }

    FASTQC(ch_checked)
    FASTP(ch_checked)
    BWA_MEM(FASTP.out.reads, ref, ref_index)
    MARKDUPLICATES(BWA_MEM.out.bam)
    HAPLOTYPECALLER(MARKDUPLICATES.out.bam, ref, ref_index, ref_dict, params.region)

    // The barrier: stage 6 starts once every sample's GVCF and its index exist.
    JOINT_GENOTYPE(HAPLOTYPECALLER.out.gvcf.collect(), HAPLOTYPECALLER.out.tbi.collect(),
                   ref, ref_index, ref_dict, params.region)
    FILTER(JOINT_GENOTYPE.out.vcf, JOINT_GENOTYPE.out.tbi, ref, ref_index, ref_dict)

    ch_qc = FASTQC.out.zip
        .mix(FASTP.out.json, MARKDUPLICATES.out.metrics, MARKDUPLICATES.out.flagstat)
        .collect()
    MULTIQC(ch_qc)

    PUBLISH(VALIDATE.out.sheet, FILTER.out.vcf.mix(FILTER.out.table, MULTIQC.out).collect())

    publish:
    vcf      = FILTER.out.vcf
    variants = FILTER.out.table
    multiqc  = MULTIQC.out
    manifest = PUBLISH.out.manifest
    samples  = PUBLISH.out.samples
}

// Each result goes to the top of the output folder, results/ unless --outdir says otherwise.
output {
    vcf {
        path '.'
    }
    variants {
        path '.'
    }
    multiqc {
        path '.'
    }
    manifest {
        path '.'
    }
    samples {
        path '.'
    }
}
