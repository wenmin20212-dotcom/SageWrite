"""Build a deterministic documentation ZIP; no network or installation."""
import hashlib
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parent
source = root / "free-pdf-tools"
names = ("README.md", "tools.json", "export.py", "download-tools.py", "validation.json")
checksums = "".join(
    f"{hashlib.sha256((source / name).read_bytes()).hexdigest()}  {name}\n"
    for name in names
)
(source / "SHA256SUMS.txt").write_text(checksums, encoding="utf-8", newline="\n")
output = root / "sagewrite-free-pdf-tools.zip"
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for name in (*names, "SHA256SUMS.txt"):
        item = zipfile.ZipInfo(f"free-pdf-tools/{name}", (2026, 10, 1, 0, 0, 0))
        item.compress_type = zipfile.ZIP_DEFLATED
        item.external_attr = 0o100644 << 16
        archive.writestr(item, (source / name).read_bytes())
print(output)
