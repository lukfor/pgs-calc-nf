# pgs-calc-nf

> Nextflow pipeline to calculate polygenic scores using pgs-calc

## Requirements

- Nextflow:

```
curl -s https://get.nextflow.io | bash
```

- Docker

## Installation

Build docker image before run the pipeline:

```
docker build -t lukfor/pgs-calc-nf . # don't ingore the dot here
```


Test the pipeline and the created docker image with test-data:

```
nextflow run main.nf \
  --project test-project  \
  --genotypes_imputed "tests/data/*.vcf.gz" \
  --genotypes_imputed_format "vcf" \
  --genotypes_imputed_have_index false \
  --genotypes_build "hg19" \
  --scores "tests/data/*.csv"
  --output output
```

Normalized score files from PGSCatalog can be downloaded from [here](https://imputationserver.sph.umich.edu/resources/pgs-catalog/).


## Contact

Lukas Forer (@lukfor), Institute of Genetic Epidemiology, Medical University of Innsbruck

## License

pgs-calc-nf is MIT Licensed.
