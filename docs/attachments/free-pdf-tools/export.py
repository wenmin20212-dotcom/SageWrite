"""Automatic, local PDF auxiliary routes. No Word/WPS or manual export."""
import argparse, hashlib, html, json, pathlib, re, shutil, subprocess, sys

def run(args, cwd):
    result = subprocess.run(list(map(str, args)), cwd=cwd, capture_output=True, timeout=240)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace'))
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--book-root', required=True)
    parser.add_argument('--engine', choices=['typst', 'chromium'], required=True)
    parser.add_argument('--tool', required=True)
    parser.add_argument('--pandoc', required=True)
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--font', default='Microsoft YaHei')
    args = parser.parse_args()
    book = pathlib.Path(args.book_root).resolve()
    output = pathlib.Path(args.output_dir).resolve()
    if output == book or book / '02_chapters' == output:
        raise ValueError('Use a separate output directory.')
    output.mkdir(parents=True, exist_ok=True)
    assets = output / 'assets'; assets.mkdir(exist_ok=True)
    toc_path = book / '01_outline/toc.md'
    parent = None; parents = {}
    for line in toc_path.read_text(encoding='utf-8').splitlines():
        if line.startswith('## '): parent = line[3:].strip()
        elif line.startswith('### ') and parent: parents[line[4:].strip()] = parent
    chapters = sorted((book / '02_chapters').glob('[0-9]*.md'))
    if not chapters: raise ValueError('No numeric manuscript files found.')
    cover = book / '00_intake/cover.png'
    if not cover.exists(): raise ValueError('This tested route requires 00_intake/cover.png.')
    shutil.copyfile(cover, assets / 'cover.png')
    parts = ['---\nlang: zh-CN\ntitle: ""\n---\n']; previous = None
    headings = []; image_count = 1
    for file in chapters:
        text = file.read_text(encoding='utf-8')
        text = re.sub(r'\A---\s*\n.*?\n---\s*\n', '', text, flags=re.S)
        match = re.search(r'^### (.+)$', text, re.M)
        if not match: raise ValueError(f'Expected a section heading in {file.name}.')
        heading = match.group(1); headings.append(heading)
        if heading not in parents: raise ValueError(f'Section absent from TOC: {heading}')
        if parents[heading] != previous:
            previous = parents[heading]; parts.append('# ' + previous + '\n')
        text = re.sub(r'^### ', '## ', text, flags=re.M)
        def copy_image(match):
            nonlocal image_count
            original = (file.parent / match.group(2)).resolve()
            if not original.is_file(): raise ValueError(f'Missing image: {original}')
            name = f'image-{image_count:03d}{original.suffix}'
            image_count += 1; shutil.copyfile(original, assets / name)
            return f'![{match.group(1)}](assets/{name})'
        text = re.sub(r'!\[([^\]]*)\]\(([^)]+)\)', copy_image, text)
        parts.append(text)
    source = output / 'manuscript.md'
    source.write_text('\n\n'.join(parts), encoding='utf-8')
    # Only the tested section-based SageWrite topology is supported here.
    pdf = output / f'auxiliary-{args.engine}.pdf'
    if pdf.exists(): raise FileExistsError(f'Use a fresh output directory: {pdf}')
    common = [args.pandoc, source, '--standalone', '--toc', '--toc-depth=2']
    if args.engine == 'chromium':
        css = '''@page{size:A4;margin:22mm 20mm;@bottom-center{content:counter(page);font-size:10pt}} @page:first{@bottom-center{content:none}} body{font-family:FONT,sans-serif;font-size:11pt;line-height:1.6} h1{break-before:page;font-size:21pt;color:#173b56} h1,h2,h3{break-after:avoid} h2{font-size:15pt} p{orphans:3;widows:3} img{max-width:100%;max-height:225mm;object-fit:contain} table{border-collapse:collapse;width:100%;font-size:9pt} td,th{border:1px solid #aaa;padding:5px} tr{break-inside:avoid} #TOC{break-after:page} .cover{height:247mm;display:flex;align-items:center;justify-content:center;break-after:page}.cover img{height:240mm;width:auto}'''
        (output / 'print.css').write_text(css.replace('FONT', json.dumps(args.font)), encoding='utf-8')
        (output / 'cover.html').write_text('<section class="cover"><img src="assets/cover.png" alt="封面"></section>', encoding='utf-8')
        run(common + ['--metadata', 'toc-title=目录', '--css=print.css', '--include-before-body=cover.html', '-o', 'manuscript.html'], output)
        run([args.tool, '--headless', '--no-pdf-header-footer', '--no-first-run', '--disable-background-networking', '--user-data-dir=' + str(output / 'browser-profile'), '--print-to-pdf=' + str(pdf), (output / 'manuscript.html').as_uri()], output)
    else:
        header = '#set text(font: FONT, lang: "zh")\n#show heading.where(level: 1): it => { pagebreak(weak: true); it }\n'
        (output / 'header.typ').write_text(header.replace('FONT', json.dumps(args.font)), encoding='utf-8')
        run(common + ['--variable', 'mainfont=' + args.font, '--variable', 'papersize=a4', '--variable', 'page-numbering=1', '--include-in-header=header.typ', '-o', 'manuscript.typ'], output)
        typ = output / 'manuscript.typ'; body = typ.read_text(encoding='utf-8')
        marker = '#outline('
        if marker not in body: raise ValueError('Pandoc Typst template lacks outline marker.')
        body = body.replace(marker, '#page(numbering: none)[#align(center, image("assets/cover.png", width: 100%))]\n' + marker, 1)
        typ.write_text(body, encoding='utf-8')
        run([args.tool, 'compile', '--root', output, typ, pdf], output)
    if not pdf.exists() or pdf.stat().st_size == 0: raise RuntimeError('No new PDF created.')
    report = {'route':args.engine, 'source_units':len(chapters), 'headings':headings, 'source_images':image_count,
              'pdf_sha256':hashlib.sha256(pdf.read_bytes()).hexdigest(), 'generated':True,
              'visual_acceptance':'required_for_each_book', 'replaces_05c':False}
    (output / 'generation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(pdf)

if __name__ == '__main__':
    main()
