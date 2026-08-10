"""
Invoice export routes - convert invoice images to PDF and upload to Supabase Storage.

Buckets used:
  - erp_billing_system         → customer-facing cash bill (simple receipt)
  - erp_billing_system_company → company GST invoice
"""

import os
import io
import base64
from flask import Blueprint, jsonify, request
from datetime import datetime

invoice_export_bp = Blueprint("invoice_export", __name__, url_prefix="/invoice-export")

# Local fallback folder (kept for debugging)
INVOICES_BASE_PATH = os.path.join(os.path.dirname(__file__), "..", "invoices")

BUCKET_MAP = {
    True:  "erp_billing_system_company",   # company GST invoice
    False: "erp_billing_system",           # customer cash bill
}


def _get_supabase():
    from dotenv import load_dotenv
    from supabase import create_client
    env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
    load_dotenv(env_path, override=True)
    url = os.getenv("SUPABASE_URL", "")
    key = os.getenv("SUPABASE_SERVICE_KEY") or os.getenv("SUPABASE_SECRET_KEY") or ""
    if not url or not key:
        raise ValueError("SUPABASE_URL or key not set in .env")
    from supabase import create_client
    return create_client(url, key)


def _image_bytes_to_pdf(image_bytes: bytes) -> bytes:
    """Convert raw PNG/JPEG bytes → single-page PDF bytes using Pillow."""
    from PIL import Image
    from reportlab.lib.pagesizes import A4
    from reportlab.pdfgen import canvas

    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    img_width, img_height = img.size

    a4_w, a4_h = A4
    scale = min(a4_w / img_width, a4_h / img_height)
    draw_w = img_width * scale
    draw_h = img_height * scale
    x_offset = (a4_w - draw_w) / 2
    y_offset = (a4_h - draw_h) / 2

    pdf_buffer = io.BytesIO()
    c = canvas.Canvas(pdf_buffer, pagesize=A4)
    tmp_img = io.BytesIO()
    img.save(tmp_img, format="PNG")
    tmp_img.seek(0)
    from reportlab.lib.utils import ImageReader
    c.drawImage(ImageReader(tmp_img), x_offset, y_offset, width=draw_w, height=draw_h)
    c.save()
    return pdf_buffer.getvalue()


def _generate_company_invoice_pdf(invoice_no: str) -> bytes:
    """
    Generate a company invoice PDF from DB data that exactly mirrors the
    Flutter InvoicePreview widget layout — including the logo.
    """
    from reportlab.lib.pagesizes import A4
    from reportlab.lib import colors
    from reportlab.lib.units import mm
    from reportlab.platypus import (
        SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer,
        HRFlowable, Image as RLImage,
    )
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.enums import TA_CENTER, TA_RIGHT, TA_LEFT
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    # ── Fonts ─────────────────────────────────────────────────────────────
    try:
        pdfmetrics.registerFont(TTFont("DJ",  "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"))
        pdfmetrics.registerFont(TTFont("DJB", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"))
        pdfmetrics.registerFont(TTFont("DJI", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf"))
        R, B, I = "DJ", "DJB", "DJI"
    except Exception:
        R, B, I = "Helvetica", "Helvetica-Bold", "Helvetica-Oblique"

    NAVY  = colors.HexColor("#1B2A4A")
    LBLUE = colors.HexColor("#F3F6FC")
    HBLU  = colors.HexColor("#E7ECF6")
    WHITE = colors.white

    def ps(name, size=9, font=R, color=colors.black, align=TA_LEFT, leading=None):
        kw = dict(fontSize=size, fontName=font, textColor=color, alignment=align)
        if leading:
            kw["leading"] = leading
        return ParagraphStyle(name, **kw)

    # ── DB fetch ──────────────────────────────────────────────────────────
    print(f"[_generate_company_invoice_pdf] Fetching DB data for invoice: {invoice_no}")
    sb = _get_supabase()
    hdr_rows = sb.table("erp_billing_system_company").select("*").eq("invoice_no", invoice_no).execute().data
    if not hdr_rows:
        print(f"[_generate_company_invoice_pdf] ERROR: No rows found for invoice: {invoice_no}")
        raise ValueError(f"Company invoice {invoice_no} not found in DB")
    hdr = hdr_rows[0]
    print(f"[_generate_company_invoice_pdf] Found header: invoice_id={hdr.get('invoice_id')}, customer={hdr.get('customer_name')}")
    items = sb.table("erp_billing_system_company_items") \
        .select("*").eq("invoice_id", hdr["invoice_id"]).order("sno").execute().data
    print(f"[_generate_company_invoice_pdf] Found {len(items)} items")

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4,
                            leftMargin=14*mm, rightMargin=14*mm,
                            topMargin=12*mm, bottomMargin=12*mm)
    story = []

    # ── 1. TOP HEADER ─────────────────────────────────────────────────────
    LOGO_PATH = os.path.join(os.path.dirname(__file__), "..", "company_logo.jpg")
    logo_cell = Spacer(22*mm, 22*mm)
    if os.path.exists(LOGO_PATH):
        try:
            logo_cell = RLImage(LOGO_PATH, width=22*mm, height=22*mm)
        except Exception:
            pass

    inv_date = hdr.get("invoice_date", "")
    inv_time = hdr.get("invoice_time", "") or ""
    try:
        from datetime import datetime as _dt
        inv_date_fmt = _dt.strptime(inv_date, "%Y-%m-%d").strftime("%d %b %Y").lstrip("0")
    except Exception:
        inv_date_fmt = inv_date
    try:
        from datetime import datetime as _dt
        inv_time_fmt = _dt.strptime(inv_time, "%H:%M:%S").strftime("%I:%M %p").lstrip("0")
    except Exception:
        inv_time_fmt = inv_time

    meta_box = Table(
        [[Paragraph(f"<b>Invoice No:</b>  {invoice_no}", ps("m1", 9, R, NAVY))],
         [Paragraph(f"<b>Date:</b>  {inv_date_fmt}",      ps("m2", 9, R, NAVY))],
         [Paragraph(f"<b>Time:</b>  {inv_time_fmt}",      ps("m3", 9, R, NAVY))]],
        colWidths=[52*mm],
    )
    meta_box.setStyle(TableStyle([
        ("BOX",           (0,0), (-1,-1), 0.5, colors.HexColor("#CCCCCC")),
        ("BACKGROUND",    (0,0), (-1,-1), LBLUE),
        ("LEFTPADDING",   (0,0), (-1,-1), 6),
        ("RIGHTPADDING",  (0,0), (-1,-1), 6),
        ("TOPPADDING",    (0,0), (-1,-1), 4),
        ("BOTTOMPADDING", (0,0), (-1,-1), 4),
    ]))

    logo_name_tbl = Table(
        [[logo_cell, Paragraph("<b>VELA AGENCY</b>", ps("cn", 16, B, NAVY))]],
        colWidths=[24*mm, 80*mm],
    )
    logo_name_tbl.setStyle(TableStyle([
        ("VALIGN",        (0,0), (-1,-1), "MIDDLE"),
        ("LEFTPADDING",   (0,0), (-1,-1), 0),
        ("RIGHTPADDING",  (0,0), (-1,-1), 0),
        ("TOPPADDING",    (0,0), (-1,-1), 0),
        ("BOTTOMPADDING", (0,0), (-1,-1), 0),
    ]))

    addr_info = (
        "Burgur Road, Vellai Pillaiyar Kovil, Anthiyur, Tamil Nadu.\n"
        "<b>GSTIN:</b>  33BAZPM1155J1ZB\n"
        "<b>FSSAI:</b>  SAMPLE-FSSAI\n"
        "<b>PAN:</b>  BAZM115J\n"
        "<b>Phone:</b>  +91 986522355\n"
        "<b>Email:</b>  velaagency27@gmail.com"
    )
    addr_para = Paragraph(addr_info, ps("addr", 9, R, colors.HexColor("#333333"), leading=14))

    header_tbl = Table(
        [[logo_name_tbl, meta_box],
         [addr_para,      ""]],
        colWidths=["62%", "38%"],
    )
    header_tbl.setStyle(TableStyle([
        ("VALIGN",        (0,0), (-1,-1), "TOP"),
        ("SPAN",          (1,0), (1,1)),
        ("ALIGN",         (1,0), (1,1), "RIGHT"),
        ("LEFTPADDING",   (0,0), (-1,-1), 0),
        ("RIGHTPADDING",  (0,0), (-1,-1), 0),
        ("TOPPADDING",    (0,0), (-1,-1), 3),
        ("BOTTOMPADDING", (0,0), (-1,-1), 3),
    ]))
    story.append(header_tbl)
    story.append(HRFlowable(width="100%", thickness=0.8,
                             color=colors.HexColor("#CCCCCC"), spaceAfter=10))

    # ── 2. BILL TO ────────────────────────────────────────────────────────
    cust_name  = hdr.get("customer_name", "Walk-in Customer")
    cust_phone = hdr.get("customer_phone", "") or ""
    cust_addr  = f"Phone: {cust_phone}" if cust_phone else "Walk-in Customer"

    story.append(Paragraph("BILL TO", ps("bt_lbl", 9, B, NAVY)))
    story.append(Spacer(1, 4))
    story.append(Paragraph(f"<b>{cust_name}</b>", ps("bt_name", 14, B, NAVY)))
    story.append(Spacer(1, 3))
    story.append(Paragraph(cust_addr,
                            ps("bt_addr", 9.5, R, colors.HexColor("#555555"))))
    story.append(HRFlowable(width="100%", thickness=0.5,
                             color=colors.HexColor("#CCCCCC"),
                             spaceBefore=10, spaceAfter=10))

    # ── 3. ITEMS TABLE ────────────────────────────────────────────────────
    col_hdr = [
        Paragraph("<b>S.NO</b>",        ps("ch0", 9, B, NAVY, TA_CENTER)),
        Paragraph("<b>DESCRIPTION</b>", ps("ch1", 9, B, NAVY, TA_LEFT)),
        Paragraph("<b>UNIT</b>",        ps("ch2", 9, B, NAVY, TA_CENTER)),
        Paragraph("<b>QTY</b>",         ps("ch3", 9, B, NAVY, TA_CENTER)),
        Paragraph("<b>RATE</b>",        ps("ch4", 9, B, NAVY, TA_RIGHT)),
        Paragraph("<b>AMOUNT</b>",      ps("ch5", 9, B, NAVY, TA_RIGHT)),
    ]
    tbl_data = [col_hdr]
    for idx, row in enumerate(items):
        amt  = float(row.get("amount", 0))
        rate = float(row.get("rate", 0))
        qty  = float(row.get("quantity", 0))
        unit = row.get("unit", "Nos")
        desc = row.get("description", "")
        desc_para = Paragraph(
            f"{desc}<br/><font size='7.5' color='#888888'>Unit: {unit}</font>",
            ps("cd1", 9, R, colors.black, TA_LEFT, leading=13)
        )
        tbl_data.append([
            Paragraph(str(row.get("sno", idx + 1)), ps("cd0", 9, R, colors.black, TA_CENTER)),
            desc_para,
            Paragraph(unit,                ps("cd2", 9, R, colors.black, TA_CENTER)),
            Paragraph(f"{qty:.2f}",        ps("cd3", 9, R, colors.black, TA_CENTER)),
            Paragraph(f"{rate:.2f}",       ps("cd4", 9, R, colors.black, TA_RIGHT)),
            Paragraph(f"<b>{amt:.2f}</b>", ps("cd5", 9, B, colors.black, TA_RIGHT)),
        ])

    items_tbl = Table(tbl_data,
                      colWidths=[12*mm, 72*mm, 20*mm, 20*mm, 24*mm, 28*mm])
    items_tbl.setStyle(TableStyle([
        ("BACKGROUND",    (0,0), (-1,0), HBLU),
        ("ROWBACKGROUNDS",(0,1), (-1,-1), [WHITE, LBLUE]),
        ("GRID",          (0,0), (-1,-1), 0.3, colors.HexColor("#CCCCCC")),
        ("VALIGN",        (0,0), (-1,-1), "MIDDLE"),
        ("TOPPADDING",    (0,0), (-1,-1), 6),
        ("BOTTOMPADDING", (0,0), (-1,-1), 6),
        ("LEFTPADDING",   (0,0), (-1,-1), 5),
        ("RIGHTPADDING",  (0,0), (-1,-1), 5),
    ]))
    story.append(items_tbl)
    story.append(HRFlowable(width="100%", thickness=0.3,
                             color=colors.HexColor("#CCCCCC"),
                             spaceBefore=0, spaceAfter=12))

    # ── 4. PAYMENT + TOTAL ────────────────────────────────────────────────
    total   = float(hdr.get("total_amount", 0))
    words   = hdr.get("amount_in_words", "")
    payment = hdr.get("payment_mode", "Cash")
    txn_id  = hdr.get("transaction_id", invoice_no) or invoice_no
    upi_id  = hdr.get("upi_id") or "N/A"

    pay_lines = [
        Paragraph("PAYMENT DETAILS", ps("pl", 9, B, NAVY)),
        Spacer(1, 5),
        Paragraph(f"<b>Mode:</b>  {payment}", ps("pm", 9, R, colors.black)),
        Paragraph(f"<b>Txn ID:</b>  {txn_id}", ps("pt", 9, R, colors.black)),
        Paragraph(f"<b>UPI ID:</b>  {upi_id}", ps("pu", 9, R, colors.black)),
    ]

    total_box = Table(
        [[Paragraph("<b>TOTAL AMOUNT</b>", ps("ta", 10, B, WHITE)),
          Paragraph(f"<b>₹{total:,.2f}</b>", ps("tv", 13, B, WHITE, TA_RIGHT))]],
        colWidths=[45*mm, 38*mm],
    )
    total_box.setStyle(TableStyle([
        ("BACKGROUND",    (0,0), (-1,-1), NAVY),
        ("TOPPADDING",    (0,0), (-1,-1), 8),
        ("BOTTOMPADDING", (0,0), (-1,-1), 8),
        ("LEFTPADDING",   (0,0), (-1,-1), 10),
        ("RIGHTPADDING",  (0,0), (-1,-1), 10),
        ("VALIGN",        (0,0), (-1,-1), "MIDDLE"),
    ]))

    words_para = Paragraph(
        f"<i>Words: {words}</i>",
        ps("wp", 8, I, colors.HexColor("#666666"), TA_RIGHT)
    ) if words else Spacer(1, 1)

    pay_tbl = Table(
        [[pay_lines, [total_box, Spacer(1, 6), words_para]]],
        colWidths=["50%", "50%"],
    )
    pay_tbl.setStyle(TableStyle([
        ("VALIGN",       (0,0), (-1,-1), "TOP"),
        ("LEFTPADDING",  (0,0), (-1,-1), 0),
        ("RIGHTPADDING", (0,0), (-1,-1), 0),
    ]))
    story.append(pay_tbl)
    story.append(Spacer(1, 14))

    # ── 5. BANK + SIGNATURE ───────────────────────────────────────────────
    bank_lines = [
        Paragraph("BANK DETAILS", ps("bk", 9, B, NAVY)),
        Spacer(1, 5),
        Paragraph("<b>Bank:</b>  HDFC Bank",    ps("b1", 9, R, colors.black)),
        Paragraph("<b>A/C:</b>  50200120799532", ps("b2", 9, R, colors.black)),
        Paragraph("<b>IFSC:</b>  HDFC0004901",  ps("b3", 9, R, colors.black)),
    ]

    sig_inner = Table(
        [[Paragraph("FOR VELA AGENCY",
                    ps("fva", 8, R, colors.HexColor("#888888")))],
         [Spacer(1, 22)],
         [HRFlowable(width="100%", thickness=0.5,
                     color=colors.HexColor("#BBBBBB"))],
         [Paragraph("Authorized Signatory", ps("sig", 9, R, colors.black))]],
        colWidths=["100%"],
    )
    sig_inner.setStyle(TableStyle([
        ("BOX",           (0,0), (-1,-1), 0.5, colors.HexColor("#CCCCCC")),
        ("TOPPADDING",    (0,0), (-1,-1), 8),
        ("BOTTOMPADDING", (0,0), (-1,-1), 8),
        ("LEFTPADDING",   (0,0), (-1,-1), 10),
        ("RIGHTPADDING",  (0,0), (-1,-1), 10),
    ]))

    bank_sig_tbl = Table(
        [[bank_lines, sig_inner]],
        colWidths=["55%", "45%"],
    )
    bank_sig_tbl.setStyle(TableStyle([
        ("VALIGN",       (0,0), (-1,-1), "TOP"),
        ("LEFTPADDING",  (0,0), (-1,-1), 0),
        ("RIGHTPADDING", (0,0), (-1,-1), 0),
    ]))
    story.append(bank_sig_tbl)
    story.append(Spacer(1, 14))

    # ── 6. FOOTER ─────────────────────────────────────────────────────────
    footer_tbl = Table(
        [[Paragraph("<b>Thank you for your business.</b>",
                    ps("f1", 11, B, NAVY, TA_CENTER))],
         [Paragraph(
             "We declare that this invoice shows the actual price of the goods "
             "described and that all particulars are true and correct",
             ps("f2", 8.5, R, colors.HexColor("#666666"), TA_CENTER))]],
        colWidths=["100%"],
    )
    footer_tbl.setStyle(TableStyle([
        ("BACKGROUND",    (0,0), (-1,-1), LBLUE),
        ("TOPPADDING",    (0,0), (-1,-1), 8),
        ("BOTTOMPADDING", (0,0), (-1,-1), 8),
        ("LEFTPADDING",   (0,0), (-1,-1), 10),
        ("RIGHTPADDING",  (0,0), (-1,-1), 10),
    ]))
    story.append(footer_tbl)

    doc.build(story)
    return buf.getvalue()


# ---------------------------------------------------------------------------
# POST /invoice-export/save  (customer bill image → erp_billing_system bucket)
# ---------------------------------------------------------------------------

@invoice_export_bp.post("/save")
def save_invoice_image():
    """
    Accepts a base64-encoded PNG/JPEG image, converts it to PDF,
    and uploads it to the correct Supabase Storage bucket.

    Body (JSON):
    {
      "invoice_number": "2026AUG08A161",
      "image_data": "<base64-encoded PNG/JPEG>",
      "is_company_invoice": false     ← always false; company uses /generate-company
    }
    """
    payload = request.get_json(silent=True)
    if not payload:
        return jsonify({"success": False, "message": "Invalid or missing JSON body"}), 400

    invoice_number = payload.get("invoice_number")
    image_data     = payload.get("image_data")
    is_company_raw = payload.get("is_company_invoice", False)
    # Accept real booleans, JSON strings and string "false"/"true" correctly.
    if isinstance(is_company_raw, str):
        is_company = is_company_raw.strip().lower() in ("true", "1", "yes")
    else:
        is_company = bool(is_company_raw)

    if not invoice_number or not image_data:
        return jsonify({"success": False,
                        "message": "invoice_number and image_data are required"}), 400

    try:
        image_bytes = base64.b64decode(image_data)
    except Exception:
        return jsonify({"success": False, "message": "image_data is not valid base64"}), 400

    try:
        pdf_bytes    = _image_bytes_to_pdf(image_bytes)
        bucket       = BUCKET_MAP[is_company]
        file_name    = f"{invoice_number}.pdf"

        sb = _get_supabase()
        sb.storage.from_(bucket).upload(
            path=file_name,
            file=pdf_bytes,
            file_options={"content-type": "application/pdf", "upsert": "true"},
        )
        public_url = sb.storage.from_(bucket).get_public_url(file_name)

        # Local PNG fallback for debugging
        folder_path = os.path.join(INVOICES_BASE_PATH,
                                   "company_invoices" if is_company else "customer_bills")
        os.makedirs(folder_path, exist_ok=True)
        with open(os.path.join(folder_path, f"{invoice_number}.png"), "wb") as f:
            f.write(image_bytes)

        return jsonify({
            "success":   True,
            "message":   "Invoice converted to PDF and uploaded to Supabase Storage",
            "file_name": file_name,
            "bucket":    bucket,
            "url":       public_url,
            "pdf_size":  len(pdf_bytes),
        }), 201

    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({"success": False, "message": f"Error: {str(e)}"}), 500


# ---------------------------------------------------------------------------
# POST /invoice-export/generate-company/<invoice_number>
# Generates company invoice PDF from DB data → uploads to erp_billing_system_company
# ---------------------------------------------------------------------------

@invoice_export_bp.post("/generate-company/<invoice_number>")
def generate_company_invoice(invoice_number: str):
    """
    Generate and upload company invoice PDF entirely server-side.
    First tries to read from erp_billing_system_company DB table.
    If not found, accepts bill data in the request body as fallback.

    Optional body (JSON) for fallback:
    {
      "customer_name": "Walk-in Customer",
      "customer_phone": "",
      "payment_mode": "Cash",
      "total_amount": 296.27,
      "amount_in_words": "Two Hundred...",
      "invoice_date": "2026-08-08",
      "invoice_time": "18:04:00",
      "items": [
        {"sno": 1, "description": "3 Rose 250g", "unit": "Nos", "quantity": 1.0, "rate": 207.29, "amount": 207.29}
      ]
    }
    """
    print(f"[generate_company_invoice] REQUEST received for invoice: {invoice_number}")
    try:
        pdf_bytes = _generate_company_invoice_pdf(invoice_number)
        print(f"[generate_company_invoice] PDF generated successfully: {len(pdf_bytes)} bytes")
    except ValueError:
        # DB record not found — try to build from request body fallback
        print(f"[generate_company_invoice] DB record not found for: {invoice_number}")
        payload = request.get_json(silent=True) or {}
        if not payload:
            print(f"[generate_company_invoice] ERROR: No fallback data in request body")
            return jsonify({
                "success": False,
                "message": f"Company invoice {invoice_number} not in DB and no fallback data provided"
            }), 404
        print(f"[generate_company_invoice] Using fallback data from request body")
        try:
            pdf_bytes = _generate_company_invoice_pdf_from_payload(invoice_number, payload)
        except Exception as e:
            import traceback; traceback.print_exc()
            return jsonify({"success": False, "message": f"Fallback PDF error: {str(e)}"}), 500
    except Exception as e:
        import traceback; traceback.print_exc()
        print(f"[generate_company_invoice] ERROR generating PDF: {str(e)}")
        return jsonify({"success": False, "message": f"Error: {str(e)}"}), 500

    try:
        file_name = f"{invoice_number}.pdf"
        sb = _get_supabase()
        print(f"[generate_company_invoice] Uploading to bucket: erp_billing_system_company")
        sb.storage.from_("erp_billing_system_company").upload(
            path=file_name,
            file=pdf_bytes,
            file_options={"content-type": "application/pdf", "upsert": "true"},
        )
        public_url = sb.storage.from_("erp_billing_system_company").get_public_url(file_name)
        print(f"[generate_company_invoice] SUCCESS: Uploaded {file_name} → erp_billing_system_company")

        return jsonify({
            "success":   True,
            "message":   "Company invoice PDF generated and uploaded",
            "file_name": file_name,
            "bucket":    "erp_billing_system_company",
            "url":       public_url,
            "pdf_size":  len(pdf_bytes),
        }), 201
    except Exception as e:
        import traceback; traceback.print_exc()
        print(f"[generate_company_invoice] ERROR uploading to bucket: {str(e)}")
        return jsonify({"success": False, "message": f"Upload error: {str(e)}"}), 500


def _generate_company_invoice_pdf_from_payload(invoice_no: str, payload: dict) -> bytes:
    """Same as _generate_company_invoice_pdf but uses dict payload instead of DB lookup."""
    from reportlab.lib.pagesizes import A4
    from reportlab.lib import colors
    from reportlab.lib.units import mm
    from reportlab.platypus import (
        SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, HRFlowable
    )
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.enums import TA_CENTER, TA_RIGHT, TA_LEFT
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    try:
        pdfmetrics.registerFont(TTFont("DejaVu",      "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"))
        pdfmetrics.registerFont(TTFont("DejaVu-Bold", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"))
        FONT_REG  = "DejaVu"
        FONT_BOLD = "DejaVu-Bold"
    except Exception:
        FONT_REG  = "Helvetica"
        FONT_BOLD = "Helvetica-Bold"

    styles = getSampleStyleSheet()
    navy   = colors.HexColor("#1B2A4A")
    light  = colors.HexColor("#F3F6FC")

    bold_style   = ParagraphStyle("bold",  fontSize=9, fontName=FONT_BOLD, textColor=navy, alignment=TA_LEFT)
    right_style  = ParagraphStyle("right", fontSize=9, fontName=FONT_REG, alignment=TA_RIGHT)
    center_style = ParagraphStyle("ctr",   fontSize=9, fontName=FONT_REG, alignment=TA_CENTER)
    normal_style = ParagraphStyle("norm",  fontSize=9, fontName=FONT_REG, textColor=colors.black)

    hdr   = payload
    items = payload.get("items", [])

    inv_date = hdr.get("invoice_date", datetime.now().strftime("%Y-%m-%d"))
    inv_time = hdr.get("invoice_time", "") or ""

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, leftMargin=15*mm, rightMargin=15*mm, topMargin=12*mm, bottomMargin=12*mm)
    story = []

    header_data = [
        [Paragraph("<b>VELA AGENCY</b>", ParagraphStyle("h", fontSize=16, fontName=FONT_BOLD, textColor=navy)),
         Paragraph("<b>TAX INVOICE</b>", ParagraphStyle("h2", fontSize=14, fontName=FONT_BOLD, textColor=navy, alignment=TA_RIGHT))],
        [Paragraph("Burgur Road, Vellai Pillaiyar Kovil, Anthiyur, Tamil Nadu.<br/>GSTIN: 33BAZPM1155J1ZB | PAN: BAZM115J<br/>Phone: +91 9865223355 | Email: velaagency27@gmail.com",
                   ParagraphStyle("addr", fontSize=8, fontName=FONT_REG, textColor=colors.HexColor("#444444"))),
         Paragraph(f"Invoice No: <b>{invoice_no}</b><br/>Date: <b>{inv_date}</b><br/>Time: <b>{inv_time}</b>",
                   ParagraphStyle("meta", fontSize=9, fontName=FONT_REG, alignment=TA_RIGHT, textColor=navy))],
    ]
    header_tbl = Table(header_data, colWidths=["55%", "45%"])
    header_tbl.setStyle(TableStyle([("VALIGN", (0,0), (-1,-1), "TOP"), ("BOTTOMPADDING", (0,0), (-1,-1), 4)]))
    story.append(header_tbl)
    story.append(HRFlowable(width="100%", thickness=1, color=navy, spaceAfter=6))

    cust_name  = hdr.get("customer_name", "Walk-in Customer")
    cust_phone = hdr.get("customer_phone", "") or ""
    cust_addr  = f"Phone: {cust_phone}" if cust_phone else "Walk-in Customer"
    payment    = hdr.get("payment_mode", "Cash")
    txn_id     = hdr.get("transaction_id", invoice_no) or invoice_no

    bill_to_data = [[
        Paragraph(f"<b>BILL TO</b><br/><font size=12><b>{cust_name}</b></font><br/>{cust_addr}",
                  ParagraphStyle("bt", fontSize=9, fontName=FONT_REG, textColor=navy)),
        Paragraph(f"<b>PAYMENT DETAILS</b><br/>Mode: {payment}<br/>Txn ID: {txn_id}",
                  ParagraphStyle("pd", fontSize=9, fontName=FONT_REG, textColor=navy, alignment=TA_RIGHT)),
    ]]
    bill_to_tbl = Table(bill_to_data, colWidths=["55%", "45%"])
    bill_to_tbl.setStyle(TableStyle([("VALIGN", (0,0), (-1,-1), "TOP"), ("BOTTOMPADDING", (0,0), (-1,-1), 6)]))
    story.append(bill_to_tbl)
    story.append(HRFlowable(width="100%", thickness=0.5, color=colors.grey, spaceAfter=6))

    col_hdr = [Paragraph("<b>S.NO</b>", center_style), Paragraph("<b>DESCRIPTION</b>", bold_style),
               Paragraph("<b>UNIT</b>", center_style), Paragraph("<b>QTY</b>", center_style),
               Paragraph("<b>RATE (₹)</b>", right_style), Paragraph("<b>AMOUNT (₹)</b>", right_style)]
    table_data = [col_hdr]
    for row in items:
        amt = float(row.get("amount", 0))
        table_data.append([
            Paragraph(str(row.get("sno", "")), center_style),
            Paragraph(str(row.get("description", "")), normal_style),
            Paragraph(str(row.get("unit", "Nos")), center_style),
            Paragraph(str(row.get("quantity", "")), center_style),
            Paragraph(f"{float(row.get('rate', 0)):.2f}", right_style),
            Paragraph(f"{amt:.2f}", right_style),
        ])
    items_tbl = Table(table_data, colWidths=[10*mm, 70*mm, 20*mm, 20*mm, 25*mm, 30*mm])
    items_tbl.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,0), colors.HexColor("#E7ECF6")), ("TEXTCOLOR", (0,0), (-1,0), navy),
        ("GRID", (0,0), (-1,-1), 0.4, colors.HexColor("#CCCCCC")),
        ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, light]),
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"), ("TOPPADDING", (0,0), (-1,-1), 5), ("BOTTOMPADDING", (0,0), (-1,-1), 5),
    ]))
    story.append(items_tbl)
    story.append(Spacer(1, 6))

    total = float(hdr.get("total_amount", 0))
    words = hdr.get("amount_in_words", "")
    total_data = [["", "", "", "",
        Paragraph("<b>GRAND TOTAL</b>", ParagraphStyle("gt", fontSize=11, fontName=FONT_BOLD, textColor=colors.white, alignment=TA_RIGHT)),
        Paragraph(f"<b>₹ {total:.2f}</b>", ParagraphStyle("gtv", fontSize=11, fontName=FONT_BOLD, textColor=colors.white, alignment=TA_RIGHT))]]
    total_tbl = Table(total_data, colWidths=[10*mm, 70*mm, 20*mm, 20*mm, 25*mm, 30*mm])
    total_tbl.setStyle(TableStyle([("BACKGROUND", (4,0), (-1,0), navy), ("SPAN", (0,0), (3,0)),
                                    ("TOPPADDING", (0,0), (-1,-1), 6), ("BOTTOMPADDING", (0,0), (-1,-1), 6)]))
    story.append(total_tbl)
    if words:
        story.append(Paragraph(f"<i>Amount in Words: {words}</i>",
                               ParagraphStyle("words", fontSize=8, fontName=FONT_REG, textColor=colors.grey, alignment=TA_RIGHT)))
    story.append(Spacer(1, 10))
    story.append(HRFlowable(width="100%", thickness=0.5, color=colors.grey, spaceAfter=4))
    story.append(Paragraph(
        "Thank you for your business. We declare that this invoice shows the actual price of the goods described and that all particulars are true and correct.",
        ParagraphStyle("footer", fontSize=7.5, fontName=FONT_REG, textColor=colors.grey, alignment=TA_CENTER)
    ))
    doc.build(story)
    return buf.getvalue()


# ---------------------------------------------------------------------------
# GET /invoice-export/list/<bucket>
# ---------------------------------------------------------------------------

@invoice_export_bp.get("/list/<bucket>")
def list_invoices(bucket: str):
    """
    GET /invoice-export/list/company_invoices
    GET /invoice-export/list/customer_bills
    Returns a list of PDF files in the given Supabase bucket.
    """
    if bucket not in ("erp_billing_system_company", "erp_billing_system"):
        return jsonify({"success": False, "message": "Invalid bucket name"}), 400

    try:
        sb = _get_supabase()
        files = sb.storage.from_(bucket).list()
        invoices = [
            {
                "file_name":      f.get("name", ""),
                "invoice_number": f.get("name", "").replace(".pdf", ""),
                "size":           (f.get("metadata") or {}).get("size", 0),
                "created_at":     f.get("created_at", ""),
                "url":            sb.storage.from_(bucket).get_public_url(f.get("name", "")),
            }
            for f in files
            if isinstance(f, dict) and f.get("name", "").endswith(".pdf")
        ]
        return jsonify({"success": True, "bucket": bucket, "invoices": invoices}), 200

    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


# ---------------------------------------------------------------------------
# GET /invoice-export/download/<bucket>/<invoice_number>
# ---------------------------------------------------------------------------

@invoice_export_bp.get("/download/<bucket>/<invoice_number>")
def get_invoice_url(bucket: str, invoice_number: str):
    """Returns a signed URL (60 min) for downloading a specific PDF."""
    if bucket not in ("erp_billing_system_company", "erp_billing_system"):
        return jsonify({"success": False, "message": "Invalid bucket name"}), 400

    try:
        sb  = _get_supabase()
        res = sb.storage.from_(bucket).create_signed_url(
            path=f"{invoice_number}.pdf",
            expires_in=3600,
        )
        return jsonify({"success": True, "url": res["signedURL"]}), 200

    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500
