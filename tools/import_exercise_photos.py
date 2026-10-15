#!/usr/bin/env python3
"""Download start/finish photos for every catalog exercise that names one.

Photos come from free-exercise-db (public domain, https://github.com/yuhonas/free-exercise-db).
Each `photo: "<id>"` in Shared/ExerciseCatalog.swift becomes FORGE/Resources/ExercisePhotos/<id>-0.jpg
and <id>-1.jpg, resized to 640 px wide to keep the app small. Re-run after adding exercises;
existing photos are skipped.

    python3 tools/import_exercise_photos.py
"""
import pathlib
import re
import subprocess
import sys
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Shared" / "ExerciseCatalog.swift"
OUT = ROOT / "FORGE" / "Resources" / "ExercisePhotos"
BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises"
WIDTH = 640


def main() -> int:
    ids = sorted(set(re.findall(r'photo: "([A-Za-z0-9_\-]+)"', CATALOG.read_text())))
    OUT.mkdir(parents=True, exist_ok=True)
    failed = []
    with tempfile.TemporaryDirectory() as tmp:
        for ex_id in ids:
            for frame in (0, 1):
                dest = OUT / f"{ex_id}-{frame}.jpg"
                if dest.exists():
                    continue
                raw = pathlib.Path(tmp) / f"{ex_id}-{frame}.jpg"
                try:
                    urllib.request.urlretrieve(f"{BASE}/{ex_id}/{frame}.jpg", raw)
                except Exception as error:  # noqa: BLE001 - report and carry on
                    failed.append(f"{ex_id}/{frame}: {error}")
                    continue
                # sips re-encodes the image, so nothing but pixels reaches the app bundle.
                subprocess.run(["sips", "--resampleWidth", str(WIDTH), "-s", "format", "jpeg",
                                "-s", "formatOptions", "70", str(raw), "--out", str(dest)],
                               check=True, capture_output=True)
    print(f"{len(ids)} exercises with photos in {OUT.relative_to(ROOT)}")
    for line in failed:
        print("failed:", line, file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
