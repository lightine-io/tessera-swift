#!/usr/bin/env python3
"""Check that the Swift code on the public iOS pages matches the compiled samples (TES-230).

Usage:  python3 -I scripts/check-samples.py --live
Runs at the release gate, not in CI on pull requests: it reads the live public knowledge base.
Python standard library only. Exit: 0 every block matches, 1 differences, 2 network or usage error.

Conventions (the Kotlin side in the main repository uses the same ones, with `kotlin` blocks):

- Pages. Every public article under the roots below (how-tos and tutorials, at any depth) is
  read, plus any article a sample names. Pages without a checked block need nothing.
- Blocks. A block is a fenced code block (``` or ~~~, at any indent). Blocks are numbered from 1
  in page order, counting every fenced block whatever its language. A block is checked when its
  info string is `swift`.
- Regions. In a sample file, the line `// region TES-A-121 block 2` opens a region and the next
  `// endregion` closes it. The lines between are that block. A block split across two regions is
  not allowed; a declaration that a page splits across two blocks gets one region per block.
- Skips. A checked block that cannot compile as a sample (Package.swift dependency lines) is
  named on a line `// skip TES-A-121 block 1: <reason>`.
- Comparison. On both sides each line is trimmed, runs of spaces and tabs become one space, and
  blank lines are dropped. The two line lists must be equal.
- Failures. A checked block with no region and no skip, a region or skip with no checked block,
  two regions for one block, and any difference.
"""

import json
import os
import re
import sys
import urllib.parse
import urllib.request

BASE = "https://lightine.youtrack.cloud"
ROOTS = ["TES-A-103", "TES-A-141"]  # How-to: iOS, Tutorials
LANGUAGE = "swift"
SAMPLES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Samples")
SUFFIXES = (".swift",)
USER_AGENT = "tessera-check-samples/1"

REGION = re.compile(r"^\s*//\s*region\s+(TES-A-\d+)\s+block\s+(\d+)\s*$")
ENDREGION = re.compile(r"^\s*//\s*endregion\s*$")
SKIP = re.compile(r"^\s*//\s*skip\s+(TES-A-\d+)\s+block\s+(\d+)\s*:")
FENCE = re.compile(r"^(\s*)(`{3,}|~{3,})\s*([^\s`]*)")


def normalize(text):
    lines = (re.sub(r"[ \t]+", " ", line.strip()) for line in text.splitlines())
    return [line for line in lines if line]


def fetch(path):
    request = urllib.request.Request(BASE + path, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def public_articles():
    articles, skip, top = [], 0, 100
    while True:
        query = urllib.parse.urlencode(
            {"fields": "idReadable,summary,parentArticle(idReadable)", "$top": top, "$skip": skip})
        page = fetch("/api/articles?" + query)
        articles += page
        if len(page) < top:
            return articles
        skip += top


def blocks(markdown):
    """Fenced blocks in page order: (number, language, text)."""
    found, lines, i = [], markdown.splitlines(), 0
    while i < len(lines):
        match = FENCE.match(lines[i])
        if match:
            indent, fence, language = match.group(1), match.group(2), match.group(3).lower()
            close = re.compile(r"^\s*" + re.escape(fence[0]) + "{%d,}\\s*$" % len(fence))
            body, i = [], i + 1
            while i < len(lines) and not close.match(lines[i]):
                line = lines[i]
                body.append(line[len(indent):] if line.startswith(indent) else line.lstrip())
                i += 1
            found.append((len(found) + 1, language, "\n".join(body)))
        i += 1
    return found


def sample_regions(problems):
    """{(article, block): [(file, text)]} and {(article, block): file} for skips."""
    regions, skips = {}, {}
    for folder, _, files in os.walk(SAMPLES):
        for name in sorted(files):
            if not name.endswith(SUFFIXES):
                continue
            path = os.path.join(folder, name)
            shown = os.path.relpath(path, os.path.join(SAMPLES, ".."))
            current, body = None, []
            for number, line in enumerate(open(path, encoding="utf-8").read().splitlines(), 1):
                if current:
                    if ENDREGION.match(line):
                        regions.setdefault(current, []).append((shown, "\n".join(body)))
                        current, body = None, []
                    elif REGION.match(line):
                        problems.append(f"{shown}:{number}: region opens inside region {current[0]} block {current[1]}")
                    else:
                        body.append(line)
                    continue
                region, skip = REGION.match(line), SKIP.match(line)
                if region:
                    current = (region.group(1), int(region.group(2)))
                elif skip:
                    skips[(skip.group(1), int(skip.group(2)))] = shown
                elif ENDREGION.match(line):
                    problems.append(f"{shown}:{number}: endregion without region")
            if current:
                problems.append(f"{shown}: region {current[0]} block {current[1]} is never closed")
    return regions, skips


def main(argv):
    if argv != ["--live"]:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    problems = []
    regions, skips = sample_regions(problems)
    try:
        articles = public_articles()
        parent = {a["idReadable"]: (a.get("parentArticle") or {}).get("idReadable") for a in articles}

        def under_root(article):
            seen = set()
            while article and article not in seen:
                seen.add(article)
                article = parent.get(article)
                if article in ROOTS:
                    return True
            return False

        pages = sorted({a for a in parent if under_root(a)} | {k[0] for k in regions} | {k[0] for k in skips},
                       key=lambda a: int(a.rsplit("-", 1)[1]))
        content = {}
        for article in pages:
            content[article] = fetch(f"/api/articles/{article}?fields=content").get("content") or ""
    except Exception as error:  # any network or decoding failure: never pass
        print(f"check-samples: could not read the knowledge base: {error}", file=sys.stderr)
        return 2

    checked = 0
    for article in pages:
        page_blocks = {n: (lang, text) for n, lang, text in blocks(content[article])}
        for number, (language, text) in sorted(page_blocks.items()):
            if language != LANGUAGE:
                continue
            key = (article, number)
            found = regions.get(key, [])
            if key in skips and not found:
                continue
            if not found:
                problems.append(f"{article} block {number}: no region and no skip in Samples/")
                continue
            if len(found) > 1 or key in skips:
                problems.append(f"{article} block {number}: more than one region or skip")
                continue
            checked += 1
            file, sample = found[0]
            if normalize(sample) != normalize(text):
                page_lines, sample_lines = normalize(text), normalize(sample)
                problems.append(f"{article} block {number} differs from {file}:")
                problems += [f"    page:   {line}" for line in page_lines if line not in sample_lines]
                problems += [f"    sample: {line}" for line in sample_lines if line not in page_lines]
        for key in sorted(set(regions) | set(skips)):
            if key[0] == article and page_blocks.get(key[1], ("",))[0] != LANGUAGE:
                problems.append(f"{article} block {key[1]}: named in Samples/, but the page has no {LANGUAGE} block {key[1]}")

    for problem in problems:
        print(problem)
    print(f"check-samples: {len(pages)} pages, {checked} blocks compared, {len(skips)} skipped, "
          f"{'no problems' if not problems else 'FAILED'}.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
