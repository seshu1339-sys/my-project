import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A table for an export: a header row and the rows under it. Cells are text or numbers.
class ReportTable {
  const ReportTable(this.title, this.header, this.rows);
  final String title;
  final List<String> header;
  final List<List<Object>> rows;
}

String _xml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
/// Excel sheet names: at most 31 characters, none of the characters \ / ? * [ ] :
String _sheetName(String title) {
  final clean = title.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
  return clean.isEmpty ? 'Sheet' : clean.substring(0, clean.length < 31 ? clean.length : 31);
}

String _col(int i) {
  var n = i, s = '';
  do {
    s = String.fromCharCode(65 + n % 26) + s;
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return s;
}

/// A real Excel file (.xlsx): one sheet per table, text and numbers (no formulas, no styles).
Uint8List buildXlsx(List<ReportTable> tables) {
  final archive = Archive();
  void add(String name, String content) => archive.addFile(ArchiveFile.string(name, content));
  add('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${[
    for (var i = 0; i < tables.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
  ].join()}</Types>');
  add('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
  add('xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${[
    for (var i = 0; i < tables.length; i++) '<sheet name="${_xml(_sheetName(tables[i].title))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>',
  ].join()}</sheets></workbook>');
  add('xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${[
    for (var i = 0; i < tables.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>',
  ].join()}</Relationships>');
  for (var t = 0; t < tables.length; t++) {
    final all = [tables[t].header, ...tables[t].rows];
    final rows = StringBuffer();
    for (var r = 0; r < all.length; r++) {
      rows.write('<row r="${r + 1}">');
      for (var c = 0; c < all[r].length; c++) {
        final v = all[r][c];
        final ref = '${_col(c)}${r + 1}';
        rows.write(v is num ? '<c r="$ref"><v>$v</v></c>' : '<c r="$ref" t="inlineStr"><is><t>${_xml('$v')}</t></is></c>');
      }
      rows.write('</row>');
    }
    add('xl/worksheets/sheet${t + 1}.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>$rows</sheetData></worksheet>');
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// A PDF of the report: the summary text, then each table.
Future<Uint8List> buildPdf(String title, String summary, List<ReportTable> tables) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Header(level: 0, child: pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
        pw.Text(summary),
        for (final t in tables) ...[
          pw.SizedBox(height: 14),
          pw.Text(t.title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: t.header,
            data: [for (final r in t.rows) [for (final c in r) '$c']],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
        ],
      ],
    ),
  );
  return doc.save();
}

/// CSV (opens in Excel too), with a byte-order mark so Telugu and other scripts show correctly.
Uint8List buildCsv(ReportTable table) {
  String cell(Object v) => v is num ? '$v' : '"${'$v'.replaceAll('"', '""')}"';
  final lines = [table.header.map(cell).join(','), for (final r in table.rows) r.map(cell).join(',')];
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(lines.join('\n'))]);
}
