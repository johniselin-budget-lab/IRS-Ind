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

Defaults to the validated years, TY2011-2023 (see notes/line_items.md). Every
vintage prints the Form 1040 for more than one population: all returns and
electronically filed returns from TY2018, and before that a third universe,
Form 1040 filers only, ahead of separate Forms 1040A and 1040EZ. The table of
contents names them and the `universe` column carries them. Earlier years than
2011 can be requested explicitly; the run warns about every ambiguity it
finds, and the Pub 1304 targets the checks need only exist from 2011.

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

# "Returns......... 14" in most vintages; TY2011 writes "Returns...... pg 14".
TOC_ENTRY = re.compile(r'^(?P<title>.+?)[^\w\s)]{2,}\s*(?:pg\.?\s*)?(?P<page>\d{1,3})\s*$', re.I)
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


ADD_RANGE = re.compile(r'(?:add|combine)\s+lines?\s+(\w+)\s+through\s+(\w+)', re.I)
RANGE_WORD = re.compile(r'\bthrough\b', re.I)
ADD_LIST  = re.compile(r'(?:add|combine)\s+lines?\s+([\w,\s]+?)(?:\s*[.\u2024]|$)', re.I)
SUBTRACT  = re.compile(r'subtract\s+line\s+(\w+)\s+from\s+line\s+(\w+)', re.I)
LABEL_TOKEN = re.compile(r'^\d{1,2}[a-z]?$')

# A stated sum only survives aggregation if it is LINEAR in each return. Many
# form lines are not: "if zero or less, enter -0-" floors the result per
# return, "enter the smaller of" caps it, and the sum of floored values is not
# the floor of the sum. Relations whose row carries one of these are recorded
# but flagged, because checking them would produce failures that mean nothing.
TRIGGER = re.compile(r'add lines?|subtract line|combine lines?', re.I)

NONLINEAR = re.compile(
    r'zero or less|enter -0-|enter 0|smaller of|larger of|greater of'
    r'|but not (?:more|less) than|whichever|limit|cannot exceed|do not enter'
    r'|if more than|if less than|multiply|percent|%', re.I)


def expand_range(first, last):
    """Labels covered by "lines 1a through 1h" / "lines 8 through 10"."""
    a = re.match(r'^(\d{1,2})([a-z])$', first)
    b = re.match(r'^(\d{1,2})([a-z])$', last)
    if a and b and a.group(1) == b.group(1):
        return ['%s%s' % (a.group(1), chr(c))
                for c in range(ord(a.group(2)), ord(b.group(2)) + 1)]
    if first.isdigit() and last.isdigit() and int(last) >= int(first):
        return [str(n) for n in range(int(first), int(last) + 1)]
    return []


REFERENCE_WORD = re.compile(r'^(lines?|schedules?|forms?|worksheets?)$', re.I)


def follows_reference(band, token):
    """Is this label really a cross-reference, e.g. "... Schedule 2, line 11"?

    A trailing cross-reference can land its line number squarely in one of the
    page's label columns, and it then beats the row's own label on the
    rightmost rule -- TY2021 Form 8959 line 18 ends "...on Schedule 2 (Form
    1040), line 11" and was filed under 11. A label introduced by "line",
    "Schedule" or "Form" is pointing elsewhere, so it is not a candidate.
    """
    before = [w for w in band if w[2] <= token[0]]
    if not before:
        return False
    prev = max(before, key=lambda w: w[2])[4].strip('(),.')
    return bool(REFERENCE_WORD.match(prev))


def line_relations(page):
    """[(target line, op, [component lines], phrase)] stated on a page.

    The forms carry their own arithmetic -- "Add lines 1z, 2b, 3b, 4b, 5b, 6b,
    7, and 8", "Subtract line 10 from line 9" -- so each subtotal can be
    checked against its own components. That tests every extracted amount
    rather than the handful a curated crosswalk can name.
    """
    words = page.get_text('words')
    columns = label_columns(words)
    if not columns:
        return []
    # Cluster into printed rows on the gaps between them; fixed-width bucketing
    # splits a row whose tokens straddle a boundary.
    rows, cur, last_y = [], [], None
    for w in sorted(words, key=lambda w: ((w[1] + w[3]) / 2, w[0])):
        y = (w[1] + w[3]) / 2
        if last_y is not None and y - last_y > 4:
            rows.append(cur)
            cur = []
        cur.append(w)
        last_y = y
    if cur:
        rows.append(cur)

    out = []
    keys = range(len(rows))
    for i in keys:
        band = sorted(rows[i], key=lambda w: w[0])
        # a wrapped description continues on the next printed line
        nxt = sorted(rows[i + 1], key=lambda w: w[0]) if i + 1 < len(rows) else []
        labels = [w for w in band if LABEL_TOKEN.match(w[4])
                  and any(abs(w[0] - x) <= 3 for x in columns)
                  and not follows_reference(band, w)]
        if not labels:
            continue
        # Take the label printed beside the ENTRY COLUMN, not the leftmost one.
        # Sub-lettered lines print only the letter on the description side
        # ("d Add lines 8a through 8c"), which is not label-shaped, so the
        # leftmost match is then a line number quoted inside the phrase itself
        # -- that is how "Add lines 8a through 8c" was filed under line 8a
        # instead of the 8d it defines. The right-hand label is always the
        # row's own, in full.
        target = max(labels, key=lambda w: w[0])[4]
        own  = ' '.join(w[4] for w in band)
        text = ' '.join(w[4] for w in band + nxt)

        # Match the row's own text. The lookahead onto the next printed line
        # is ONLY to finish a description that wraps, so it is used solely
        # when this row starts a statement it does not complete. Falling back
        # to it whenever the row had no match instead hands this row the NEXT
        # row's statement -- that is how 1040 line 10 acquired line 11's
        # "Subtract line 10 from line 9" and failed every check.
        rel, matched = first_relation(own), own
        if rel is None and TRIGGER.search(own):
            rel, matched = first_relation(text), text
        # A line is never defined in terms of itself, so a target that appears
        # among its own components means the statement was filed under the
        # wrong line -- the label picked up was one quoted inside the phrase.
        # Drop it rather than guess: the arithmetic check found exactly this
        # in 9 relations ("Subtract line 5 from line 4" filed under line 5,
        # which belongs to line 6).
        if rel is not None and target in rel[1]:
            rel = None
        if rel:
            # Judge linearity on the SAME text the statement was matched in.
            # Using the lookahead here regardless flagged a relation whenever
            # the FOLLOWING row said "if zero or less" -- roughly halving the
            # check's coverage for a qualifier that was not its own.
            caveat = 'nonlinear' if NONLINEAR.search(matched) else ''
            out.append((target,) + rel + (caveat,))
    return out


def first_relation(text):
    """The arithmetic statement appearing earliest in a row's text."""
    found = []
    m = SUBTRACT.search(text)
    if m:
        found.append((m.start(), 'subtract', [m.group(2), m.group(1)], m.group(0)))
    m = ADD_RANGE.search(text)
    if m:
        # A range this cannot expand ("10 through 32f") is DROPPED, never
        # narrowed: the list branch below would otherwise match the same
        # phrase and record just its endpoints, turning "Combine lines 1
        # through 8" into a two-term sum that then fails its own check.
        parts = expand_range(m.group(1), m.group(2))
        if parts:
            found.append((m.start(), 'add', parts, m.group(0)))
    m = ADD_LIST.search(text)
    if m and not RANGE_WORD.search(m.group(1)):
        # Compound phrases ("Add lines 27a and 28 through 31") would lose
        # their spanned lines the same way, so any list carrying "through"
        # is left out rather than recorded short.
        parts = [p for p in re.split(r'[,\s]+|\band\b', m.group(1)) if p]
        parts = [p for p in parts if LABEL_TOKEN.match(p)]
        if len(parts) >= 2:
            found.append((m.start(), 'add', parts, m.group(0)))
    if not found:
        return None
    _, op, parts, phrase = min(found, key=lambda f: f[0])
    return op, parts, phrase


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


def universe_of(heading):
    """Which population a TOC section tabulates.

    Every vintage prints the Form 1040 more than once. TY2018+ prints it for
    all returns and again for electronically filed returns. TY2017 and
    earlier print it THREE times -- all returns (every filer, consolidated
    onto the 1040 layout), Form 1040 filers only, and electronically filed --
    before separate sections for Forms 1040A and 1040EZ. Recognising only the
    electronic heading labelled the "1040 only" pages as all returns, so
    every 1040 line appeared twice and pre-2018 years could not be emitted.
    """
    h = (heading or '').lower()
    if 'electronically' in h:
        return 'electronically filed'
    if 'form 1040 only' in h:
        return 'form 1040 only'
    return 'all returns'


def classify(doc):
    """One record per data page: form, universe and measure."""
    toc = toc_sections(doc)
    starts = sorted({p for _, _, p in toc})
    universe_at = {p: universe_of(heading) for heading, _, p in toc}

    pages, last_pp = [], None
    for i in range(doc.page_count):
        text = normalise(doc[i].get_text())
        measure = ('returns' if RETURNS_MARKER.search(text) else
                   'amount' if AMOUNTS_MARKER.search(text) else None)
        if measure is None:
            continue
        pp = printed_page(doc[i])
        # TY2011's amounts pages print no page number in their header, so a
        # page without one is taken to follow the previous data page. Without
        # this every TY2011 amounts page fell to the default universe while its
        # returns page did not, and the two halves of each table disagreed.
        if pp is None and last_pp is not None:
            pp = last_pp + 1
        last_pp = pp
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
    rows, relations = [], []
    for page in classify(doc):
        for label, value, desc in line_values(doc[page['pdf_page']]):
            rows.append(dict(tax_year=tax_year, publication=4801,
                             universe=page['universe'], form=page['form'],
                             line=label, line_text=desc, measure=page['measure'],
                             value=int(value.replace(',', '')),
                             pdf_page=page['pdf_page'], source_file=source))
        # relations are a property of the form, so read them once per page
        # from whichever measure is printed there
        for target, op, parts, phrase, caveat in line_relations(doc[page['pdf_page']]):
            relations.append(dict(tax_year=tax_year, form=page['form'],
                                  universe=page['universe'], target_line=target,
                                  op=op, components='|'.join(parts),
                                  caveat=caveat,
                                  phrase=re.sub(r'\s+', ' ', phrase)[:80],
                                  pdf_page=page['pdf_page']))
    return doc, rows, relations


#-------
# Main
#-------

SUMMARY_YEARS = range(2003, 2024)


def main(dest, first, last):
    src_dir = os.path.join(dest, 'national', 'line_items')
    all_rows, check_rows, coverage, warnings = [], [], [], []
    all_relations = []

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
        doc.close()

    for year in range(first, last + 1):
        path = os.path.join(src_dir, 'p4801_%d.pdf' % year)
        if not os.path.exists(path):
            continue
        doc, rows, rels = extract(path, year)
        all_rows.extend(rows)
        all_relations.extend(rels)

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
        doc.close()      # PyMuPDF corrupts its heap if many stay open

    for sub, name, fields, data in (
            ('aligned', 'line_items.csv',
             ['tax_year', 'publication', 'universe', 'form', 'line', 'line_text',
              'measure', 'value', 'pdf_page', 'source_file'], all_rows),
            ('checks', 'line_item_values.csv',
             ['tax_year', 'item', 'measure', 'value'], check_rows),
            ('aligned', 'line_relations.csv',
             ['tax_year', 'form', 'universe', 'target_line', 'op', 'components',
              'caveat', 'phrase', 'pdf_page'], all_relations)):
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
    print('%d stated relations -> aligned/line_relations.csv' % len(all_relations))
    if warnings:
        print('\nwarnings:')
        for w in warnings:
            print('  ' + w)


if __name__ == '__main__':
    if not 2 <= len(sys.argv) <= 4:
        sys.exit('usage: parse_line_items.py <dest> [first_year] [last_year]')
    main(sys.argv[1],
         int(sys.argv[2]) if len(sys.argv) > 2 else 2011,
         int(sys.argv[3]) if len(sys.argv) > 3 else 2023)
