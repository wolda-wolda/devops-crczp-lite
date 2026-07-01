#!/usr/bin/env python3
"""Fix remaining markdownlint issues that pymarkdown fix cannot handle automatically."""
import re
import sys

def fix_file(path):
    with open(path, 'r') as f:
        content = f.read()

    lines = content.split('\n')
    result = []
    i = 0
    in_fence = False
    fence_marker = ''

    while i < len(lines):
        line = lines[i]

        # Track fenced code block state
        fence_match = re.match(r'^(\s*)(```|~~~)', line)
        if fence_match:
            marker = fence_match.group(2)
            if not in_fence:
                in_fence = True
                fence_marker = marker
                # MD040: add 'text' language if no language specified
                if re.match(r'^\s*(```|~~~)\s*$', line):
                    line = fence_match.group(1) + marker + 'text'
            elif marker == fence_marker:
                in_fence = False
                fence_marker = ''

        if not in_fence:
            # MD009: strip trailing spaces (not inside code blocks)
            stripped = line.rstrip()
            if line != stripped and not line.endswith('  '):
                line = stripped

            # MD034: wrap bare URLs in angle brackets (not already wrapped or in link syntax)
            line = re.sub(
                r'(?<![<(\[])(https?://[^\s\)\]">]+)(?![>)\]"])',
                r'<\1>',
                line
            )

        result.append(line)

        if not in_fence:
            # MD022: heading should have blank line below
            is_heading = re.match(r'^#{1,6} ', line)
            if is_heading:
                next_line = lines[i + 1] if i + 1 < len(lines) else ''
                if next_line.strip() != '' and not next_line.startswith('#'):
                    result.append('')

        i += 1

    # MD022: headings should have blank line ABOVE too
    final = []
    for i, line in enumerate(result):
        is_heading = re.match(r'^#{1,6} ', line)
        if is_heading and i > 0 and result[i - 1].strip() != '':
            final.append('')
        final.append(line)

    # MD029: reset ordered list numbers to sequential 1/2/3
    result2 = []
    ol_counter = {}  # indent -> count
    prev_indent = -1
    for i, line in enumerate(final):
        ol_match = re.match(r'^(\s*)(\d+)\. (.*)$', line)
        if ol_match:
            indent = len(ol_match.group(1))
            # reset counter if indent decreased (went back to parent)
            keys_to_remove = [k for k in ol_counter if k > indent]
            for k in keys_to_remove:
                del ol_counter[k]
            ol_counter[indent] = ol_counter.get(indent, 0) + 1
            line = f"{ol_match.group(1)}{ol_counter[indent]}. {ol_match.group(3)}"
        else:
            # non-list line resets counters for deeper indents only if not blank
            if line.strip():
                prev_indent = -1
        result2.append(line)

    # MD032: lists should be surrounded by blank lines
    result3 = []
    for i, line in enumerate(result2):
        is_list = re.match(r'^(\s*[-*+]|\s*\d+\.) ', line)
        prev_line = result2[i - 1] if i > 0 else ''
        next_line = result2[i + 1] if i + 1 < len(result2) else ''

        prev_is_list = re.match(r'^(\s*[-*+]|\s*\d+\.) ', prev_line)
        next_is_list = re.match(r'^(\s*[-*+]|\s*\d+\.) ', next_line)
        next_is_heading = re.match(r'^#{1,6} ', next_line)

        if is_list and not prev_is_list and prev_line.strip() != '':
            result3.append('')
        result3.append(line)
        if is_list and not next_is_list and next_line.strip() != '' and not next_is_heading:
            result3.append('')

    output = '\n'.join(result3)
    # Collapse excessive blank lines (4+) down to double blank
    output = re.sub(r'\n{4,}', '\n\n\n', output)
    # Ensure file ends with exactly one newline
    output = output.rstrip('\n') + '\n'

    with open(path, 'w') as f:
        f.write(output)

    print(f"Fixed: {path}")

for path in sys.argv[1:]:
    fix_file(path)
