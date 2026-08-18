#!/usr/bin/env python3
"""Extract line-item estimates from the SOI Pub 4801 line item estimate PDFs.

Each data page is a vector facsimile of a tax form with the estimate printed
in that line's entry box. For every page this recovers the form, the universe
(all returns vs electronically filed), whether the page carries counts or
amounts, and each line's label and value.

Outputs, under the download destination:
  aligned/line_items.csv      one row per (year, form, universe, line, measure)
  checks/line_item_values.csv the subset run_checks.R compares to Pub 1304

Usage:  python3 parse_line_items.py <dest> [first_year] [last_year]

Defaults to the validated years, TY2018-2023 (see notes/line_items.md): from
TY2017 back, a vintage repeats the Form 1040 under two or three universes that
the table of contents does not separate here, so the same line appears more
than once and the universe column would be wrong. Earlier years can be
requested explicitly; the run warns about every ambiguity it finds. The
cover-page total is unaffected and is read for every year present.

Needs PyMuPDF (`import fitz`). NOTE: on this cluster `module load R/...` swaps
the Python environment and hides it -- run this in a shell without R loaded.

See notes/line_items.md for the vintage traps this had to absorb.
"""
import csv
import os
import re
import sys
from collections import Counter

import fitz

NUMERIC = re.compile(r'^\d{1,3}(,\d{3})*$|^\d{3,}$')
LINE_LABEL = re.compile(r'^\d{1,2}[a-z]?$')
DOT_LEADER = re.compile(r'^[.\u2024\u2219\u00b7\u25b6]+$')   # the forms' leader dots
MAX_LABEL_GAP = 40  # pt between a line label and its estimate
BOX_Y_TOL = 8       # pt a value may sit outside its drawn box (TY2018 prints above)

# Page markers. Vintages differ in case (TY2011 shouts) and TY2013 typesets
# "filed" with an fi ligature that extracts as "fi led", so text is normalised
# and the patterns tolerate a gap inside the word.
RETURNS_MARKER = re.compile(r'number of returns f\s*i\s*led', re.I)
AMOUNTS_MARKER = re.compile(r'amounts of selected lines f\s*i\s*led', re.I)

# Bottom-of-form legend: "Form 1040 (2023)", "Schedule C (Form 1040) 2023",
# revision-dated forms such as "Form 965-A (Rev. 1-2021)" and "Form 965-A
# (1-2019)" -- the same form, one vintage with the "Rev." prefix and one
# without -- and the TY2019-20 vintages that name two parent forms:
# "Schedule 1 (Form 1040 or 1040-SR) 2019".
LEGEND = re.compile(r'^(?P<name>Form\s+[\w-]+|Schedule\s+[\w-]+)\s*'
                    r'(?:\(Form[^)]*\))?\s*'
                    r'(?:\(?(?:Rev\.\s*)?\d{0,2}-?20\d\d\)?)$')

TOC_ENTRY = re.compile(r'^(?P<title>.+?)[^\w\s)]{2,}\s*(?P<page>\d{1,3})\s*$')
TOTAL_RETURNS = re.compile(
    r'([\d,]{7,})\s+Total,?\s+all individual returns\s+f\s*i\s*led', re.I)

# Form 1040 line carrying AGI, by tax year. TY2019 is the only year it sits on
# line 8b: the TY2020 redesign moved it to line 11, where it has stayed.
AGI_LINE = dict([(y, '37') for y in range(2003, 2018)] +
                [(2018, '7'), (2019, '8b'), (2020, '11'),
                 (2021, '11'), (2022, '11'), (2023, '11')])


def normalise(text):
    return re.sub(r'\s+', ' ', text.replace('ﬁ', 'fi').replace('ﬂ', 'fl'))


#--------------------
# Page-level geometry
#--------------------

def label_columns(words, min_members=4):
    """x positions where the form prints its line numbers.

    Forms print each line number twice -- once left of the description and
    again beside the entry column -- and both are real label columns. Body
    text is full of numerals that look like labels ("Schedule 1, line 22"),
    so only x positions several label-shaped tokens share are trusted.
    """
    counts = Counter(round(w[0] / 2) * 2
                     for w in words if LINE_LABEL.match(w[4]))
    return {x for x, n in counts.items() if n >= min_members}


def boxes(page):
    """The form's drawn entry cells, where it paints them as rectangles."""
    return [d['rect'] for d in page.get_drawings()
            if 25 < d['rect'].width < 130 and 7 < d['rect'].height < 16]


def line_values(page):
    """[(line label, value, description)] for the estimates printed on a page.

    A candidate is a numeric token immediately to the right of a line label
    standing in one of the form's label columns. Anchoring on the label rather
    than on a drawn entry box is what makes this work across forms: the 1040
    paints filled rectangles behind its entry cells, but most schedules rule
    theirs with bare line segments, so box detection finds nothing on them.

    A candidate still has to look like an entry rather than prose, because
    forms are full of cross-references that sit right beside a label -- "19 If
    line 18 is more than line 15" put the 18 one label-width from the 19 and
    published it as line 19's estimate. So a candidate is kept only if it is
    either inside one of the drawn boxes, or ends its row: an estimate is
    printed in the entry column with nothing after it, while a cross-reference
    has the rest of its sentence to the right.
    """
    words = page.get_text('words')
    columns = label_columns(words)
    labels = [w for w in words if LINE_LABEL.match(w[4])
              and any(abs(w[0] - x) <= 3 for x in columns)]
    bs = boxes(page)
    out = []
    for w in words:
        if not NUMERIC.match(w[4]):
            continue
        cx, cy = (w[0] + w[2]) / 2, (w[1] + w[3]) / 2
        left = [l for l in labels
                if l[2] < w[0] and w[0] - l[2] <= MAX_LABEL_GAP
                and abs((l[1] + l[3]) / 2 - cy) <= 5]
        if not left:
            continue
        label = max(left, key=lambda l: l[2])
        if label[4] == w[4] and label[0] == w[0]:
            continue

        in_box = any(b.x0 <= cx <= b.x1 and b.y0 - BOX_Y_TOL <= cy <= b.y1 + BOX_Y_TOL
                     for b in bs)
        after = [t for t in words
                 if abs((t[1] + t[3]) / 2 - cy) <= 5 and t[0] > w[2] + 1
                 and not DOT_LEADER.match(t[4])]
        if not in_box and after:
            continue

        # Best-effort description. A wrapped line puts half of it a row above,
        # so this can be only the tail -- never key anything on it.
        desc = ' '.join(t[4] for t in words
                        if abs((t[1] + t[3]) / 2 - cy) <= 5 and t[2] < w[0])
        out.append((label[4], w[4], desc.strip()[:120]))
    return out


def page_form(page):
    for raw in page.get_text().split('\n'):
        m = LEGEND.match(raw.strip())
        if m:
            return re.sub(r'\s+', ' ', m.group('name'))
    return None


def printed_page(page):
    for raw in page.get_text().split('\n')[:4]:
        line = raw.strip()
        if line.isdigit() and len(line) <= 3:
            return int(line)
    return None


#---------------------
# Document structure
#---------------------

def toc_sections(doc, max_page=12):
    """[(heading, kind, printed page)] from the table of contents."""
    out, heading = [], None
    for i in range(min(max_page, doc.page_count)):
        text = doc[i].get_text()
        if 'Contents' not in text and not out:
            continue
        for raw in text.split('\n'):
            line = raw.strip()
            if not line:
                continue
            m = TOC_ENTRY.match(line)
            if m and m.group('title').strip() in ('Returns', 'Amounts'):
                out.append((heading, m.group('title').strip(), int(m.group('page'))))
            elif not m and len(line) > 3 and not line[0].isdigit():
                heading = line
    return out


def classify(doc):
    """One record per data page: form, universe and measure."""
    toc = toc_sections(doc)
    starts = sorted({p for _, _, p in toc})
    universe_at = {p: ('electronically filed'
                       if heading and 'Electronically Filed' in heading
                       else 'all returns')
                   for heading, _, p in toc}

    pages = []
    for i in range(doc.page_count):
        text = normalise(doc[i].get_text())
        measure = ('returns' if RETURNS_MARKER.search(text) else
                   'amount' if AMOUNTS_MARKER.search(text) else None)
        if measure is None:
            continue
        pp = printed_page(doc[i])
        owner = max([s for s in starts if pp is not None and s <= pp], default=None)
        pages.append(dict(pdf_page=i, printed=pp, measure=measure,
                          form=page_form(doc[i]),
                          universe=universe_at.get(owner, 'all returns')))

    # A form runs over several page pairs and only its first page carries the
    # legend, so a page without one continues the form before it. Carry-forward
    # is dangerous: when a legend pattern stops matching, it silently relabels
    # every following page as the last form recognised. Track run length so a
    # long run shows up as a defect rather than as plausible output.
    last, run = None, 0
    for r in pages:
        if r['form']:
            last, run = r['form'], 0
        else:
            run += 1
            r['form'], r['carried'] = last, run
    return pages


def extract(path, tax_year):
    doc = fitz.open(path)
    source = os.path.basename(path)
    rows = []
    for page in classify(doc):
        for label, value, desc in line_values(doc[page['pdf_page']]):
            rows.append(dict(tax_year=tax_year, publication=4801,
                             universe=page['universe'], form=page['form'],
                             line=label, line_text=desc, measure=page['measure'],
                             value=int(value.replace(',', '')),
                             pdf_page=page['pdf_page'], source_file=source))
    return doc, rows


#-------
# Main
#-------

SUMMARY_YEARS = range(2003, 2024)


def main(dest, first, last):
    src_dir = os.path.join(dest, 'national', 'line_items')
    all_rows, check_rows, coverage, warnings = [], [], [], []

    # The cover-page total is a plain text read, independent of the page
    # classification, so it is collected for every vintage on disk.
    for year in SUMMARY_YEARS:
        path = os.path.join(src_dir, 'p4801_%d.pdf' % year)
        if not os.path.exists(path):
            continue
        doc = fitz.open(path)
        head = normalise('\n'.join(doc[i].get_text()
                                    for i in range(min(8, doc.page_count))))
        m = TOTAL_RETURNS.search(head)      # first hit is the all-returns total
        if m:
            check_rows.append(dict(tax_year=year, item='total_returns_filed',
                                   measure='returns',
                                   value=int(m.group(1).replace(',', ''))))
        else:
            warnings.append('TY%d: cover-page total not found' % year)

    for year in range(first, last + 1):
        path = os.path.join(src_dir, 'p4801_%d.pdf' % year)
        if not os.path.exists(path):
            continue
        doc, rows = extract(path, year)
        all_rows.extend(rows)

        # The check items are selected from the same extraction rather than
        # parsed a second way, so the harness tests the real parser.
        agi = AGI_LINE.get(year)
        for measure in ('returns', 'amount'):
            hit = [r for r in rows
                   if r['form'] == 'Form 1040' and r['universe'] == 'all returns'
                   and r['line'] == agi and r['measure'] == measure]
            if len(hit) == 1:
                check_rows.append(dict(tax_year=year, item='agi',
                                       measure=measure, value=hit[0]['value']))
            else:
                # More than one hit means pages are mislabelled -- exactly how
                # a broken legend pattern showed up. Never silently drop it.
                warnings.append('TY%d agi/%s: %d candidate rows, want 1'
                                % (year, measure, len(hit)))
        pages = classify(doc)
        carried = max([p.get('carried', 0) for p in pages] or [0])
        if carried > 4:
            warnings.append('TY%d: %d consecutive pages inherited their form '
                            'from an earlier page -- check the legend pattern'
                            % (year, carried))
        coverage.append((year, len(rows), len({r['form'] for r in rows}),
                         len(set(r['pdf_page'] for r in rows)), len(pages)))

    for sub, name, fields, data in (
            ('aligned', 'line_items.csv',
             ['tax_year', 'publication', 'universe', 'form', 'line', 'line_text',
              'measure', 'value', 'pdf_page', 'source_file'], all_rows),
            ('checks', 'line_item_values.csv',
             ['tax_year', 'item', 'measure', 'value'], check_rows)):
        out_dir = os.path.join(dest, sub)
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, name), 'w', newline='') as f:
            w = csv.DictWriter(f, fields)
            w.writeheader()
            w.writerows(data)

    print('%-6s %8s %6s %14s' % ('year', 'values', 'forms', 'pages w/ values'))
    for year, n, forms, pages, data_pages in coverage:
        print('%-6d %8d %6d %8d / %-5d' % (year, n, forms, pages, data_pages))
    print('\n%d values across %d tax years -> aligned/line_items.csv'
          % (len(all_rows), len(coverage)))
    print('%d check values -> checks/line_item_values.csv' % len(check_rows))
    if warnings:
        print('\nwarnings:')
        for w in warnings:
            print('  ' + w)


if __name__ == '__main__':
    if not 2 <= len(sys.argv) <= 4:
        sys.exit('usage: parse_line_items.py <dest> [first_year] [last_year]')
    main(sys.argv[1],
         int(sys.argv[2]) if len(sys.argv) > 2 else 2018,
         int(sys.argv[3]) if len(sys.argv) > 3 else 2023)
