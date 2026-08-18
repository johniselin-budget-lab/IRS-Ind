"""Extract line-item estimates from the SOI Pub 4801 / Pub 5385 PDFs.

Run directly, this emits the two items that can be checked against Pub 1304
without a full scrape -- total returns filed, and Form 1040 adjusted gross
income -- to <dest>/checks/line_item_values.csv, for run_checks.R to compare.

The extraction core (`boxes`, `labelled_values`, `normalise`) is the reusable
part: the full form-by-form scrape planned in notes/expansion_plan.md builds
on these rather than reimplementing them.

Uses the box-anchored extraction settled by the TY2023 spike: a value is a
numeric token whose centre falls inside one of the form's drawn entry boxes,
and its line label is the nearest label-shaped token to the left of that box.

The AGI row is selected by LINE NUMBER, from an explicit per-year map, not by
matching the printed description. Description matching looked attractive but
is fragile: the TY2018 redesign drops the phrase "this is your adjusted gross
income", and TY2018's line 7 description wraps onto two printed lines with the
entry box aligned to the second, so any text window wide enough to catch it
also bleeds the phrase into the neighbouring row.
"""
import csv, glob, os, re, sys
import fitz

if len(sys.argv) != 2:
    sys.exit('usage: parse_line_items.py <dest>   (the download destination)')
DEST = sys.argv[1]
S = os.path.join(DEST, 'national', 'line_items')
NUMERIC = re.compile(r'^\d{1,3}(,\d{3})*$|^\d{3,}$')
LINE_LABEL = re.compile(r'^\d{1,2}[a-z]?$')
Y_TOL = 8      # pt a value may sit outside its drawn box (TY2018 prints above)
# The number sits immediately before the phrase, but the separator varies by
# vintage (newline in most years, a tab in TY2014-15) and TY2013 typesets
# "filed" with an fi LIGATURE that expands to "fi led" -- with a space -- so
# the pattern tolerates gaps inside the word as well as normalising the text.
TOTAL_RETURNS = re.compile(
    r'([\d,]{7,})\s+Total,?\s+all individual returns\s+f\s*i\s*led', re.I)

def normalise(text):
    return re.sub(r'\s+', ' ', text.replace('\ufb01', 'fi').replace('\ufb02', 'fl'))

# Form 1040 line carrying AGI, by tax year.
AGI_LINE = dict([(y, '37') for y in range(2003, 2018)] +
                [(2018, '7'), (2019, '8b'), (2020, '11'),
                 (2021, '11'), (2022, '11'), (2023, '11')])
# TY2019 is the only year AGI sits on line 8b: the TY2020 redesign moved it to
# line 11, where it has stayed.

def boxes(page):
    return [d['rect'] for d in page.get_drawings()
            if 25 < d['rect'].width < 130 and 7 < d['rect'].height < 16]

def labelled_values(page):
    """{line label: value string} for the values printed in the form's boxes.

    Two refinements on the TY2023 spike, both forced by TY2018:

    * values are not always INSIDE their box -- TY2018 prints them ~5pt above
      it -- so a value is a numeric token whose x falls in a box's span and
      whose y is within a small tolerance of that box, nearest box winning;
    * the label is taken from the VALUE's own row, not the box's. Forms print
      the line number twice (left of the description and again beside the box,
      e.g. TY2018 at x=477), and the value aligns with the second. Taking the
      rightmost label-shaped token to the left of the value on its row also
      handles rows with two entry boxes (2a mid-page, 2b at the margin) and
      ignores body-text numerals like the "1" in "Schedule 1, line 22".
    """
    bs, words = boxes(page), page.get_text('words')
    labels = [w for w in words if LINE_LABEL.match(w[4])]
    out = {}
    for w in words:
        if not NUMERIC.match(w[4]):
            continue
        cx, cy = (w[0] + w[2]) / 2, (w[1] + w[3]) / 2
        near = [b for b in bs if b.x0 <= cx <= b.x1
                and b.y0 - Y_TOL <= cy <= b.y1 + Y_TOL]
        if not near:
            continue
        left = [l for l in labels
                if l[2] <= w[0] and abs((l[1] + l[3]) / 2 - cy) <= 5]
        if not left:
            continue
        lab = max(left, key=lambda l: l[2])[4]
        if lab == w[4]:
            continue
        out.setdefault(lab, w[4])
    return out


def agi_page_pair(doc, label):
    """(returns page, amounts page) for the 1040 page carrying the AGI line."""
    for i in range(doc.page_count - 1):
        text = doc[i].get_text()
        if 'adjusted gross income' not in text.lower():
            continue
        vals = labelled_values(doc[i])
        if len(vals) >= 10 and label in vals:
            return i, i + 1
    return None, None

rows, missing = [], []
for path in sorted(glob.glob(os.path.join(S, 'p4801_*.pdf'))):
    year = int(re.search(r'p4801_(\d{4})', path).group(1))
    doc = fitz.open(path)

    head = normalise('\n'.join(doc[i].get_text()
                                for i in range(min(8, doc.page_count))))
    m = TOTAL_RETURNS.search(head)   # first hit is the all-returns total;
                                     # the electronically-filed total follows
    if m:
        rows.append(dict(tax_year=year, item='total_returns_filed',
                         measure='returns', value=int(m.group(1).replace(',', ''))))
    else:
        missing.append('TY%d total_returns_filed (summary wording differs)' % year)

    label = AGI_LINE.get(year)
    ri, ai = agi_page_pair(doc, label) if label else (None, None)
    if ri is None:
        missing.append('TY%d agi (no 1040 page with line %s)' % (year, label))
        continue
    for idx, measure in ((ri, 'returns'), (ai, 'amount')):
        v = labelled_values(doc[idx]).get(label)
        if v is None:
            missing.append('TY%d agi/%s (line %s absent on page %d)'
                           % (year, measure, label, idx))
        else:
            rows.append(dict(tax_year=year, item='agi', measure=measure,
                             value=int(v.replace(',', ''))))

out_dir = os.path.join(DEST, 'checks')
os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, 'line_item_values.csv'), 'w', newline='') as f:
    w = csv.DictWriter(f, ['tax_year', 'item', 'measure', 'value'])
    w.writeheader(); w.writerows(rows)
print('wrote %d values for %d tax years to %s' %
      (len(rows), len({r['tax_year'] for r in rows}),
       os.path.join(out_dir, 'line_item_values.csv')))
if missing:
    print('\nnot extracted:')
    for x in missing:
        print('  ' + x)
