import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'format.dart';
import 'store.dart';

/// Maakt een PDF met de notities en foto's van een klus en opent het
/// deelmenu (mail, WhatsApp, Drive, ...).
Future<void> exportJobPdf(BuildContext context, Job job) async {
  final notes = store.notesFor(job.key);
  final photos = store.photosFor(job.key);
  if (notes.isEmpty && photos.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Voeg eerst een notitie of foto toe om te exporteren.')));
    return;
  }

  final doc = pw.Document(title: job.title, author: 'EventFriend');
  final grey = PdfColor.fromInt(0xFF666666);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    footer: (c) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Pagina ${c.pageNumber} van ${c.pagesCount}',
          style: pw.TextStyle(fontSize: 9, color: grey)),
    ),
    build: (c) => [
      pw.Text(job.title,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Text('${dateLong(job.start)}, ${hm(job.start)} - ${hm(job.end)}',
          style: pw.TextStyle(color: grey)),
      if (job.location.isNotEmpty)
        pw.Text(job.location, style: pw.TextStyle(color: grey)),
      pw.SizedBox(height: 16),
      if (notes.isNotEmpty) ...[
        pw.Text('Notities',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        for (final n in notes)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('${dateShort(n.created)} ${hm(n.created)}',
                      style: pw.TextStyle(fontSize: 9, color: grey)),
                  pw.SizedBox(height: 2),
                  if (n.title.trim().isNotEmpty)
                    pw.Text(n.title.trim(),
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(n.text.replaceAll('☐', '[ ]').replaceAll('☑', '[x]')),
                ]),
          ),
        pw.SizedBox(height: 12),
      ],
      if (photos.isNotEmpty) ...[
        pw.Text('Foto\'s',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        for (final p in photos)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Image(pw.MemoryImage(p.bytes),
                      height: 300, fit: pw.BoxFit.contain),
                  if (p.caption.isNotEmpty)
                    pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 4),
                        child: pw.Text(p.caption,
                            style: pw.TextStyle(fontSize: 10, color: grey))),
                ]),
          ),
      ],
    ],
  ));

  final bytes = await doc.save();
  final safe = job.title.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
  final d = job.start;
  await Printing.sharePdf(
      bytes: bytes,
      filename: '${d.year}-${two(d.month)}-${two(d.day)} ${safe.isEmpty ? 'klus' : safe}.pdf');
}
