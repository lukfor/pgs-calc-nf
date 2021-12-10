import java.io.File;
import java.util.List;
import java.util.Vector;
import java.util.concurrent.Callable;

import genepi.io.table.writer.CsvTableWriter;
import genepi.io.table.reader.XlsxTableReader;
import genepi.io.text.LineWriter;
import picocli.CommandLine;
import picocli.CommandLine.Option;

//usr/bin/env jbang "$0" "$@" ; exit $?
//REPOS jcenter,jfrog-genepi-maven=https://genepi.jfrog.io/artifactory/maven
//DEPS info.picocli:picocli:4.5.0
//DEPS genepi:genepi-io:1.1.1

public class ExcelToCsv implements Callable<Integer> {

      @Option(names = "--input", description = "input excel file", required = true)
      private String input;

      @Option(names = "--output", description = "output csv file", required = true)
      private String output;

      @Option(names = "--sheet", description = "Sheet name", required = false)
      private String sheet;

      public static void main(String ... args) {
              int exitCode = new CommandLine(new ExcelToCsv()).execute(args);
              System.exit(exitCode);
      }

      @Override
      public Integer call() throws Exception {

              assert (input != null);
              assert (output != null);

              XlsxTableReader reader = null;

              if (sheet != null) {
                      reader = new XlsxTableReader(input, sheet);
              } else {
                      reader = new XlsxTableReader(input);
              }

              CsvTableWriter writer = new CsvTableWriter(output);
              writer.setColumns(reader.getColumns());
              while(reader.next()) {
                      //ignore empty rows
                      boolean empty = true;
                      String[] row = reader.getRow();
                      for (int i = 0; i < row.length; i++) {
                            if (!row[i].isEmpty()) {
                                  empty = false;
                            }
                      }
                      if (!empty) {
                            writer.setRow(row);
                            writer.next();
                      }
              }

              writer.close();
              reader.close();

              return 0;
      }

}
