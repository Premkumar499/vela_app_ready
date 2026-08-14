import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;

import '../utils/constants.dart';

/// Service to export invoices as images / PDFs
class InvoiceExportService {
  // Delegates to AppConstants so changing the IP in one place is enough.
  static String get baseUrl => AppConstants.baseUrl;

  /// Capture customer receipt widget as image and upload to erp_billing_system bucket.
  static Future<Map<String, dynamic>> saveInvoiceAsImage({
    required GlobalKey widgetKey,
    required String invoiceNumber,
    required bool isCompanyInvoice,
  }) async {
    try {
      RenderRepaintBoundary? boundary =
          widgetKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        return {'success': false, 'message': 'Could not capture invoice. Please try again.'};
      }

      await Future.delayed(const Duration(milliseconds: 200));

      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        return {'success': false, 'message': 'Failed to convert invoice to image'};
      }

      final Uint8List bytes = byteData.buffer.asUint8List();
      final String base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('$baseUrl/invoice-export/save'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'invoice_number': invoiceNumber,
          'image_data': base64Image,
          'is_company_invoice': isCompanyInvoice,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'message': data['message'],
          'fileName': data['file_name'],
          'bucket': data['bucket'],
          'url': data['url'],
          'size': data['pdf_size'],
        };
      } else {
        final error = jsonDecode(response.body);
        return {'success': false, 'message': error['message'] ?? 'Failed to save invoice'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Generate company invoice PDF server-side from DB data and upload to
  /// erp_billing_system_company bucket. Sends bill data as fallback.
  static Future<Map<String, dynamic>> generateCompanyInvoice(
    String invoiceNumber, {
    Map<String, dynamic>? fallbackData,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/invoice-export/generate-company/$invoiceNumber'),
        headers: {'Content-Type': 'application/json'},
        body: fallbackData != null ? jsonEncode(fallbackData) : '{}',
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'message': data['message'],
          'fileName': data['file_name'],
          'url': data['url'],
        };
      } else {
        final error = jsonDecode(response.body);
        return {'success': false, 'message': error['message'] ?? 'Failed to generate company invoice'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }
}
