version 1.0

import "file:///home/ac.aleman/Bacterial_GATK_SNPs_aleman/workflow/scripts/MicrobialAlignmentPipeline.wdl" as AlignAndMarkDuplicates
# import "https://api.firecloud.org/ga4gh/v1/tools/jakec:SamToFastq/versions/8/plain-WDL/descriptor" as SamToFastq
import "https://raw.githubusercontent.com/broadinstitute/GATK-for-Microbes/master/wdl/shortReads/SamToFastq.wdl" as SamToFastq
import "https://raw.githubusercontent.com/gatk-workflows/seq-format-conversion/master/paired-fastq-to-unmapped-bam.wdl" as FastqToUnmappedBam

workflow MicrobialGenomePipeline {

  meta {
    description: "Takes in a bam or fastq files, aligns to ref and shifted reference."
  }

  input {

    File? sdk_init
    String disk_space

    String sample_name
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File ref_amb
    File ref_ann
    File ref_bwt
    File ref_pac
    File ref_sa
     
    # inputs required when starting from bam file
    File? input_bam
    File? input_bam_index

    # iputs required when starting from fastq files
    String? input_fastq1
    String? input_fastq2
    String? readgroup_name
    String? library_name
    String? platform_unit
    String? run_date
    String? platform_name
    String? sequencing_center
    File? fastqunpaired

    Int? num_dangling_bases
    String? m2_extra_args
    String? m2_filter_extra_args
    Boolean make_bamout = true
    Boolean? circular_ref
  

    #Optional runtime arguments
    Int? preemptible_tries
    File? gatk_override
    String? gatk_docker_override

  }

  parameter_meta {
    input_bam: "Full WGS hg38 bam or cram"
    sample_name: "Name of file in final output vcf"
  }

  if (select_first([circular_ref, false])) {
    call ShiftReference {
      input:
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        ref_dict = ref_dict,
        preemptible_tries = preemptible_tries,
        disk_space = disk_space
    }

    call IndexReference as IndexShiftedRef {
      input:
      ref_fasta = ShiftReference.shifted_ref_fasta,
      preemptible_tries = preemptible_tries,
      disk_space = disk_space
    }
  }

# only for bam input
  if (defined(input_bam)) {
    call RevertSam {
      input:
        input_bam = select_first([input_bam, ""]),
        preemptible_tries = preemptible_tries,
        disk_space = disk_space
    }

    call SamToFastq.convertSamToFastq as SamToFastq {
      input:
        inputBam = RevertSam.unmapped_bam,
        sampleName = sample_name,
        memoryGb = 4,
        diskSpaceGb = 3 # TODO see if we can do computations on the input_bam size here
    }
  }

  if (defined(input_fastq1) && defined(input_fastq2)) {
    call FastqToUnmappedBam.ConvertPairedFastQsToUnmappedBamWf as FastqToUnmappedBam {
      input:
        sample_name = sample_name,
        fastq_1 = select_first([input_fastq1, ""]),
        fastq_2 = select_first([input_fastq2, ""]),
        readgroup_name = select_first([readgroup_name, ""]),
        library_name = select_first([library_name, ""]),
        platform_unit = select_first([platform_unit, ""]),
	run_date = select_first([run_date, "0000-00-00"]),
        platform_name = select_first([platform_name, ""]),
        sequencing_center = select_first([sequencing_center, ""])
    }
  }

File fastq1 = select_first([input_fastq1, SamToFastq.fastq1])
File fastq2 = select_first([input_fastq2, SamToFastq.fastq2])
#File fastq1 = select_first([SamToFastq.fastq1, input_fastq1])
#File fastq2 = select_first([SamToFastq.fastq2, input_fastq2])
File ubam = select_first([RevertSam.unmapped_bam, FastqToUnmappedBam.output_unmapped_bam])
Int num_dangling_bases_with_default = select_first([num_dangling_bases, 1])
File in_bam = select_first([input_bam, AlignToRef.aligned_bam])
File in_bai = select_first([input_bam_index, AlignToRef.aligned_bai])

# pass in 2 fastq files and unmapped bam
  call AlignAndMarkDuplicates.MicrobialAlignmentPipeline as AlignToRef {
    input:
      unmapped_bam = ubam,
      fastq1 = fastq1,
      fastq2 = fastq2,
      ref_dict = ref_dict,
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      ref_amb = ref_amb,
      ref_ann = ref_ann,
      ref_bwt = ref_bwt,
      ref_pac = ref_pac,
      ref_sa = ref_sa,
      preemptible_tries = preemptible_tries
  }

  call M2 as CallM2 {
    input:
      input_bam = in_bam,
      input_bai = in_bai,
      ref_fasta = ref_fasta,
      ref_fai = ref_fasta_index,
      ref_dict = ref_dict,
      intervals = ShiftReference.unshifted_intervals,
      num_dangling_bases = num_dangling_bases_with_default,
      make_bamout = make_bamout,
      m2_extra_args = m2_extra_args,
      gatk_override = gatk_override,
      preemptible_tries = preemptible_tries,
      disk_space = disk_space
  }


  if (select_first([circular_ref, false])) {
    call AlignAndMarkDuplicates.MicrobialAlignmentPipeline as AlignToShiftedRef {
      input:
        unmapped_bam = ubam,
        fastq1 = fastq1,
        fastq2 = fastq2,
        ref_dict = select_first([ShiftReference.shifted_ref_dict]),
        ref_fasta = select_first([ShiftReference.shifted_ref_fasta]),
        ref_fasta_index = select_first([ShiftReference.shifted_ref_fasta_index]),
        ref_amb = select_first([IndexShiftedRef.ref_amb]),
        ref_ann = select_first([IndexShiftedRef.ref_ann]),
        ref_bwt = select_first([IndexShiftedRef.ref_bwt]),
        ref_pac = select_first([IndexShiftedRef.ref_pac]),
        ref_sa = select_first([IndexShiftedRef.ref_sa]),
        preemptible_tries = preemptible_tries
    }

    call M2 as CallShiftedM2 {
      input:
        input_bam = AlignToShiftedRef.aligned_bam,
        input_bai = AlignToShiftedRef.aligned_bai,
        ref_fasta = select_first([ShiftReference.shifted_ref_fasta]),
        ref_fai = select_first([ShiftReference.shifted_ref_fasta_index]),
        ref_dict = select_first([ShiftReference.shifted_ref_dict]),
        intervals = ShiftReference.shifted_intervals,
        num_dangling_bases = num_dangling_bases_with_default,
        make_bamout = make_bamout,
        m2_extra_args = m2_extra_args,
        gatk_override = gatk_override,
        preemptible_tries = preemptible_tries,
        disk_space = disk_space
    }

    if (defined(make_bamout) && select_first([make_bamout, false])) {
      call ShiftBackBam {
        input:
          bam = CallShiftedM2.output_bamout,
          shiftback_chain = select_first([ShiftReference.shiftback_chain]),
          preemptible_tries = preemptible_tries,
          disk_space = disk_space

      }
    }

    call LiftoverAndCombineVcfs {
      input:
        shifted_vcf = CallShiftedM2.raw_vcf,
        vcf = CallM2.raw_vcf,
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        ref_dict = ref_dict,
        shiftback_chain = select_first([ShiftReference.shiftback_chain]),
        preemptible_tries = preemptible_tries,
        disk_space = disk_space
    }

    call MergeStats {
      input:
        shifted_stats = CallShiftedM2.stats,
        non_shifted_stats = CallM2.stats,
        gatk_override = gatk_override,
        preemptible_tries = preemptible_tries,
        disk_space = disk_space
    }
  }

  File raw_vcf = select_first([LiftoverAndCombineVcfs.final_vcf, CallM2.raw_vcf])
  File raw_vcf_idx = select_first([LiftoverAndCombineVcfs.final_vcf_index, CallM2.raw_vcf_idx])
  File selected_stats = select_first([MergeStats.stats, CallM2.stats])

  call Filter {
    input:
      raw_vcf = raw_vcf,
      raw_vcf_index = raw_vcf_idx,
      raw_vcf_stats = selected_stats,
      sample_name = sample_name,
      ref_fasta = ref_fasta,
      ref_fai = ref_fasta_index,
      ref_dict = ref_dict,
      gatk_override = gatk_override,
      gatk_docker_override = gatk_docker_override,
      m2_extra_filtering_args = m2_filter_extra_args,
      # vaf_filter_threshold = 0,  # do we need this value?
      preemptible_tries = preemptible_tries,
      disk_space = disk_space
  }

  output {
    File final_vcf = raw_vcf
    File final_vcf_index = raw_vcf_idx
    File stats = selected_stats
    File filtered_vcf = Filter.filtered_vcf
    File filtered_vcf_idx = Filter.filtered_vcf_idx
    File unmapped_bam = ubam
    File asssembly_region_out = CallM2.assembly_region_out
    File? shifted_ref_dict = ShiftReference.shifted_ref_dict
    File? shifted_ref_fasta = ShiftReference.shifted_ref_fasta
    File? shifted_ref_fasta_index = ShiftReference.shifted_ref_fasta_index
    File? shifted_intervals = ShiftReference.shifted_intervals
    File? unshifted_intervals = ShiftReference.unshifted_intervals
    File? shifted_ref_amb = IndexShiftedRef.ref_amb
    File? shifted_ref_ann = IndexShiftedRef.ref_ann
    File? shifted_ref_bwt = IndexShiftedRef.ref_bwt
    File? shifted_ref_pac = IndexShiftedRef.ref_pac
    File? shifted_ref_sa = IndexShiftedRef.ref_sa
    File? bamout_bam = CallM2.output_bamout
    File? shifted_bamout_bam = CallShiftedM2.output_bamout
    File? shifted_back_bamout_bam = ShiftBackBam.bamout
  }
}


task ShiftReference {
  input {

    String disk_space

    File ref_fasta
    File ref_fasta_index
    File ref_dict
    String basename = basename(ref_fasta, ".fasta")

    # runtime
    Int? preemptible_tries
    File? gatk_override
  }

  Int disk_size = ceil(size(ref_fasta, "GB") * 2.5) + 20

  meta {
    description: "Creates a shifted reference file and shiftback chain file"
  }
  parameter_meta {
    ref_fasta: {
      localization_optional: true
    }
    ref_fasta_index: {
      localization_optional: true
    }    
    ref_dict: {
      localization_optional: true
    }
  }
  command <<<
      set -e

      export GATK_LOCAL_JAR=~{default="/root/gatk.jar" gatk_override}

      gatk --java-options "-Xmx2500m" ShiftFasta \
        -R ~{ref_fasta} \
        -O ~{basename}.shifted.fasta \
        --interval-file-name ~{basename} \
        --shift-back-output ~{basename}.shiftback.chain
  >>>
  runtime {
      container: "broadinstitute/gatk"
      memory: "2 GB"
      preemptible: select_first([preemptible_tries, 5])
      cpu: 2
  }
  output {
    File shifted_ref_fasta = "~{basename}.shifted.fasta"
    File shifted_ref_fasta_index = "~{basename}.shifted.fasta.fai"
    File shifted_ref_dict = "~{basename}.shifted.dict"
    File shiftback_chain = "~{basename}.shiftback.chain"
    File unshifted_intervals = "~{basename}.intervals"
    File shifted_intervals = "~{basename}.shifted.intervals"
  }
}

task IndexReference {
  input {

    String disk_space

    File ref_fasta    
    Int? preemptible_tries
  }

  Int disk_size = ceil(size(ref_fasta, "GB") * 2.5) + 20
  String basename = basename(ref_fasta)
  
  command <<<
      set -e
      cp ~{ref_fasta} .
      /usr/gitc/bwa index ~{basename}
      ls -al
      find . -name *.pac -print
  >>>
  runtime {
    preemptible: select_first([preemptible_tries, 5])
    memory: "2 GB"
    disks: disk_space
    docker: "us.gcr.io/broad-gotc-prod/genomes-in-the-cloud:2.4.2-1552931386"
  }

  output {
    File ref_amb = "~{basename}.amb"
    File ref_ann = "~{basename}.ann"
    File ref_bwt = "~{basename}.bwt"
    File ref_pac = "~{basename}.pac"
    File ref_sa = "~{basename}.sa"
  }
}


task RevertSam {
  input {

    String disk_space

    File input_bam
    String basename = basename(input_bam, ".bam")

    # runtime
    Int? preemptible_tries
  }
  Int disk_size = ceil(size(input_bam, "GB") * 2.5) + 20

  meta {
    description: "Removes alignment information while retaining recalibrated base qualities and original alignment tags"
  }
  parameter_meta {
    input_bam: "aligned bam"
  }
  command {
    java -Xmx1000m -jar /usr/gitc/picard.jar \
    RevertSam \
    INPUT=~{input_bam} \
    OUTPUT_BY_READGROUP=false \
    OUTPUT=~{basename}.bam \
    VALIDATION_STRINGENCY=LENIENT \
    ATTRIBUTE_TO_CLEAR=FT \
    ATTRIBUTE_TO_CLEAR=CO \
    SORT_ORDER=queryname \
    RESTORE_ORIGINAL_QUALITIES=false
  }
  runtime {
    disks: disk_space
    memory: "2 GB"
    docker: "broadinstitute/gatk"
    preemptible: select_first([preemptible_tries, 5])
  }
  output {
    File unmapped_bam = "~{basename}.bam"
  }
}

task LiftoverAndCombineVcfs {
  input {

    String disk_space

    File shifted_vcf
    File vcf
    String basename = basename(shifted_vcf, ".vcf")

    File ref_fasta
    File ref_fasta_index
    File ref_dict

    File shiftback_chain

    # runtime
    Int? preemptible_tries
  }

  Float ref_size = size(ref_fasta, "GB") + size(ref_fasta_index, "GB")
  Int disk_size = ceil(size(shifted_vcf, "GB") + ref_size) + 20

  meta {
    description: "Lifts over shifted vcf of the interval region and combines it with the unshifted vcf."
  }
  parameter_meta {
    shifted_vcf: "VCF of the shifted interval region on shifted reference"
    vcf: "VCF of the unshifted interval region on original reference"
    ref_fasta: "Original (not shifted) reference"
    shiftback_chain: "Chain file to lift over from shifted reference to original reference"
  }
  command<<<
    set -e

    gatk LiftoverVcf \
      I=~{shifted_vcf} \
      O=~{basename}.shifted_back.vcf \
      R=~{ref_fasta} \
      CHAIN=~{shiftback_chain} \
      REJECT=~{basename}.rejected.vcf

    gatk MergeVcfs \
      I=~{basename}.shifted_back.vcf \
      I=~{vcf} \
      O=~{basename}.final.vcf
    >>>
    runtime {
      disks: disk_space
      memory: "2 GB"
      docker: "broadinstitute/gatk"
      preemptible: select_first([preemptible_tries, 5])
    }
    output{
        # rejected_vcf should always be empty
        File rejected_vcf = "~{basename}.rejected.vcf"
        File final_vcf = "~{basename}.final.vcf"
        File final_vcf_index = "~{basename}.final.vcf.idx"
    }
}

task M2 {
  input {

    String disk_space

    File ref_fasta
    File ref_fai
    File ref_dict
    File input_bam
    File input_bai
    File? intervals
    Int num_dangling_bases
    String? m2_extra_args
    Boolean? make_bamout
    File? gga_vcf
    File? gga_vcf_idx
    File? gatk_override
    # runtime
    Int? mem
    Int? preemptible_tries
  }

  String output_vcf = "raw" + ".vcf"
  String output_vcf_index = output_vcf + ".idx"
  Float ref_size = size(ref_fasta, "GB") + size(ref_fai, "GB")
  Int disk_size = ceil(size(input_bam, "GB") + ref_size) + 20

  # Mem is in units of GB but our command and memory runtime values are in MB
  Int machine_mem = if defined(mem) then select_first([mem, 0]) * 1000 else 3500
  Int command_mem = machine_mem - 500

  meta {
    description: "Mutect2 for calling Snps and Indels"
  }
  parameter_meta {
    input_bam: "Aligned Bam"
    gga_vcf: "VCF for force-calling mode"
  }
  command <<<
      set -e

      export GATK_LOCAL_JAR=~{default="/root/gatk.jar" gatk_override}

      # We need to create these files regardless, even if they stay empty
      touch bamout.bam

      # TODO change param back to num_dangling_bases
      gatk --java-options "-Xmx~{command_mem}m" Mutect2 \
        -R ~{ref_fasta} \
        -I ~{input_bam} \
        ~{"--alleles " + gga_vcf} \
        -O ~{output_vcf} \
        ~{"-L " + intervals} \
        ~{true='--bam-output bamout.bam' false='' make_bamout} \
        ~{m2_extra_args} \
        --annotation StrandBiasBySample \
        --max-reads-per-alignment-start 75 \
        --num-matching-bases-in-dangling-end-to-recover 1 \
        --assembly-region-out assembly_region_out
  >>>
  runtime {
      docker: "broadinstitute/gatk"
      memory: machine_mem + " MB"
      disks: disk_space
      preemptible: select_first([preemptible_tries, 5])
      cpu: 2
  }
  output {
      File raw_vcf = "~{output_vcf}"
      File raw_vcf_idx = "~{output_vcf_index}"
      File stats = "~{output_vcf}.stats"
      File output_bamout = "bamout.bam"
      File assembly_region_out = "assembly_region_out"
  }
}

task Filter {
  input {

    String disk_space

    File ref_fasta
    File ref_fai
    File ref_dict
    File raw_vcf
    File raw_vcf_index
    File raw_vcf_stats
    Float? vaf_cutoff
    String sample_name

    String? m2_extra_filtering_args
  
    Float? verifyBamID

    File? gatk_override
    String? gatk_docker_override

  # runtime
    Int? preemptible_tries
  }

  String output_vcf = sub(sample_name, "(0x20 | 0x9 | 0xD | 0xA)+", "_") + ".vcf"
  String output_vcf_index = output_vcf + ".idx"
  Float ref_size = size(ref_fasta, "GB") + size(ref_fai, "GB")
  Int disk_size = ceil(size(raw_vcf, "GB") + ref_size) + 20
  
  meta {
    description: "Mutect2 Filtering for calling Snps and Indels"
  }
  command <<<
      set -e

      export GATK_LOCAL_JAR=~{default="/root/gatk.jar" gatk_override}

      # We need to create these files regardless, even if they stay empty
      touch bamout.bam

      gatk --java-options "-Xmx2500m" FilterMutectCalls -V ~{raw_vcf} \
        -R ~{ref_fasta} \
        -O ~{output_vcf} \
        --stats ~{raw_vcf_stats} \
        ~{m2_extra_filtering_args} \
        --microbial-mode 
  >>>
  runtime {
      docker: select_first([gatk_docker_override, "broadinstitute/gatk"])
      memory: "4 MB"
      disks: disk_space
      preemptible: select_first([preemptible_tries, 5])
      cpu: 2
  }
  output {
      File filtered_vcf = "~{output_vcf}"
      File filtered_vcf_idx = "~{output_vcf_index}"
  }
}

task MergeStats {
  input {

    String disk_space

    File shifted_stats
    File non_shifted_stats
    Int? preemptible_tries
    File? gatk_override
  }

  command{
    set -e

    export GATK_LOCAL_JAR=~{default="/root/gatk.jar" gatk_override}

    gatk MergeMutectStats --stats ~{shifted_stats} --stats ~{non_shifted_stats} -O raw.combined.stats
  }
  output {
    File stats = "raw.combined.stats"
  }
  runtime {
      docker: "broadinstitute/gatk"
      memory: "3 MB"
      disks: disk_space
      preemptible: select_first([preemptible_tries, 5])
  }
}

task ShiftBackBam {
  input {

    String disk_space

    File bam
    File shiftback_chain
    Int? preemptible_tries
  }

  command <<<
      set -e
      CrossMap.py bam ~{shiftback_chain} ~{bam} bamout
  >>>
  runtime {
    preemptible: select_first([preemptible_tries, 5])
    memory: "2 GB"
    disks: disk_space
    docker: "us.gcr.io/broad-dsde-methods/gatk-for-microbes:crossmap_d4631de9db30"
  }

  output {
    File bamout = "bamout.sorted.bam"
    File bamout_bai = "bamout.sorted.bam.bai"
  }
}
