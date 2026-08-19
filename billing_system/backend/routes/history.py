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
    from reportlab.platypus import Image as RLImage
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.enums import TA_CENTER, TA_RIGHT, TA_LEFT
    import io
    import os
    from datetime import datetime

    # Fonts
    FONT_REG = "Helvetica"
    FONT_BOLD = "Helvetica-Bold"

    brand_green = colors.HexColor("#1b7a42")
    dark_grey = colors.HexColor("#333333")

    # Styles
    title_style = ParagraphStyle("DocTitle", fontSize=26, fontName=FONT_BOLD, textColor=brand_green, alignment=TA_RIGHT, leading=30)
    subtitle_style = ParagraphStyle("DocSubTitle", fontSize=16, fontName=FONT_BOLD, textColor=dark_grey, alignment=TA_RIGHT, leading=20)
    meta_style = ParagraphStyle("DocMeta", fontSize=9.5, fontName=FONT_REG, textColor=dark_grey, alignment=TA_RIGHT, leading=14)
    
    header_style = ParagraphStyle("HeaderCell", fontSize=9.5, fontName=FONT_BOLD, textColor=colors.white, alignment=TA_LEFT)
    header_center = ParagraphStyle("HeaderCenter", fontSize=9.5, fontName=FONT_BOLD, textColor=colors.white, alignment=TA_CENTER)
    
    cell_style = ParagraphStyle("Cell", fontSize=8.5, fontName=FONT_REG, textColor=colors.black, alignment=TA_LEFT)
    cell_center = ParagraphStyle("CellCenter", fontSize=8.5, fontName=FONT_REG, textColor=colors.black, alignment=TA_CENTER)
    
    # Metrics styles
    metric_label = ParagraphStyle("MetricLabel", fontSize=11, fontName=FONT_REG, textColor=colors.HexColor("#555555"), alignment=TA_CENTER, leading=14)
    metric_value = ParagraphStyle("MetricValue", fontSize=20, fontName=FONT_BOLD, textColor=brand_green, alignment=TA_CENTER, leading=24)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, leftMargin=12*mm, rightMargin=12*mm, topMargin=12*mm, bottomMargin=12*mm)
    story = []

    now = datetime.now()
    generated_on = f"{now.day}-{now.month}-{now.year} {now.strftime('%H:%M')}"
    
    # Determine Date Range
    if start_date and end_date:
        date_range_str = f"{start_date} to {end_date}"
    elif start_date:
        date_range_str = f"Since {start_date}"
    elif end_date:
        date_range_str = f"Until {end_date}"
    elif bills:
        bill_dates = []
        for b in bills:
            d_str = b.get("date", "").split("T")[0]
            if d_str:
                bill_dates.append(d_str)
        if bill_dates:
            date_range_str = f"{min(bill_dates)} to {max(bill_dates)}"
        else:
            date_range_str = "All Time"
    else:
        date_range_str = "All Time"

    # Header flowables list
    right_flowables = [
        Paragraph("VELA AGENCY", title_style),
        Spacer(1, 2),
        Paragraph("Sales & Financial Report", subtitle_style),
        Spacer(1, 6),
        Paragraph(f"<b>Generated On:</b> {generated_on}", meta_style),
        Paragraph(f"<b>Date Range:</b> {date_range_str}", meta_style),
        Paragraph("<b>Salesperson:</b> All", meta_style),
    ]

    # Logo image
    LOGO_PATH = os.path.join(os.path.dirname(__file__), "..", "company_logo.jpg")
    logo_cell = Spacer(28*mm, 28*mm)
    if os.path.exists(LOGO_PATH):
        try:
            logo_cell = RLImage(LOGO_PATH, width=28*mm, height=28*mm)
        except Exception:
            pass

    # Header Table
    header_table = Table(
        [[logo_cell, right_flowables]],
        colWidths=[50*mm, 136*mm]
    )
    header_table.setStyle(TableStyle([
        ("VALIGN", (0,0), (-1,-1), "TOP"),
        ("ALIGN", (0,0), (0,0), "LEFT"),
        ("ALIGN", (1,0), (1,0), "RIGHT"),
        ("LEFTPADDING", (0,0), (-1,-1), 0),
        ("RIGHTPADDING", (0,0), (-1,-1), 0),
        ("TOPPADDING", (0,0), (-1,-1), 0),
        ("BOTTOMPADDING", (0,0), (-1,-1), 0),
    ]))
    story.append(header_table)
    story.append(Spacer(1, 10))
    story.append(HRFlowable(width="100%", thickness=2, color=brand_green, spaceAfter=15))

    # Summary calculations
    total_bills = len(bills)
    total_sales = sum(float(b.get("grand_total", 0)) for b in bills)

    # Metrics Box
    metrics_data = [
        [
            Paragraph("Total Revenue", metric_label),
            Paragraph("Total Orders", metric_label)
        ],
        [
            Paragraph(f"INR {total_sales:,.2f}", metric_value),
            Paragraph(str(total_bills), metric_value)
        ]
    ]
    metrics_table = Table(metrics_data, colWidths=[93*mm, 93*mm])
    metrics_table.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,-1), colors.HexColor("#EBF6ED")),
        ("BOX", (0,0), (-1,-1), 0.8, colors.HexColor("#A1D9B4")),
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
        ("TOPPADDING", (0,0), (-1,-1), 12),
        ("BOTTOMPADDING", (0,0), (-1,-1), 12),
    ]))
    story.append(metrics_table)
    story.append(Spacer(1, 15))

    # "Order Details:" heading
    story.append(Paragraph("<b>Order Details:</b>", ParagraphStyle("SectionTitle", fontSize=13, fontName=FONT_BOLD, textColor=dark_grey, leading=16)))
    story.append(Spacer(1, 8))

    # Bills Table
    col_hdr = [
        Paragraph("<b>S.No</b>", header_center),
        Paragraph("<b>Bill #</b>", header_style),
        Paragraph("<b>Customer</b>", header_style),
        Paragraph("<b>Items</b>", header_center),
        Paragraph("<b>Total</b>", header_style),
        Paragraph("<b>Status</b>", header_style),
        Paragraph("<b>Date</b>", header_style)
    ]
    table_data = [col_hdr]
    
    for idx, b in enumerate(bills):
        # Format Date as YYYY-MM-DD
        dt_str = b.get("date", "")
        try:
            dt_part = dt_str.split("T")[0]
            dt_obj = datetime.strptime(dt_part, "%Y-%m-%d")
            formatted_dt = dt_obj.strftime("%Y-%m-%d")
        except Exception:
            formatted_dt = dt_str.split("T")[0] if "T" in dt_str else dt_str

        # Compute Status
        status = b.get("remarks", "").strip()
        if not status:
            balance = float(b.get("balance", 0.0))
            if balance > 0:
                status = "PENDING"
            else:
                status = "PAID"

        # Bill Number display
        bill_no = b.get("bill_number", b.get("bill_no", ""))
        if len(bill_no) > 16 or "-" in bill_no:
            bill_no_display = bill_no[:8]
        else:
            bill_no_display = bill_no

        table_data.append([
            Paragraph(str(idx + 1), cell_center),
            Paragraph(bill_no_display, cell_style),
            Paragraph(b.get("customer_name", "Walk-in Customer"), cell_style),
            Paragraph(str(b.get("item_count", 0)), cell_center),
            Paragraph(f"{float(b.get('grand_total', 0)):.2f}", cell_style),
            Paragraph(status, cell_style),
            Paragraph(formatted_dt, cell_style)
        ])

    # Widths should sum to exactly 186mm (A4 width 210mm - 24mm margins)
    bills_tbl = Table(table_data, colWidths=[12*mm, 24*mm, 46*mm, 14*mm, 24*mm, 42*mm, 24*mm])
    bills_tbl.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,0), brand_green),
        ("GRID", (0,0), (-1,-1), 0.5, colors.black),
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
        ("TOPPADDING", (0,0), (-1,-1), 8),
        ("BOTTOMPADDING", (0,0), (-1,-1), 8),
        ("LEFTPADDING", (0,0), (-1,-1), 6),
        ("RIGHTPADDING", (0,0), (-1,-1), 6),
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


