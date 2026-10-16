#!/usr/bin/env python3
#
# Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
#
# AGENT-PLATFORM (Brief 0078): regenerates the acknowledgements the app ships in
# ElementX/SupportingFiles/Settings.bundle (iOS Settings > Spiral >
# Acknowledgements; Settings > About > Open source licenses opens it).
#
# Upstream writes the same bundle with `swift-package-list` from its Renovate
# CI job. That job never runs here (no CI), and the tool cannot see what this
# fork ships: the local path packages (LiveKit, SpiralAppShell, MatrixRustSDK,
# Compound, CompoundDesignTokens) are absent from Package.resolved, upstream
# ignores its own packages, and neither the app nor matrix-rust-sdk is a
# package. The output format stays the tool's, so nothing else changes.
#
# The list is the whole package graph: every package project.yml declares,
# every local package those reach, every pin in Package.resolved, plus the app
# itself and the sources built into a package's binary (BUNDLED_SOURCES). The
# text of each entry is its licence files verbatim (LICENSE*, LICENCE*,
# COPYING*, NOTICE*), plus those inside its downloaded binary artifacts (the
# WebRTC binary is BSD-licensed, its packaging repository MIT); a package
# without one is listed as such, never given a made-up licence.
#
# Usage (from anywhere; needs xcodegen, swift and resolved packages):
#   Tools/Scripts/generate-acknowledgements.py           # rewrite the bundle
#   Tools/Scripts/generate-acknowledgements.py --check   # exit 1 if stale
# Remote licence texts come from the SwiftPM checkouts of a build of this
# project (Xcode's DerivedData, or .build-dd / .build-sim / .build-device);
# `--source-packages DIR` picks one. Each checkout must sit at its pinned
# revision, and a bundled source is read at the commit its package's
# PROVENANCE.json names, so a stale checkout cannot leave an old licence in
# the bundle.

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "ElementX.xcodeproj"
RESOLVED = PROJECT / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
BUNDLE = ROOT / "ElementX/SupportingFiles/Settings.bundle"

APP_TITLE = "Element X iOS"

# Sources compiled into a package's binary target rather than declared as a
# package: package name -> [(title, directory relative to the package)].
BUNDLED_SOURCES = {
    "MatrixRustSDK": [("matrix-rust-sdk", "../matrix-rust-sdk")],
}
# The same for a package fetched by URL: repository identity -> [(title,
# checkout)]. The checkout is a clone of the source repository, by default
# the sibling of this repository (`--bundled-source TITLE=DIR` picks another);
# the commit read is the one the package's PROVENANCE.json names.
REMOTE_BUNDLED_SOURCES = {
    "matrix-rust-components-swift": [("matrix-rust-sdk", ROOT.parent / "matrix-rust-sdk")],
}

LICENCE_FILE = re.compile(r"^(licen[cs]e|copying|notice)([-._ ][^/]*)?$", re.IGNORECASE)
INVALID_XML = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f]")
NO_LICENCE_TEXT = "The package's source carries no licence file."


@dataclass
class Entry:
    title: str
    kind: str  # app, local, remote, bundled
    version: str
    licences: list[tuple[str, str]] = field(default_factory=list)  # (label, text)

    @property
    def file_stem(self) -> str:
        return re.sub(r"[^A-Za-z0-9._-]+", "-", self.title)


def fail(message: str) -> None:
    sys.exit(f"generate-acknowledgements: {message}")


def run(arguments: list[str], cwd: Path | None = None) -> str:
    try:
        return subprocess.run(arguments, cwd=cwd, check=True, capture_output=True, text=True).stdout
    except FileNotFoundError:
        fail(f"`{arguments[0]}` is not installed")
    except subprocess.CalledProcessError as error:
        fail(f"`{' '.join(arguments)}` failed:\n{error.stderr.strip()}")


def repository_name(location: str) -> str:
    name = location.rstrip("/").split("/")[-1]
    return name[:-4] if name.endswith(".git") else name


def licence_files(directory: Path) -> list[str]:
    names = [name for name in os.listdir(directory)
             if LICENCE_FILE.match(name) and (directory / name).is_file()]
    # The licence first, then any NOTICE (Apache-2.0 4(d) wants it shown too).
    return sorted(names, key=lambda name: (name.lower().startswith("notice"), name.lower()))


def find_licence(directory: Path, walk_up: bool) -> list[tuple[str, Path]]:
    """A package's licence files; a local package inside a larger repository
    (spiral-app-shell/ios, compound-ios) takes its repository's."""
    current = directory
    while True:
        names = licence_files(current)
        if names:
            return [(name, current / name) for name in names]
        if not walk_up or (current / ".git").exists() or current.parent == current:
            return []
        current = current.parent


def read_licences(found: list[tuple[str, Path]]) -> list[tuple[str, str]]:
    return [(label, licence_text(path.read_bytes(), str(path))) for label, path in found]


def licences_at_commit(repository: Path, commit: str) -> list[tuple[str, str]]:
    """The licence files of a repository's tree at one commit, whatever its
    working tree holds."""
    def git(*arguments: str) -> subprocess.CompletedProcess:
        return subprocess.run(["git", "-C", str(repository), *arguments], capture_output=True)

    if git("cat-file", "-e", f"{commit}^{{commit}}").returncode != 0:
        fail(f"{repository} does not have commit {commit} — fetch it")
    tree = git("ls-tree", commit).stdout.decode()
    names = [line.split("\t", 1)[1] for line in tree.splitlines()
             if line.split()[1] == "blob" and LICENCE_FILE.match(line.split("\t", 1)[1])]
    names.sort(key=lambda name: (name.lower().startswith("notice"), name.lower()))
    return [(name, licence_text(git("show", f"{commit}:{name}").stdout, f"{repository}/{name} at {commit[:10]}"))
            for name in names]


def artifact_licences(source_packages: Path, identity: str) -> list[tuple[str, Path]]:
    """Licence files shipped inside a package's binary artifacts, at the top
    of each artifact (not the copies in every platform slice)."""
    root = source_packages / "artifacts" / identity
    if not root.is_dir():
        return []
    found = [path for path in root.rglob("*")
             if len(path.relative_to(root).parts) <= 3 and LICENCE_FILE.match(path.name) and path.is_file()]
    return [(str(path.relative_to(root)), path) for path in sorted(found)]


def git_version(directory: Path) -> str:
    result = subprocess.run(["git", "-C", str(directory), "describe", "--tags", "--always"],
                            capture_output=True, text=True)
    return result.stdout.strip() or "untracked"


def checkout_candidates(explicit: Path | None) -> list[Path]:
    if explicit:
        explicit = explicit.expanduser().resolve()
        return [explicit if explicit.name == "checkouts" else explicit / "checkouts"]
    candidates = [ROOT / name / "SourcePackages/checkouts" for name in (".build-dd", ".build-sim", ".build-device")]
    derived_data = Path.home() / "Library/Developer/Xcode/DerivedData"
    if derived_data.is_dir():
        for directory in sorted(derived_data.iterdir()):
            info = directory / "info.plist"
            if not info.is_file():
                continue
            try:
                workspace = plistlib.loads(info.read_bytes()).get("WorkspacePath")
            except Exception:
                continue
            if workspace and Path(workspace).resolve() == PROJECT.resolve():
                candidates.append(directory / "SourcePackages/checkouts")
    return [candidate for candidate in candidates if candidate.is_dir()]


def head_revision(directory: Path) -> str:
    result = subprocess.run(["git", "-C", str(directory), "rev-parse", "HEAD"], capture_output=True, text=True)
    return result.stdout.strip()


def collect(source_packages: Path | None, bundled_overrides: dict[str, Path]) -> list[Entry]:
    spec = json.loads(run(["xcodegen", "dump", "--type", "json", "--spec", str(ROOT / "project.yml")], cwd=ROOT))
    pins = json.loads(RESOLVED.read_text())["pins"]
    pinned = {pin["identity"]: pin for pin in pins}

    required_remotes: dict[str, str] = {}  # identity -> who declares it
    local_queue: list[Path] = []
    for name, package in sorted(spec.get("packages", {}).items()):
        if "path" in package:
            local_queue.append((ROOT / package["path"]).resolve())
        elif "url" in package:
            required_remotes[repository_name(package["url"]).lower()] = f"project.yml ({name})"

    entries: list[Entry] = []
    seen_local: set[Path] = set()
    while local_queue:
        directory = local_queue.pop(0)
        if directory in seen_local:
            continue
        seen_local.add(directory)
        if not (directory / "Package.swift").is_file():
            fail(f"local package {directory} is missing — check out the sibling repository")
        # A scratch path keeps SwiftPM from leaving a .build in each package.
        with tempfile.TemporaryDirectory() as scratch:
            manifest = json.loads(run(["swift", "package", "--scratch-path", scratch,
                                       "dump-package", "--package-path", str(directory)]))
        for dependency in manifest.get("dependencies", []):
            for local in dependency.get("fileSystem", []):
                local_queue.append(Path(local["path"]).resolve())
            for remote in dependency.get("sourceControl", []):
                required_remotes[remote["identity"]] = manifest["name"]

        inside_app = directory.is_relative_to(ROOT)
        entries.append(Entry(manifest["name"], "local", "in-tree" if inside_app else git_version(directory),
                             read_licences(find_licence(directory, walk_up=True))))

        for title, relative in BUNDLED_SOURCES.get(manifest["name"], []):
            bundled = (directory / relative).resolve()
            if not bundled.is_dir():
                fail(f"{manifest['name']} is built from {title}, expected at {bundled} — check it out")
            provenance = directory / "PROVENANCE.json"
            if not provenance.is_file():
                fail(f"{manifest['name']} has no PROVENANCE.json, so which {title} commit it carries is unknown")
            commit = json.loads(provenance.read_text())["sourceCommit"]
            entries.append(Entry(title, "bundled", f"built from {commit[:10]}", licences_at_commit(bundled, commit)))

    missing = sorted(identity for identity in required_remotes if identity not in pinned)
    if missing:
        fail("Package.resolved does not pin " + ", ".join(f"{identity} (from {required_remotes[identity]})" for identity in missing)
             + " — resolve the packages in Xcode or with `xcodebuild -resolvePackageDependencies -project ElementX.xcodeproj -scheme ElementX`")

    candidates = checkout_candidates(source_packages)
    stale: list[str] = []
    for pin in pins:
        name = repository_name(pin["location"])
        revision = pin["state"]["revision"]
        checkout = next((candidate / name for candidate in candidates
                         if (candidate / name).is_dir() and head_revision(candidate / name) == revision), None)
        if checkout is None:
            stale.append(f"{name} @ {revision[:10]}")
            continue
        licences = read_licences(find_licence(checkout, walk_up=False))
        texts = {text for _, text in licences}
        for label, text in read_licences(artifact_licences(checkout.parent.parent, pin["identity"])):
            if text not in texts:  # MapLibre's artifact repeats the repository's
                texts.add(text)
                licences.append((label, text))
        entries.append(Entry(name, "remote", pin["state"].get("version") or revision[:10], licences))
        for title, default in REMOTE_BUNDLED_SOURCES.get(pin["identity"], []):
            bundled = bundled_overrides.get(title, default).expanduser().resolve()
            if not (bundled / ".git").exists():
                fail(f"{name} is built from {title}; clone it at {bundled} or pass --bundled-source {title}=DIR")
            provenance = checkout / "PROVENANCE.json"
            if not provenance.is_file():
                fail(f"{name} has no PROVENANCE.json, so which {title} commit it carries is unknown")
            commit = json.loads(provenance.read_text())["sourceCommit"]
            entries.append(Entry(title, "bundled", f"built from {commit[:10]}", licences_at_commit(bundled, commit)))
    if stale:
        searched = "\n  ".join(str(candidate) for candidate in candidates) or "(none found)"
        fail("no checkout at the pinned revision for " + ", ".join(stale)
             + f"\nsearched:\n  {searched}\nbuild or resolve the project first, or pass --source-packages")

    entries.append(Entry(APP_TITLE, "app", git_version(ROOT), read_licences(find_licence(ROOT, walk_up=False))))

    titles: dict[str, str] = {}
    for entry in entries:
        for key in (entry.title.lower(), entry.file_stem.lower()):
            if key in titles and titles[key] != entry.title:
                fail(f"two entries would share the name {entry.title!r} ({titles[key]!r})")
            titles[key] = entry.title
    return sorted(entries, key=lambda entry: entry.title.lower())


def licence_text(data: bytes, origin: str) -> str:
    try:
        text = data.decode("utf-8").replace("\r\n", "\n")
    except UnicodeDecodeError as error:
        fail(f"{origin} is not UTF-8 ({error.reason} at byte {error.start}) — the bundle needs its text as is")
    if INVALID_XML.search(text):
        fail(f"{origin} contains characters a plist cannot carry")
    return text


def render(entries: list[Entry]) -> dict[str, bytes]:
    def dump(value: dict) -> bytes:
        return plistlib.dumps(value, fmt=plistlib.FMT_XML, sort_keys=True)

    files: dict[str, bytes] = {}
    panes = [{"Title": "Licenses", "Type": "PSGroupSpecifier"}]
    for entry in entries:
        panes.append({"File": f"Packages/{entry.file_stem}", "Title": entry.title, "Type": "PSChildPaneSpecifier"})
        groups = []
        for label, text in entry.licences:
            group = {"FooterText": text, "Type": "PSGroupSpecifier"}
            if len(entry.licences) > 1:
                group["Title"] = label
            groups.append(group)
        if not groups:
            groups.append({"FooterText": NO_LICENCE_TEXT, "Type": "PSGroupSpecifier"})
        files[f"Packages/{entry.file_stem}.plist"] = dump({"PreferenceSpecifiers": groups})
    files["Acknowledgements.plist"] = dump({"PreferenceSpecifiers": panes, "StringsTable": "Acknowledgements"})
    return files


def on_disk() -> dict[str, bytes]:
    files = {"Acknowledgements.plist": (BUNDLE / "Acknowledgements.plist").read_bytes()}
    packages = BUNDLE / "Packages"
    if packages.is_dir():
        for name in os.listdir(packages):  # listdir keeps the on-disk case
            if name.endswith(".plist"):
                files[f"Packages/{name}"] = (packages / name).read_bytes()
    return files


def spdx(text: str) -> str:
    """A best guess for the summary only; the bundle carries the text itself."""
    if "GNU AFFERO GENERAL PUBLIC LICENSE" in text:
        return "AGPL-3.0"
    if "Licensees holding a valid commercial license with Element" in text:
        return "LicenseRef-Element-Commercial"
    if re.search(r"Apache License\s*\n?\s*Version 2\.0", text) and "TERMS AND CONDITIONS" in text:
        return "Apache-2.0"
    if "Permission is hereby granted, free of charge" in text:
        return "MIT"
    if "Redistribution and use in source and binary forms" in text:
        return "BSD-3-Clause" if "Neither the name" in text or "may be used to endorse" in text else "BSD-2-Clause"
    if "Mozilla Public License Version 2.0" in text:
        return "MPL-2.0"
    return "unrecognised"


def summary(entries: list[Entry]) -> str:
    def describe(label: str, text: str) -> str:
        return "notice" if Path(label).name.lower().startswith("notice") else spdx(text)

    lines = []
    for entry in entries:
        if entry.licences:
            licences = ", ".join(f"{label}: {describe(label, text)}" for label, text in entry.licences)
        else:
            licences = "NO LICENCE FILE"
        lines.append(f"{entry.title:34} {entry.kind:8} {entry.version:24} {licences}")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Regenerate or check the acknowledgements in Settings.bundle.")
    parser.add_argument("--check", action="store_true", help="exit 1 when the bundle differs from the package graph")
    parser.add_argument("--source-packages", type=Path, help="a SourcePackages (or checkouts) directory to read licences from")
    parser.add_argument("--bundled-source", action="append", default=[], metavar="TITLE=DIR",
                        help="where to read a bundled source of a remote package, e.g. matrix-rust-sdk=../matrix-rust-sdk")
    arguments = parser.parse_args()
    overrides = {}
    for item in arguments.bundled_source:
        title, separator, directory = item.partition("=")
        if not separator:
            fail(f"--bundled-source wants TITLE=DIR, not {item!r}")
        overrides[title] = Path(directory)

    entries = collect(arguments.source_packages, overrides)
    expected = render(entries)
    actual = on_disk()

    if arguments.check:
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        changed = sorted(path for path in set(expected) & set(actual) if expected[path] != actual[path])
        if missing or extra or changed:
            for label, paths in (("missing", missing), ("not in the graph", extra), ("out of date", changed)):
                for path in paths:
                    print(f"  {label}: {path}")
            fail("Settings.bundle is stale — run Tools/Scripts/generate-acknowledgements.py")
        print(f"generate-acknowledgements: {len(entries)} entries, Settings.bundle up to date")
        return

    for path in sorted(set(actual) - set(expected)):
        (BUNDLE / path).unlink()  # first, so a case-only rename lands with the new case
    (BUNDLE / "Packages").mkdir(exist_ok=True)
    for path, content in expected.items():
        if actual.get(path) != content:
            (BUNDLE / path).write_bytes(content)
    print(summary(entries))
    without = [entry.title for entry in entries if not entry.licences]
    print(f"\n{len(entries)} entries written" + (f"; no licence file: {', '.join(without)}" if without else ""))


if __name__ == "__main__":
    main()
