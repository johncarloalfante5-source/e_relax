import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportChartPoint {
  const ReportChartPoint({required this.label, required this.values});

  final String label;
  final List<double> values;
}

class ReportPdfService {
  static Future<void> download({
    required String title,
    required String periodLabel,
    required List<String> seriesNames,
    List<int> seriesColorValues = const [],
    required List<ReportChartPoint> points,
    required List<String> summary,
    String detailTitle = 'Details',
    List<List<String>> detailRows = const [],
    List<String> detailHeaders = const [],
    required String filename,
  }) async {
    final document = pw.Document();
    final defaultColors = [PdfColors.green800, PdfColors.blue700];
    final colors = seriesColorValues.isEmpty
        ? defaultColors
        : [for (final value in seriesColorValues) PdfColor.fromInt(value)];
    final chartWidth = 690 / seriesNames.length - 40;
    final maxValue = points.fold<double>(0, (max, point) {
      final pointMax = point.values.fold<double>(
        0,
        (value, candidate) => candidate > value ? candidate : value,
      );
      return pointMax > max ? pointMax : max;
    });

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(32),
        ),
        build: (context) => [
          pw.Text(
            'E-Relax Massage Clinic',
            style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Reporting period: $periodLabel'),
          pw.SizedBox(height: 16),
          pw.Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              for (final item in summary)
                pw.Text(item, style: pw.TextStyle(fontSize: 11)),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Chart',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Wrap(
            spacing: 16,
            children: [
              for (var index = 0; index < seriesNames.length; index++)
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Container(
                      width: 10,
                      height: 10,
                      color: colors[index % colors.length],
                    ),
                    pw.SizedBox(width: 5),
                    pw.Text(seriesNames[index]),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 10),
          for (final point in points)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 78,
                    child: pw.Text(point.label, style: const pw.TextStyle(fontSize: 9)),
                  ),
                  for (var index = 0; index < seriesNames.length; index++) ...[
                    pw.SizedBox(
                      width: chartWidth,
                      child: pw.Container(
                        height: 14,
                        color: PdfColors.grey200,
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Container(
                          width: maxValue == 0
                              ? 0
                              : (chartWidth - 10) *
                                    (point.values[index] / maxValue),
                          height: 14,
                          color: colors[index % colors.length],
                        ),
                      ),
                    ),
                    pw.SizedBox(
                      width: 40,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.only(left: 5),
                        child: pw.Text(
                          _formatValue(point.values[index]),
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (detailRows.isNotEmpty) ...[
            pw.SizedBox(height: 22),
            pw.Text(
              detailTitle,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: detailHeaders,
              data: detailRows,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellPadding: const pw.EdgeInsets.all(7),
            ),
          ],
          pw.SizedBox(height: 18),
          pw.Text(
            'Generated ${DateTime.now().toLocal()}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => document.save(),
      name: filename,
    );
  }

  static String _formatValue(double value) =>
      value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(2);
}
