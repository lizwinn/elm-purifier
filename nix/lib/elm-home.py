# SPDX-License-Identifier: MIT
"""Writes the package cache of an ELM_HOME from locked package archives.

    python3 elm-home.py OUT COMPILER_VERSION MANIFEST

MANIFEST has one line per package, `author/project/version<TAB>zip`. Each
zip is unpacked to OUT/COMPILER_VERSION/packages/author/project/version
the way the Elm compiler unpacks a download: the archive's top directory
is stripped, and only elm.json, LICENSE, README.md and src/ are kept.

The compiler also reads packages/registry.dat, its copy of the package
server's list of every published version. That list changes with every
release, so it cannot be locked. This writes a registry that lists only
the locked versions, which is all an offline build resolves against.
"""

import os
import struct
import sys
import zipfile

KEPT_FILES = ("elm.json", "LICENSE", "README.md")


def unpack(archive, destination):
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            if info.is_dir() or "/" not in info.filename:
                continue
            relative = info.filename.split("/", 1)[1]
            if relative not in KEPT_FILES and not relative.startswith("src/"):
                continue
            target = os.path.join(destination, relative)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "wb") as out:
                out.write(z.read(info))


# The registry is the compiler's Data.Binary encoding of
#   Registry { count :: Int, versions :: Map Name KnownVersions }
# Int is 8 bytes big-endian; a Map is its size followed by its entries in
# key order; a Name is author and project, each a length byte and UTF-8;
# KnownVersions is the newest version followed by a list (length, then
# elements) of older ones; a version is three bytes, or 255 followed by
# three 16-bit numbers when a part does not fit in a byte.


def encode_int(n):
    return struct.pack(">q", n)


def encode_text(text):
    data = text.encode()
    return bytes([len(data)]) + data


def encode_version(version):
    parts = [int(p) for p in version.split(".")]
    if all(p < 255 for p in parts):
        return bytes(parts)
    return b"\xff" + b"".join(struct.pack(">H", p) for p in parts)


def version_key(version):
    return tuple(int(p) for p in version.split("."))


def registry(packages):
    by_name = {}
    for package in packages:
        author, project, version = package.split("/")
        by_name.setdefault((author, project), []).append(version)
    data = encode_int(len(packages)) + encode_int(len(by_name))
    for (author, project) in sorted(by_name):
        versions = sorted(by_name[(author, project)], key=version_key, reverse=True)
        data += encode_text(author) + encode_text(project)
        data += encode_version(versions[0])
        data += encode_int(len(versions) - 1)
        data += b"".join(encode_version(v) for v in versions[1:])
    return data


def main(out, compiler_version, manifest):
    root = os.path.join(out, compiler_version, "packages")
    os.makedirs(root, exist_ok=True)
    packages = []
    with open(manifest) as f:
        for line in f:
            if not line.strip():
                continue
            package, archive = line.rstrip("\n").split("\t")
            unpack(archive, os.path.join(root, package))
            packages.append(package)
    with open(os.path.join(root, "registry.dat"), "wb") as f:
        f.write(registry(packages))


if __name__ == "__main__":
    main(*sys.argv[1:])
