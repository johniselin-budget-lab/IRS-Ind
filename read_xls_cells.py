#!/usr/bin/env python3
"""Dump the first sheet of a Pub 1304 .xls as CSV on stdout, one record per
non-empty cell plus one per merged range:

    C,row,col,flag,value      a cell (1-based); value as text, numbers as shortest round-trip repr
    M,first_row,last_row,first_col,last_col   a merged range (1-based inclusive)

Used by alignment_helpers.R::read_bysize_sheet(). It exists because SOI marks
its disclosure flags with NUMBER FORMATS, not text: a cell shown as "* 1,234"
holds 1234 under the format '"* "#,##0', and a cell shown as "**" holds 0
under '"** "#,##0;...'. readxl returns the bare numbers and loses both marks,
so a combined cell reads as a true zero. The flag column carries them:

    caution    format prefix "* "   estimate flagged for sampling variability
    combined   format prefix "** "  combined with another cell to prevent
                                    disclosure; a zero here is not a zero
    ''         anything else

Requires xlrd. It reads both formats in the store: BIFF8 (TY2004 on) and
the BIFF4 of Table 2.3's TY1996-2003 files (TY1997 aside). The flag formats
begin in TY2005; earlier vintages carry none (checked 2026-09-26), so an
empty flag column there is what SOI published, not a reader gap.
"""

import csv
import re
import sys

import xlrd

if len(sys.argv) != 2:
    sys.exit("usage: read_xls_cells.py <file.xls>")

book = xlrd.open_workbook(sys.argv[1], formatting_info=True)
sheet = book.sheet_by_index(0)
out = csv.writer(sys.stdout, lineterminator="\n")

# The flag is decided by the positive section of the format, which every
# flagged format in the store opens with a quoted "* " or "** ".
FLAG_RE = re.compile(r'^"(\*+)\s*"')


def cell_flag(r, c):
    fmt = book.format_map[book.xf_list[sheet.cell_xf_index(r, c)].format_key]
    m = FLAG_RE.match(fmt.format_str)
    if not m:
        return ""
    return "combined" if len(m.group(1)) >= 2 else "caution"


for r in range(sheet.nrows):
    for c in range(sheet.ncols):
        ctype = sheet.cell_type(r, c)
        if ctype in (xlrd.XL_CELL_EMPTY, xlrd.XL_CELL_BLANK):
            continue
        v = sheet.cell_value(r, c)
        if ctype == xlrd.XL_CELL_NUMBER:
            text = repr(v)
            flag = cell_flag(r, c)
        else:
            text = str(v)
            if text.strip() == "":
                continue
            flag = ""
        out.writerow(["C", r + 1, c + 1, flag, text])

for r0, r1, c0, c1 in sorted(sheet.merged_cells):
    # xlrd ranges are 0-based half-open
    out.writerow(["M", r0 + 1, r1, c0 + 1, c1])
