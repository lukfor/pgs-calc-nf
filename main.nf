
Channel.fromFilePairs(params.genotypes_imputed).set{vcf_files}

if (params.scores == "") {

Channel.fromFilePairs(params.dbsnp_index).set{dbsnp_index_ch}

if (params.genotypes_imputed_format != 'vcf'){
  exit 1, "PGS Calc supports only vcf files."
}

if (params.genotypes_build == "hg19"){
  build_filter = "hg19|GRCh37|NR"
} else if (params.genotypes_build == "hg38"){
  build_filter = "hg38|GRCh38|NR"
} else {
  exit 1, "Unsupported build."
}


ExcelToCsvJava = file("$baseDir/src/ExcelToCsv.java")


process cacheJBangScripts {

  input:
    file ExcelToCsvJava

  output:
    file "ExcelToCsv.jar" into ExcelToCsv

  """
  jbang export portable -O=ExcelToCsv.jar ${ExcelToCsvJava}
  """

}


if (params.pgs_catalog_url.startsWith('https://') || params.pgs_catalog_url.startsWith('http://')){

  process downloadPGSCatalogMeta {

    output:
      file "*.xlsx" into pgs_catalog_excel_file

    """
    wget ${params.pgs_catalog_url}
    """

  }

} else {

  pgs_catalog_excel_file = file(params.pgs_catalog_url)

}


process convertPgsCatalogMeta {

  input:
    file ExcelToCsv
    file excel_file from pgs_catalog_excel_file

  output:
    file "*.csv" into pgs_catalog_csv_file

  """
  java -jar ${ExcelToCsv} \
    --input ${excel_file} \
    --sheet Scores \
    --output pgs_all_metadata.csv
  """

}


if (params.pgs_catalog_url.startsWith('https://') || params.pgs_catalog_url.startsWith('http://')){


  // filter out other pgs scores
  pgs_catalog_csv_file
    .splitCsv(header: true, sep: ',', quote:'"')
    .filter(row -> row['Polygenic Score (PGS) ID'] in (params.pgs_scores.split(',')) )
    .map(row -> tuple(row['Polygenic Score (PGS) ID'], row['FTP link']) )
    .set { score_rows }

  process downloadScore {

    publishDir params.output, mode: 'copy'

    input:
      tuple val(score_id), val(score_ftp_link) from score_rows

    output:
      tuple val(score_id), file("${score_id}.original.txt.gz") into scores_ch

    """

    ##TODO check build and write to log if not same.

    wget ${score_ftp_link} -O ${score_id}.original.txt.gz

    """
  }

} else {

  // filter out other pgs scores
  pgs_catalog_csv_file
    .splitCsv(header: true, sep: ',', quote:'"')
    .filter(row -> row['Polygenic Score (PGS) ID'] in (params.pgs_scores.split(',')) )
    .map(row -> tuple(row['Polygenic Score (PGS) ID'], file(new File(params.pgs_catalog_url).getAbsoluteFile().getParent() + '/' + row['FTP link'])))
    .set { score_rows }

  process copyScore {

    publishDir params.output, mode: 'copy'

    input:
      tuple val(score_id), file(score_file) from score_rows

    output:
      tuple val(score_id), file("${score_id}.original.txt.gz") into scores_ch

    """

    ##TODO check build and write to log if not same.

    cp ${score_file} ${score_id}.original.txt.gz

    """
  }

}


process resolveScore {

  publishDir params.output, mode: 'copy'

  input:
    tuple val(score_id), file(score_file) from scores_ch
    tuple val(dbsnp_index), file(dbsnp_index_file) from dbsnp_index_ch.collect()

  output:
    file "${score_id}.txt.gz" optional true into prepared_scores_ch
    file "${score_id}.log"

  """
  set +e

  pgs-calc resolve \
    --in ${score_file} \
    --out ${score_id}.txt.gz \
    --dbsnp ${dbsnp_index}.txt.gz > ${score_id}.log

  # ignore pgs-calc status to get log files of failed scores.
  exit 0
  """
}

} else {
  Channel.fromPath(params.scores).set{prepared_scores_ch}
}

process calcChunks {

  input:
    tuple val(vcf_filename), path(vcf_file) from vcf_files
    val scores from prepared_scores_ch.collect()

  output:
    file "*.txt" optional true into score_chunks_ch
    file "*.info" optional true into report_chunks_ch
    file "*.log"

  """
  set +e

  pgs-calc apply ${vcf_filename}.vcf.gz \
    --ref ${scores.join(',')} \
    --dosages ${genotypes_imputed_dosages} \
    --out ${vcf_filename}.scores.txt \
    --info ${vcf_filename}.scores.info \
    --no-ansi > ${vcf_filename}.scores.log

  # ignore pgs-calc status to get log files of failed scores.
  exit 0
  """

}

process mergeScoreChunks {

  publishDir params.output, mode: 'copy'

  input:
    file(score_chunks) from score_chunks_ch.collect()

  output:
    file "*.txt" into merged_score_files

  """

  pgs-calc merge-score ${score_chunks} \
    --out ${params.project}.scores.txt

  """

}

process mergeInfoChunks {

  publishDir params.output, mode: 'copy'

  input:
    file(report_chunks) from report_chunks_ch.collect()

  output:
    file "*.info" into merged_info_files

  """

  pgs-calc merge-info ${report_chunks} \
    --out ${params.project}.info

  """

}

process createHtmlReport {

  publishDir params.output, mode: 'copy'

  input:
    file(merged_score) from merged_score_files
    file(merged_info) from merged_info_files


  output:
    file "*.html"
    file "*.coverage.txt"

  """

  wget https://www.pgscatalog.org/rest/score/all -O pgs-catalog.json

  pgs-calc report \
    --data ${merged_score} \
    --info ${merged_info} \
    --meta pgs-catalog.json \
    --out ${params.project}.scores.html

  pgs-calc report \
    --data ${merged_score} \
    --info ${merged_info} \
    --meta pgs-catalog.json \
    --template txt \
    --out ${params.project}.scores.coverage.txt

  """

}


workflow.onComplete {
    println "Pipeline completed at: $workflow.complete"
    println "Execution status: ${ workflow.success ? 'OK' : 'failed' }"
}
