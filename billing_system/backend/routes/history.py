"""
Bill history routes.
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from flask import Blueprint, jsonify, request
from services.billing_service import billing_service

history_bp = Blueprint("history", __name__, url_prefix="/bills")


@history_bp.get("/")
def list_bills():
    """GET /bills/ – return all bills, newest first."""
    data = billing_service.get_all_bills()
    return jsonify({"success": True, "data": data, "count": len(data)}), 200


@history_bp.get("/summary")
def summary():
    """
    GET /bills/summary – dashboard totals.
    NOTE: This route MUST be registered before /<bill_number> so that
    Flask matches the literal path '/bills/summary' first.
    """
    data = billing_service.get_dashboard_summary()
    return jsonify({"success": True, "data": data}), 200


@history_bp.get("/<string:bill_number>")
def get_bill(bill_number: str):
    """GET /bills/<bill_number>"""
    bill = billing_service.get_bill_by_number(bill_number)
    if bill is None:
        return jsonify({"success": False, "message": "Bill not found"}), 404
    return jsonify({"success": True, "data": bill}), 200


@history_bp.delete("/<string:bill_number>")
def delete_bill(bill_number: str):
    """DELETE /bills/<bill_number>"""
    result = billing_service.delete_bill(bill_number)
    status = 200 if result["success"] else 404
    return jsonify(result), status


@history_bp.post("/bulk-delete")
def bulk_delete_bills():
    """POST /bills/bulk-delete"""
    payload = request.json or {}
    bill_numbers = payload.get("bill_numbers", [])
    if not bill_numbers:
        return jsonify({"success": False, "message": "No bill numbers provided"}), 400

    # Each delete_bill makes several sequential network calls (DB deletes,
    # storage removals, hold-cancel RPCs), so run bill deletions in parallel.
    deleted = []
    errors = []
    with ThreadPoolExecutor(max_workers=min(8, len(bill_numbers))) as pool:
        futures = {pool.submit(billing_service.delete_bill, bn): bn for bn in bill_numbers}
        for future in as_completed(futures):
            bn = futures[future]
            try:
                res = future.result()
            except Exception as exc:
                errors.append(f"Bill {bn}: {exc}")
                continue
            if res["success"]:
                deleted.append(bn)
            else:
                errors.append(f"Bill {bn}: {res.get('message', 'Unknown error')}")

    if errors:
        return jsonify({
            "success": len(deleted) > 0,
            "message": f"Deleted {len(deleted)} bills. Errors: {'; '.join(errors)}",
            "deleted": deleted
        }), 200 if deleted else 400

    return jsonify({"success": True, "message": f"Successfully deleted {len(deleted)} bills.", "deleted": deleted}), 200


def generate_bills_report_pdf(bills, start_date=None, end_date=None):
    from reportlab.lib.pagesizes import A4
    from reportlab.lib import colors
    from reportlab.lib.units import mm
    from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, HRFlowable
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.enums import TA_CENTER, TA_RIGHT, TA_LEFT
    import io

    # Fonts
    FONT_REG = "Helvetica"
    FONT_BOLD = "Helvetica-Bold"

    navy = colors.HexColor("#1B2A4A")
    light = colors.HexColor("#F3F6FC")

    # Styles
    title_style = ParagraphStyle("Title", fontSize=18, fontName=FONT_BOLD, textColor=navy, alignment=TA_CENTER)
    subtitle_style = ParagraphStyle("SubTitle", fontSize=9, fontName=FONT_REG, textColor=colors.HexColor("#555555"), alignment=TA_CENTER)
    header_style = ParagraphStyle("Header", fontSize=9, fontName=FONT_BOLD, textColor=colors.white, alignment=TA_CENTER)
    cell_style = ParagraphStyle("Cell", fontSize=8.5, fontName=FONT_REG, textColor=colors.black, alignment=TA_LEFT)
    cell_right = ParagraphStyle("CellRight", fontSize=8.5, fontName=FONT_REG, textColor=colors.black, alignment=TA_RIGHT)
    cell_center = ParagraphStyle("CellCenter", fontSize=8.5, fontName=FONT_REG, textColor=colors.black, alignment=TA_CENTER)
    bold_cell = ParagraphStyle("BoldCell", fontSize=8.5, fontName=FONT_BOLD, textColor=colors.black, alignment=TA_LEFT)
    bold_cell_right = ParagraphStyle("BoldCellRight", fontSize=8.5, fontName=FONT_BOLD, textColor=colors.black, alignment=TA_RIGHT)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, leftMargin=12*mm, rightMargin=12*mm, topMargin=12*mm, bottomMargin=12*mm)
    story = []

    # Title
    story.append(Paragraph("<b>VELA AGENCY</b>", title_style))
    story.append(Spacer(1, 4))
    story.append(Paragraph("<b>BILLS HISTORY REPORT</b>", ParagraphStyle("Title2", fontSize=13, fontName=FONT_BOLD, textColor=navy, alignment=TA_CENTER)))
    story.append(Spacer(1, 2))
    
    date_str = f"Date Range: {start_date} to {end_date}" if (start_date and end_date) else \
               f"Since {start_date}" if start_date else \
               f"Until {end_date}" if end_date else "All Time"
    story.append(Paragraph(f"Report Generated on {datetime.now().strftime('%d-%m-%Y %H:%M:%S')} | {date_str}", subtitle_style))
    story.append(Spacer(1, 8))
    story.append(HRFlowable(width="100%", thickness=1, color=navy, spaceAfter=10))

    # Summary calculations
    total_bills = len(bills)
    total_sales = sum(float(b.get("grand_total", 0)) for b in bills)
    cash_sales = sum(float(b.get("grand_total", 0)) for b in bills if b.get("payment_type", "").upper() == "CASH")
    credit_sales = sum(float(b.get("grand_total", 0)) for b in bills if b.get("payment_type", "").upper() == "CREDIT")

    # Summary Table
    summary_data = [
        [
            Paragraph("<b>Total Bills</b>", bold_cell),
            Paragraph("<b>Total Sales</b>", bold_cell),
            Paragraph("<b>Cash Sales</b>", bold_cell),
            Paragraph("<b>Credit Sales</b>", bold_cell),
        ],
        [
            Paragraph(str(total_bills), cell_style),
            Paragraph(f"₹ {total_sales:,.2f}", cell_style),
            Paragraph(f"₹ {cash_sales:,.2f}", cell_style),
            Paragraph(f"₹ {credit_sales:,.2f}", cell_style),
        ]
    ]
    summary_tbl = Table(summary_data, colWidths=[40*mm, 48*mm, 48*mm, 48*mm])
    summary_tbl.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,0), colors.HexColor("#E7ECF6")),
        ("GRID", (0,0), (-1,-1), 0.5, colors.HexColor("#CCCCCC")),
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
        ("TOPPADDING", (0,0), (-1,-1), 6),
        ("BOTTOMPADDING", (0,0), (-1,-1), 6),
        ("LEFTPADDING", (0,0), (-1,-1), 8),
    ]))
    story.append(summary_tbl)
    story.append(Spacer(1, 12))

    # Bills Table
    col_hdr = [
        Paragraph("<b>S.No</b>", header_style),
        Paragraph("<b>Bill Number</b>", header_style),
        Paragraph("<b>Date</b>", header_style),
        Paragraph("<b>Customer Name</b>", header_style),
        Paragraph("<b>Mode</b>", header_style),
        Paragraph("<b>Items</b>", header_style),
        Paragraph("<b>Total (₹)</b>", header_style)
    ]
    table_data = [col_hdr]
    
    for idx, b in enumerate(bills):
        # Format Date
        dt_str = b.get("date", "")
        try:
            dt_part = dt_str.split("T")[0]
            dt_obj = datetime.strptime(dt_part, "%Y-%m-%d")
            formatted_dt = dt_obj.strftime("%d-%m-%Y")
        except Exception:
            formatted_dt = dt_str.split("T")[0] if "T" in dt_str else dt_str

        table_data.append([
            Paragraph(str(idx + 1), cell_center),
            Paragraph(b.get("bill_number", b.get("bill_no", "")), cell_center),
            Paragraph(formatted_dt, cell_center),
            Paragraph(b.get("customer_name", "Walk-in Customer"), cell_style),
            Paragraph(b.get("payment_type", "Cash"), cell_center),
            Paragraph(str(b.get("item_count", 0)), cell_center),
            Paragraph(f"{float(b.get('grand_total', 0)):,.2f}", cell_right)
        ])

    # Totals row in the main table
    table_data.append([
        Paragraph("<b>Total</b>", bold_cell),
        Paragraph("", cell_style),
        Paragraph("", cell_style),
        Paragraph("", cell_style),
        Paragraph("", cell_style),
        Paragraph(str(sum(int(b.get("item_count", 0)) for b in bills)), bold_cell_right),
        Paragraph(f"<b>₹ {total_sales:,.2f}</b>", bold_cell_right)
    ])

    # Widths should sum to roughly A4 width - margins (210 - 24 = 186mm)
    bills_tbl = Table(table_data, colWidths=[12*mm, 32*mm, 22*mm, 65*mm, 18*mm, 15*mm, 22*mm])
    bills_tbl.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,0), navy),
        ("GRID", (0,0), (-1,-1), 0.4, colors.HexColor("#CCCCCC")),
        ("ROWBACKGROUNDS", (0,1), (-1,-2), [colors.white, light]),
        ("BACKGROUND", (0,-1), (-1,-1), colors.HexColor("#E7ECF6")),
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
        ("TOPPADDING", (0,0), (-1,-1), 5),
        ("BOTTOMPADDING", (0,0), (-1,-1), 5),
    ]))
    story.append(bills_tbl)
    
    doc.build(story)
    return buf.getvalue()


def generate_bills_report_csv(bills):
    import io
    import csv

    output = io.StringIO()
    # Write UTF-8 BOM so Excel opens it with proper encoding
    output.write(u'\ufeff')
    writer = csv.writer(output, delimiter=',', quotechar='"', quoting=csv.QUOTE_MINIMAL)

    # Headers
    writer.writerow([
        "S.No",
        "Bill Number",
        "Date",
        "Customer Name",
        "Customer Phone",
        "Payment Mode",
        "Sales Type",
        "Area",
        "Remarks",
        "Item Count",
        "Grand Total (\u20b9)"
    ])

    for idx, b in enumerate(bills):
        # Format Date
        dt_str = b.get("date", "")
        try:
            dt_part = dt_str.split("T")[0]
            dt_obj = datetime.strptime(dt_part, "%Y-%m-%d")
            formatted_dt = dt_obj.strftime("%d-%m-%Y")
        except Exception:
            formatted_dt = dt_str.split("T")[0] if "T" in dt_str else dt_str

        writer.writerow([
            idx + 1,
            b.get("bill_number", b.get("bill_no", "")),
            formatted_dt,
            b.get("customer_name", "Walk-in Customer"),
            b.get("customer_phone", ""),
            b.get("payment_type", "Cash"),
            b.get("sales_type", ""),
            b.get("area", ""),
            b.get("remarks", ""),
            b.get("item_count", 0),
            f"{float(b.get('grand_total', 0)):.2f}"
        ])

    # Totals Row
    total_sales = sum(float(b.get("grand_total", 0)) for b in bills)
    total_items = sum(int(b.get("item_count", 0)) for b in bills)
    writer.writerow([
        "Total",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        total_items,
        f"{total_sales:.2f}"
    ])

    return output.getvalue()


@history_bp.get("/export/pdf")
def export_pdf():
    """GET /bills/export/pdf – export filtered bills as a PDF report."""
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search', '').strip().lower()

    bills = billing_service.get_all_bills()

    # Filter
    filtered = []
    for b in bills:
        # Date filter
        b_date_str = b.get('date', '').split('T')[0]
        if start_date and b_date_str < start_date:
            continue
        if end_date and b_date_str > end_date:
            continue
        # Search filter
        if search:
            bill_num = b.get('bill_number', '').lower()
            cust_name = b.get('customer_name', '').lower()
            if search not in bill_num and search not in cust_name:
                continue
        filtered.append(b)

    # Generate PDF
    pdf_data = generate_bills_report_pdf(filtered, start_date, end_date)
    
    filename = f"bills_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
    
    from flask import Response
    return Response(
        pdf_data,
        mimetype="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Access-Control-Expose-Headers": "Content-Disposition"
        }
    )



@history_bp.get("/export/excel")
def export_excel():
    """GET /bills/export/excel – export filtered bills as a CSV file for Excel."""
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    search = request.args.get('search', '').strip().lower()

    bills = billing_service.get_all_bills()

    # Filter
    filtered = []
    for b in bills:
        # Date filter
        b_date_str = b.get('date', '').split('T')[0]
        if start_date and b_date_str < start_date:
            continue
        if end_date and b_date_str > end_date:
            continue
        # Search filter
        if search:
            bill_num = b.get('bill_number', '').lower()
            cust_name = b.get('customer_name', '').lower()
            if search not in bill_num and search not in cust_name:
                continue
        filtered.append(b)

    # Generate CSV
    csv_data = generate_bills_report_csv(filtered)
    
    filename = f"bills_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    
    from flask import Response
    return Response(
        csv_data,
        mimetype="text/csv",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Access-Control-Expose-Headers": "Content-Disposition"
        }
    )


