"""Build and check a local pub archive. Requires Dart 3.12 with Flutter on PATH."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = {
    "LICENSE", "README.md", "CHANGELOG.md", "THIRD_PARTY_NOTICES.md", "pubspec.yaml",
    "lib/flutter_amap_map.dart", "lib/flutter_amap_map_harmony.dart",
    "android/build.gradle", "ios/flutter_amap_map.podspec",
    "ios/sdk/AMap3DMap.podspec.json", "ohos/index.ets", "doc/platforms.md",
    "doc/api.md", "example/pubspec.yaml", "example/lib/main.dart",
    "example/lib/main_harmony.dart", "example/demo_scenes/pubspec.yaml",
    "example/demo_scenes/assets/pet_pin.png",
}
FORBIDDEN_DIRS = {"hosts", "docs", "config", "output", "build", "Pods", "oh_modules",
                  "node_modules", "ephemeral", "xcuserdata", "flutter_assets"}
FORBIDDEN_SUFFIXES = {".key", ".pem", ".p8", ".p12", ".pfx", ".p7b", ".jks",
                      ".keystore", ".cer", ".mobileprovision", ".apk", ".aab",
                      ".hap", ".ipa", ".har", ".aar", ".jar", ".so", ".dylib",
                      ".zip", ".gz", ".tgz", ".a", ".dsym", ".xcframework", ".framework"}
URL_WARNING = 'It\'s strongly recommended to include a "homepage" or "repository" field in your pubspec.yaml'


def fail(message):
    raise SystemExit(message)


def configured_map_keys():
    keys = set()
    for path in (ROOT / "config").glob("*.json"):
        try:
            config = json.loads(path.read_bytes())
        except ValueError:
            continue  # The local Harmony signing profile uses JSON5.
        if isinstance(config, dict):
            key = config.get("AMAP_API_KEY")
            if isinstance(key, str) and key.strip():
                keys.add(key.strip().encode())
    return keys


def read_archive(path, keys):
    files = {}
    with tarfile.open(path, "r:gz") as archive:
        for entry in archive:
            name = PurePosixPath(entry.name)
            if (name.is_absolute() or ".." in name.parts or
                    any(p.startswith(".") or p in FORBIDDEN_DIRS or
                        PurePosixPath(p).suffix.lower() in FORBIDDEN_SUFFIXES for p in name.parts)):
                fail(f"Unexpected package path: {name}")
            if entry.isdir():
                continue
            if not entry.isfile() or entry.name in files or name.name in {
                "key.properties", "local.properties", "pubspec.lock", "env.json"
            }:
                fail(f"Unexpected entry: {name}")
            data = archive.extractfile(entry).read()
            if any(key in data for key in keys) or re.search(
                rb"-----BEGIN [A-Z ]*PRIVATE KEY-----", data
            ):
                fail(f"Local credential material in {name}")
            if name.name == "build-profile.json5" and b"signingConfigs" in data:
                if not re.search(rb"""\bsigningConfigs["']?\s*:\s*\[\s*\]""", data):
                    fail(f"Local signing configuration in {name}")
            files[entry.name] = data
    missing = REQUIRED.difference(files)
    if missing:
        fail(f"Package files missing: {sorted(missing)}")
    return files


def pub(dart, cwd, option, log, dry_run=False):
    args = [dart, "pub", "publish", option]
    with log.open("w") as stream:
        result = subprocess.run(args, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
    output = log.read_text()
    warnings = [line[2:].strip() for line in output.splitlines() if line.startswith("* ")]
    if (any(w != URL_WARNING for w in warnings) or
            result.returncode and not (dry_run and result.returncode == 65 and warnings == [URL_WARNING])):
        fail(f"Pub check failed. See {log}")
    if dry_run and warnings:
        print(warnings[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", default="dart", help="Dart from the standard Flutter SDK")
    parser.add_argument("--output", type=Path, default=ROOT / "output/pub-check")
    args = parser.parse_args()
    dart = shutil.which(args.dart)
    if not dart:
        fail("Dart executable not found")
    # dart pub needs the Flutter SDK when resolving the package in a new directory.
    if (Path(dart).resolve().parents[1] / "packages/flutter").is_dir():
        os.environ["FLUTTER_ROOT"] = str(Path(dart).resolve().parents[1])
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="amap-pub-") as temp:
        work = Path(temp)
        source = work / "source.tar.gz"
        pub(dart, ROOT, f"--to-archive={source}", out / "source-archive.log")
        keys = configured_map_keys()
        files = read_archive(source, keys)
        candidate = work / "flutter_amap_map"
        manifest = files["pubspec.yaml"]
        files["pubspec.yaml"] = re.sub(rb"(?m)^publish_to: none\r?\n", b"", manifest)
        if re.search(rb"(?m)^publish_to:", files["pubspec.yaml"]):
            fail("Unexpected publish_to value in the release candidate")
        for name, data in files.items():
            target = candidate / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        shutil.copyfile(ROOT / ".pubignore", candidate / ".pubignore")
        pub(dart, candidate, "--dry-run", out / "publish-dry-run.log", dry_run=True)
        version = re.search(rb"(?m)^version: (\S+)$", manifest).group(1).decode()
        archive = work / f"flutter_amap_map-{version}.tar.gz"
        pub(dart, candidate, f"--to-archive={archive}", out / "candidate-archive.log")
        if read_archive(archive, keys) != files:
            fail("Final pub archive differs from the checked source")
        target = out / archive.name
        shutil.copyfile(archive, target)
        print(f"{target}\n{len(files)} files, {target.stat().st_size} bytes")
        print(f"SHA-256 {hashlib.sha256(target.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
