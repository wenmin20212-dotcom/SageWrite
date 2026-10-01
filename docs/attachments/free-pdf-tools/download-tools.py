"""Fetch exact locally validated builds; no system installation."""
import argparse, hashlib, json, pathlib, urllib.request, zipfile

def fetch(engine, destination):
    items = json.loads((pathlib.Path(__file__).parent / 'tools.json').read_text(encoding='utf-8'))['tools']
    tool = next(item for item in items if item['id'] == engine)
    root = pathlib.Path(destination).resolve(); root.mkdir(parents=True, exist_ok=True)
    archive = root / tool['archive']
    def digest(path):
        h = hashlib.sha256()
        with path.open('rb') as source:
            for block in iter(lambda: source.read(1024 * 1024), b''): h.update(block)
        return h.hexdigest()
    if not archive.exists():
        temporary = archive.with_suffix('.partial')
        request = urllib.request.Request(tool['url'], headers={'User-Agent':'SageWrite-Validated-PDF-Addon'})
        with urllib.request.urlopen(request, timeout=120) as response, temporary.open('wb') as output:
            for block in iter(lambda: response.read(1024 * 1024), b''): output.write(block)
        if temporary.stat().st_size != tool['bytes'] or digest(temporary) != tool['sha256']:
            raise ValueError('Downloaded package differs from validated hash; not extracted.')
        temporary.replace(archive)
    if archive.stat().st_size != tool['bytes'] or digest(archive) != tool['sha256']:
        raise ValueError('Existing package differs from validated hash; not extracted.')
    runtime = root / 'runtime' / engine; runtime.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as compressed:
        if compressed.testzip() is not None: raise ValueError('Invalid ZIP.')
        for item in compressed.infolist():
            if not (runtime / item.filename).resolve().is_relative_to(runtime):
                raise ValueError('ZIP escapes runtime directory.')
        compressed.extractall(runtime)
    executable = runtime / tool['executable']
    if not executable.is_file(): raise ValueError('Expected executable absent.')
    print(executable)
    return executable

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--engine', required=True, choices=['typst','chromium'])
    parser.add_argument('--dest', required=True)
    args = parser.parse_args()
    fetch(args.engine, args.dest)
