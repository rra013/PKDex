#!/usr/bin/env python3
"""Scrape Serebii's Champions Pokedex for Regulation M-C additions.

Diagnostic helper — prints what it finds per species. The real generator that
builds the bundled JSONs is gen_mc.py. Full workflow: tools/README.md.

Outputs the per-species data (stats, abilities, moves, mega forms) in the
same shape as champions-<id>-learnsets.json so it can be merged into the
M-C learnset file. Read-only network access; nothing is written to the
app bundle by this script.
"""
import urllib.request, re, json, sys, html as htmlmod, time

UA = {"User-Agent": "Mozilla/5.0"}

def fetch(slug):
    url = f"https://www.serebii.net/pokedex-champions/{slug}/"
    for attempt in range(3):
        try:
            return urllib.request.urlopen(
                urllib.request.Request(url, headers=UA), timeout=30
            ).read().decode("utf-8", "replace")
        except Exception as e:
            if attempt == 2:
                raise
            time.sleep(2)

STAT_KEYS = ["hp", "atk", "def", "spa", "spd", "spe"]

def parse_stats_at(h, idx):
    """Parse the 6 stat cells following a 'Base Stats - Total' marker at idx."""
    seg = h[idx: idx + 700]
    cells = re.findall(r'class="fooinfo">(\d+)</td>', seg)
    if len(cells) < 6:
        return None
    nums = [int(x) for x in cells[:6]]
    return dict(zip(STAT_KEYS, nums))

def parse_abilities_at(h, idx):
    """Parse the ability links in the fooleft cell at/after idx."""
    m = re.search(r'<b>Abilities</b>:(.*?)</td>', h[idx: idx + 1200], re.S)
    if not m:
        return []
    names = re.findall(r'/abilitydex/[a-z0-9\-]+\.shtml"><b>([^<]+)</b>', m.group(1))
    return [htmlmod.unescape(n).strip() for n in names]

def parse_moves(segment):
    links = re.findall(r'/attackdex[^"]*?/[a-z0-9\-]+\.shtml"[^>]*>([^<]+)</a>', segment)
    return sorted(set(htmlmod.unescape(n).strip() for n in links))

def scrape(slug):
    h = fetch(slug)
    result = {}

    # Split page into base region vs mega region at the mega anchor.
    mega_anchor = h.find('<a name="mega"></a>')
    base_region = h[:mega_anchor] if mega_anchor >= 0 else h

    # Base abilities: first Abilities block on the page.
    ab_idx = h.find("<b>Abilities</b>")
    result["abilities"] = parse_abilities_at(h, ab_idx) if ab_idx >= 0 else []

    # Base stats: first 'Base Stats - Total' occurrence.
    bs_idx = h.find("Base Stats - Total")
    result["stats"] = parse_stats_at(h, bs_idx) if bs_idx >= 0 else None

    # Base moves: attackdex links in the base region.
    result["moves"] = parse_moves(base_region)

    # Megas: each starts with <h3>Mega ...</h3> in a fooevo cell, followed by
    # its own Abilities block and Base Stats row.
    megas = []
    for m in re.finditer(r'<td class="fooevo"[^>]*><h3>(Mega [^<]+)</h3>', h):
        name = htmlmod.unescape(m.group(1)).strip()
        seg_start = m.end()
        ab_i = h.find("<b>Abilities</b>", seg_start)
        bs_i = h.find("Base Stats - Total", seg_start)
        megas.append({
            "name": name,
            "abilities": parse_abilities_at(h, ab_i) if ab_i >= 0 else [],
            "stats": parse_stats_at(h, bs_i) if bs_i >= 0 else None,
        })
    # Dedupe by name preserving order.
    seen = set(); uniq = []
    for mg in megas:
        if mg["name"] in seen:
            continue
        seen.add(mg["name"]); uniq.append(mg)
    result["megas"] = uniq
    return result

NEW_BASE = [
    "wigglytuff", "persian", "farfetchd", "mr-mime", "swalot", "salamence",
    "gogoat", "golisopod", "rillaboom", "cinderace", "inteleon", "thievul",
    "toxtricity", "grapploct", "perrserker", "sirfetchd", "pincurchin",
    "indeedee", "pawmot", "arboliva", "squawkabilly", "mabosstiff", "baxcalibur",
]
# Existing species that gain a new "Z" mega in M-C.
Z_MEGA_HOSTS = ["garchomp", "lucario", "absol"]

if __name__ == "__main__":
    out = {}
    for slug in NEW_BASE + Z_MEGA_HOSTS:
        try:
            out[slug] = scrape(slug)
            m = out[slug]
            print(f"[ok] {slug:14} ab={m['abilities']} stats={m['stats']} "
                  f"#moves={len(m['moves'])} megas={[x['name'] for x in m['megas']]}",
                  file=sys.stderr)
        except Exception as e:
            print(f"[ERR] {slug}: {e!r}", file=sys.stderr)
            out[slug] = {"error": repr(e)}
    with open("tools/mc_scrape.json", "w") as f:
        json.dump(out, f, indent=2)
    print("wrote tools/mc_scrape.json", file=sys.stderr)
