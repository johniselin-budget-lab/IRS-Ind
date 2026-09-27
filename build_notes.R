#!/usr/bin/env Rscript
#------------------------------------------------------------------------------
# build_notes.R
#
# Assembles notes/*.md into the consolidated NOTES.md that sits at the root of
# the data store, for anyone who reaches the files without this repo.
#
# This exists because the consolidated copy was maintained by hand and drifted:
# on 2026-09-16 it carried five of the ten families, and its by-size section
# predated Table 2.3, the BIFF4 trap and the capital-assets cross-reference.
# The per-family notes were correct throughout -- only the copy placed with the
# data was stale. Assembling it mechanically is what stops that recurring.
#
# The downloader deliberately never touches NOTES.md, so this is a separate
# step. Run it whenever a note changes or a family is added:
#
#   Rscript build_notes.R                          # into this repo's data/
#   Rscript build_notes.R --dest /path/to/store    # the shared store
#
# A family added to notes/ must be added to NOTE_ORDER below, or the script
# stops: a note that exists but is unlisted is exactly the silent omission
# that produced the drift.
#------------------------------------------------------------------------------

args = commandArgs(trailingOnly = TRUE)

script_dir = dirname(sub('--file=', '', grep('--file=', commandArgs(), value = TRUE)[1]))
if (is.na(script_dir) || script_dir == '') script_dir = '.'

# Reading order: the four by-geographic-area families first, since they are what
# most consumers arrive for, then the national ones. Planning documents
# (alignment_plan, expansion_plan, bysize_panels_plan) are repo-internal and deliberately excluded --
# they describe work to be done, not the data that is here.
NOTE_ORDER = c('ht2', 'percentile', 'county', 'zip',
               'national_bysize', 'ira', 'sole_prop', 'w2', 'line_items',
               'capital_assets')

PLANNING_NOTES = c('alignment_plan', 'expansion_plan', 'bysize_panels_plan')

dest = file.path(script_dir, 'data')

i = 1
while (i <= length(args)) {
  if (args[i] == '--dest') {
    if (i == length(args)) stop('--dest requires a path')
    dest = args[i + 1]
    i = i + 2
  } else {
    stop('unknown argument: ', args[i])
  }
}

notes_dir = file.path(script_dir, 'notes')
if (!dir.exists(notes_dir)) stop('notes/ not found at ', notes_dir)

# Every note on disk is either ordered or explicitly planning. Anything else is
# a new family whose author forgot this file.
on_disk   = sub('\\.md$', '', basename(list.files(notes_dir, pattern = '\\.md$')))
unlisted  = setdiff(on_disk, c(NOTE_ORDER, PLANNING_NOTES))
if (length(unlisted) > 0) {
  stop('notes/ holds families missing from NOTE_ORDER: ',
       paste(unlisted, collapse = ', '),
       '\n  Add them to build_notes.R, or NOTES.md will omit them silently.')
}

missing = setdiff(NOTE_ORDER, on_disk)
if (length(missing) > 0) {
  stop('NOTE_ORDER names notes that do not exist: ', paste(missing, collapse = ', '))
}

bodies = vapply(NOTE_ORDER,
                function(n) trimws(paste(readLines(file.path(notes_dir, paste0(n, '.md')),
                                                   warn = FALSE), collapse = '\n')),
                character(1))

preamble = sprintf(
'# IRS-Ind: Notes on the data

Consolidated documentation of the %d data families in this store -- what each
file is, how it changed over time (variables, disclosure rules, units), and
gotchas for analysis. Compiled from the SOI documentation guides (downloaded
alongside the data as *docguide* files) and verified directly against the files
here. Each section carries its own compilation date; this assembly was built
%s.

Maintained in the IRS-Ind repo (github.com/johniselin-budget-lab/IRS-Ind,
notes/); this copy is placed with the data for anyone who reaches it without
the repo. The downloader never touches this file -- it is written by
build_notes.R, which is the only thing that should write it. Edit the
per-family note in the repo and re-run that script; do not edit this copy.',
  length(NOTE_ORDER), format(Sys.Date(), '%Y-%m-%d'))

out = paste(c(preamble, bodies), collapse = '\n\n---\n\n')

dir.create(dest, recursive = TRUE, showWarnings = FALSE)
out_path = file.path(dest, 'NOTES.md')
writeLines(out, out_path)

message('Wrote ', normalizePath(out_path))
message('  ', length(NOTE_ORDER), ' families, ',
        length(strsplit(out, '\n')[[1]]), ' lines: ',
        paste(NOTE_ORDER, collapse = ', '))
