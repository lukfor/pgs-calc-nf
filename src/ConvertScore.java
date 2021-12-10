import java.io.File;
import java.io.IOException;
import java.util.List;
import java.util.concurrent.Callable;

import genepi.io.FileUtil;
import genepi.io.text.LineWriter;
import genepi.io.table.writer.ExcelTableWriter;
import genepi.riskscore.io.PGSCatalog;
import genepi.riskscore.io.PGSCatalogFileFormat;
import genepi.riskscore.io.RiskScoreFile;
import genepi.riskscore.io.formats.PGSCatalogFormat;
import genepi.riskscore.tasks.ConvertRsIdsTask;
import lukfor.progress.TaskService;
import lukfor.progress.tasks.Task;
import picocli.CommandLine;
import picocli.CommandLine.Option;

//usr/bin/env jbang "$0" "$@" ; exit $?
//REPOS jcenter,jfrog-genepi-maven=https://genepi.jfrog.io/artifactory/maven
//DEPS info.picocli:picocli:4.5.0
//DEPS genepi:genepi-io:1.1.1
//DEPS lukfor:pgs-calc:0.9.6

public class ConvertScore implements Callable<Integer> {

	@Option(names = "--input", description = "input score file", required = true)
	private String input;

	@Option(names = "--output", description = "output score file", required = true)
	private String output;

	@Option(names = "--dbsnp", description = "dbsnp index vcf file", required = true)
	private String dbsnp;

	public static void main(String... args) {
		int exitCode = new CommandLine(new ConvertScore()).execute(args);
		System.exit(exitCode);
	}

	@Override
	public Integer call() throws Exception {

		LineWriter writer = new LineWriter(output + ".log");
		writer.write("ID: " + input);

		try {

			int originalVariants = 0;

			PGSCatalogFileFormat fileFormat = PGSCatalog.getFileFormat(input);
			writer.write("File Format: " + fileFormat.name());

			if (fileFormat == PGSCatalogFileFormat.RS_ID) {

				ConvertRsIdsTask convertRsIds = new ConvertRsIdsTask(input, output, dbsnp);
				TaskService.setAnsiSupport(false);
				TaskService.setAnimated(false);
				List<Task> result = TaskService.run(convertRsIds);
				if (!result.get(0).getStatus().isSuccess()) {
					throw new IOException(result.get(0).getStatus().getThrowable());
				}

				originalVariants = convertRsIds.getTotal();

			} else {
				FileUtil.copy(input, output);
			}

			// test file format
			RiskScoreFile score = null;
			for (int i = 1; i <= 22; i++){
				score = new RiskScoreFile(output, new PGSCatalogFormat());
				score.buildIndex(i + "");
			}
			if (fileFormat == PGSCatalogFileFormat.COORDINATES) {
				originalVariants = score.getTotalVariants();
			}
			writer.write("Number Variants Original: " + originalVariants);
			writer.write("Number Variants After: " + score.getTotalVariants());
			writer.write("Number Variants Lost: " + (originalVariants - score.getTotalVariants()));

			System.out.println("Downloaded score.");

		} catch (Exception e) {
			e.printStackTrace();
			System.out.println("Error: " + e.getMessage() + "");
			writer.write("Error: " + e.getMessage());
			new File(output).delete();
		}

		writer.close();

		return 0;

	}

}
