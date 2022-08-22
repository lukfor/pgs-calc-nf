
if (params.genotypes_imputed_have_index){
  Channel.fromFilePairs(params.genotypes_imputed).map{it[1][0]}.set{vcf_files}
  Channel.fromFilePairs(params.genotypes_imputed).map{it[1][0]}.set{vcf_files2}
}else{
  Channel.fromPath(params.genotypes_imputed).set{vcf_files}
  Channel.fromPath(params.genotypes_imputed).set{vcf_files2}
}

if (params.chunk_size != 0){

  vcf_files2.map{tuple(it.name, it)}.set{vcf_files_index}

  process createChunks {

    input:
      file vcfs from vcf_files.collect()

    output:
      file "chunks.txt" into chunks_file

    """
    pgs-calc create-chunks ${vcfs} --size ${params.chunk_size} --out chunks.txt
    """

  }

  chunks_file
    .splitCsv(header: true, sep: ',', quote:'"')
    .map(row -> tuple(row['FILENAME'], row['START'], row['END']))
    .combine(vcf_files_index, by: 0).set{chunks_ch}

} else {
  vcf_files.map{tuple(it.name, 1, 250000000, it)}.set{chunks_ch}
}


if (params.proxy_map){
  Channel.fromFilePairs(params.proxy_map).set{proxy_map_ch}
} else {
  proxy_map_ch = [tuple(null, null, null)]
}

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
    tuple val(name), val(start), val(end), file(vcf_file) from chunks_ch
    file scores from prepared_scores_ch.collect()
    tuple val(proxy_map), file(proxy_map_file) from proxy_map_ch.collect()

  output:
    file "*.txt" optional true into score_chunks_ch
    file "*.info" optional true into report_chunks_ch
    file "*.variants" optional true into variants_chunks_ch
    file "*.log"

  """
  set +e

  pgs-calc apply ${vcf_file} \
    --ref ${scores.join(',')} \
    --genotypes ${params.genotypes_imputed_dosages} \
    --out ${vcf_file.baseName}_${start}_${end}.scores.txt \
    --info ${vcf_file.baseName}_${start}_${end}.scores.info \
    --start ${start} \
    --end ${end} \
    ${params.write_variants ? "--write-variants " + vcf_file.baseName + ".variants " : ""} \
    ${params.fix_strand_flips ? "--fix-strand-flips" : ""} \
    ${proxy_map ? "--proxies ${proxy_map}.txt.gz" : ""} \
    --min-r2 ${params.min_r2} \
    --no-ansi > ${vcf_file.baseName}.scores.log

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

process mergeVariantsChunks {

  publishDir params.output, mode: 'copy'

  input:
    file(variants_chunks) from variants_chunks_ch.collect()

  output:
    file "*.variants" into merged_variants_files

  """

  pgs-calc merge-variants ${variants_chunks} \
    --out ${params.project}.variants

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

  #wget https://www.pgscatalog.org/rest/score/all -O pgs-catalog.json
  pgs-calc download-meta --out pgs-catalog.json

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
