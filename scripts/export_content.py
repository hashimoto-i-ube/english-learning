#!/usr/bin/env python3
"""全コンテンツを Markdown（AI検証用）と HTML/PDF（目視確認用）に書き出す。

使い方: python3 scripts/export_content.py [--no-pdf]
出力先: export/（git 管理外）。PDF 化には Google Chrome（ヘッドレス）を使う。
各項目に ID を付けているので、修正依頼は ID で指定できる。
"""
import glob
import html
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKS = os.path.join(ROOT, "Content", "packs")
OUT = os.path.join(ROOT, "export")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TYPE_JA = {"choice": "選択", "fill": "空所補充", "reorder": "整序", "translateToJa": "英文和訳",
           "translateToEn": "和文英訳", "shortAnswer": "記述"}


def load(pattern):
    packs = []
    for f in sorted(glob.glob(os.path.join(PACKS, pattern))):
        with open(f, encoding="utf-8") as fh:
            packs.append(json.load(fh))
    return packs


class Doc:
    """Markdown と HTML を同時に組み立てる"""

    def __init__(self, title):
        self.title = title
        self.md = [f"# {title}\n"]
        self.html = []

    def h(self, level, text):
        self.md.append(f"\n{'#' * level} {text}\n")
        self.html.append(f"<h{level}>{html.escape(text)}</h{level}>")

    def p(self, text, cls=None):
        if not text:
            return
        self.md.append(text + "\n")
        c = f' class="{cls}"' if cls else ""
        self.html.append(f"<p{c}>{inline(text)}</p>")

    def block(self, text):
        """単元解説（簡易 Markdown）をそのまま整形表示"""
        self.md.append(text + "\n")
        self.html.append(f'<div class="explain">{inline(text)}</div>')

    def items(self, lines):
        lines = [l for l in lines if l]
        if not lines:
            return
        self.md.extend(f"- {l}" for l in lines)
        self.md.append("")
        self.html.append("<ul>" + "".join(f"<li>{inline(l)}</li>" for l in lines) + "</ul>")

    def table(self, header, rows):
        self.md.append("| " + " | ".join(header) + " |")
        self.md.append("|" + "---|" * len(header))
        for r in rows:
            self.md.append("| " + " | ".join(str(c).replace("|", "／").replace("\n", " ") for c in r) + " |")
        self.md.append("")
        th = "".join(f"<th>{html.escape(h)}</th>" for h in header)
        trs = "".join("<tr>" + "".join(f"<td>{inline(str(c))}</td>" for c in r) + "</tr>" for r in rows)
        self.html.append(f"<table><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table>")

    def write(self, base):
        with open(base + ".md", "w", encoding="utf-8") as f:
            f.write("\n".join(self.md))
        with open(base + ".html", "w", encoding="utf-8") as f:
            f.write(HTML_HEAD.replace("{title}", html.escape(self.title)) + "\n".join(self.html) + "</body></html>")


def inline(text):
    t = html.escape(text)
    t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
    return t.replace("\n", "<br>")


HTML_HEAD = """<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>{title}</title>
<style>
@page { size: A4; margin: 14mm 12mm; }
body { font-family: "Hiragino Sans", "Hiragino Kaku Gothic ProN", sans-serif; font-size: 10pt; line-height: 1.55; color: #111; }
h1 { font-size: 18pt; border-bottom: 2px solid #333; }
h2 { font-size: 14pt; margin-top: 1.4em; border-bottom: 1px solid #999; page-break-after: avoid; }
h3 { font-size: 11.5pt; margin: 1em 0 .3em; page-break-after: avoid; }
table { border-collapse: collapse; width: 100%; margin: .4em 0 1em; font-size: 9pt; }
th, td { border: 1px solid #bbb; padding: 3px 5px; vertical-align: top; text-align: left; }
th { background: #eee; }
tr { page-break-inside: avoid; }
.explain { white-space: pre-wrap; background: #f6f6f6; padding: 6px 8px; border-radius: 4px; font-size: 9pt; }
.ex { border-left: 3px solid #4a7; padding-left: 8px; margin: .6em 0; page-break-inside: avoid; }
.en { font-family: "Times New Roman", serif; font-size: 11pt; }
.meta { color: #666; font-size: 8.5pt; }
ul { margin: .2em 0 .6em 1.2em; padding: 0; }
</style></head><body>
<h1>{title}</h1>
"""


def exercise(doc, e, n=None):
    head = f"{'問' + str(n) + '　' if n else ''}[{e['id']}]（{TYPE_JA.get(e['type'], e['type'])}）{e['prompt']}"
    lines = []
    if e.get("sentence"):
        lines.append(f"英文・問題文：{e['sentence']}")
    if e.get("choices"):
        label = "語句" if e["type"] == "reorder" else "選択肢"
        lines.append(f"{label}：" + " ／ ".join(e["choices"]))
    lines.append("正解・解答例：" + " ／ ".join(e["answers"]))
    if e.get("hint"):
        lines.append(f"ヒント：{e['hint']}")
    if e.get("keyPoints"):
        lines.append("採点ポイント：" + "、".join(e["keyPoints"]))
    lines.append(f"解説：{e['explanation']}")
    doc.md.append(f"**{head}**\n")
    doc.md.extend(f"- {l}" for l in lines)
    doc.md.append("")
    doc.html.append(f'<div class="ex"><b>{inline(head)}</b><ul>' + "".join(f"<li>{inline(l)}</li>" for l in lines) + "</ul></div>")


def export_words(pattern, title, base):
    doc = Doc(title)
    for pack in load(pattern):
        doc.h(2, f"{pack['title']}（{len(pack['words'])}項目・pack {pack['id']} rev.{pack['revision']}）")
        rows = []
        for w in pack["words"]:
            extra = []
            for key, label in [("derivatives", "派生"), ("synonyms", "類義"), ("antonyms", "反意"), ("collocations", "連語")]:
                if w.get(key):
                    extra.append(f"{label}: " + ", ".join(w[key]))
            if w.get("accentNote"):
                extra.append("アクセント: " + w["accentNote"])
            if w.get("note"):
                extra.append("注: " + w["note"])
            ex = w.get("example") or {}
            rows.append([w["id"], w["headword"] + (f" {w['ipa']}" if w.get("ipa") else ""), w["pos"],
                         "；".join(w["meanings"]), f"{ex.get('en', '')}\n{ex.get('ja', '')}", "\n".join(extra)])
        doc.table(["ID", "見出し語", "品詞", "意味", "例文", "補足"], rows)
    doc.write(base)


def export_units(fname, title, base):
    doc = Doc(title)
    pack = load(fname)[0]
    for u in sorted(pack["units"], key=lambda u: (u["level"], u["id"])):
        doc.h(2, f"Lv{u['level']}　{u['title']}　[{u['id']}]")
        doc.p(f"{u.get('category') or ''}　{u['summary']}", "meta")
        doc.block(u["explanation"])
        if u["examples"]:
            doc.h(3, "例文")
            doc.items([f"{x['en']}　→　{x['ja']}" + (f"（{x['note']}）" if x.get("note") else "") for x in u["examples"]])
        doc.h(3, f"演習（{len(u['exercises'])}問）")
        for i, e in enumerate(u["exercises"], 1):
            exercise(doc, e, i)
    doc.write(base)


def export_compositions(base):
    doc = Doc("英作文")
    pack = load("composition-core.json")[0]
    for c in sorted(pack["compositions"], key=lambda c: (c["level"], c["id"])):
        doc.h(2, f"Lv{c['level']}　{c['title']}　[{c['id']}]")
        doc.p(f"種類：{c['kind']}　条件：{c.get('conditions') or 'なし'}", "meta")
        doc.p("問題：" + c["promptJa"])
        doc.h(3, "模範解答")
        doc.items(c["modelAnswers"])
        doc.h(3, "採点ポイント")
        doc.items(c["keyPoints"])
        if c.get("usefulExpressions"):
            doc.h(3, "使える表現")
            doc.items([f"{x['en']}：{x['ja']}" for x in c["usefulExpressions"]])
    doc.write(base)


def export_reading(base):
    doc = Doc("長文読解")
    pack = load("reading-core.json")[0]
    for p in sorted(pack["passages"], key=lambda p: (p["level"], p["id"])):
        words = sum(len(x.split()) for x in p["paragraphs"])
        doc.h(2, f"Lv{p['level']}　{p['title']}　[{p['id']}]")
        doc.p(f"{p['topic']}・{words}語・目標{p.get('targetMinutes', '-')}分", "meta")
        doc.h(3, "本文と全訳")
        rows = [[f"[{i + 1}]", para, (p.get("translation") or [""] * len(p["paragraphs"]))[i]]
                for i, para in enumerate(p["paragraphs"])]
        doc.table(["段落", "本文", "訳"], rows)
        if p.get("glossary"):
            doc.h(3, "語注")
            doc.items([f"{g['term']}：{g['meaning']}" for g in p["glossary"]])
        doc.h(3, f"設問（{len(p['questions'])}問）")
        for i, q in enumerate(p["questions"], 1):
            exercise(doc, q, i)
    doc.write(base)


def export_notices(base):
    doc = Doc("お知らせ・入試情報")
    for pack in load("notices.json"):
        for n in pack["notices"]:
            doc.h(2, f"{n['date']}　{n['title']}　[{n['id']}]")
            doc.p(n["body"])
    doc.write(base)


def to_pdf(html_path):
    pdf = html_path[:-5] + ".pdf"
    profile = os.path.join(ROOT, ".cache", "chrome-export-profile")
    os.makedirs(profile, exist_ok=True)
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", f"--user-data-dir={profile}",
                    "--no-pdf-header-footer", f"--print-to-pdf={pdf}", "file://" + html_path],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
    return pdf


def main():
    os.makedirs(OUT, exist_ok=True)
    jobs = [
        ("01_英単語", lambda b: export_words("vocab-l*.json", "英単語（レベル別）", b)),
        ("02_熟語イディオム", lambda b: export_words("idioms-l*.json", "熟語・イディオム（レベル別）", b)),
        ("03_文法語法", lambda b: export_units("grammar-core.json", "文法・語法", b)),
        ("04_英文解釈構文", lambda b: export_units("construction-core.json", "英文解釈・構文", b)),
        ("05_基礎知識", lambda b: export_units("knowledge-core.json", "基礎知識", b)),
        ("06_英作文", export_compositions),
        ("07_長文読解", export_reading),
        ("08_お知らせ", export_notices),
    ]
    for name, fn in jobs:
        base = os.path.join(OUT, name)
        fn(base)
        print("md/html:", name)
    # AI に一括で渡せるよう Markdown を結合
    with open(os.path.join(OUT, "00_全コンテンツ.md"), "w", encoding="utf-8") as out:
        for name, _ in jobs:
            with open(os.path.join(OUT, name + ".md"), encoding="utf-8") as f:
                out.write(f.read() + "\n\n")
    if "--no-pdf" not in sys.argv:
        if not os.path.exists(CHROME):
            sys.exit("Google Chrome が見つからないため PDF は作成しませんでした（HTML をブラウザで印刷してください）")
        for name, _ in jobs:
            print("pdf:", os.path.basename(to_pdf(os.path.join(OUT, name + ".html"))))


if __name__ == "__main__":
    main()
