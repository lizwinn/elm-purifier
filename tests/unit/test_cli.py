# SPDX-License-Identifier: MIT
"""Unit tests for bin/elm-purifier and nix/lib/elm-home.py.

    python3 -m unittest discover -s tests/unit

The tests import both scripts from the repository, given as
ELM_PURIFIER_REPO (the current directory when unset).
"""

import importlib.machinery
import importlib.util
import json
import os
import struct
import tempfile
import unittest

REPO = os.environ.get("ELM_PURIFIER_REPO", os.getcwd())


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, os.path.join(REPO, path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


cli = load("elm_purifier", "bin/elm-purifier")
elm_home = load("elm_home", "nix/lib/elm-home.py")

TOOLCHAINS = {
    "0.19.1": {"elm": "/e1/bin/elm", "elm-test": {"1": "/t9/bin/elm-test", "2": "/t15/bin/elm-test"},
               "elm-test-offline-args": []},
    "0.19.2": {"elm": "/e2/bin/elm", "elm-test": {"2": "/t2/bin/elm-test"},
               "elm-test-offline-args": ["--offline"]},
}


class Constraints(unittest.TestCase):
    def test_exact_version(self):
        self.assertTrue(cli.satisfies("0.19.1", "0.19.1"))
        self.assertFalse(cli.satisfies("0.19.2", "0.19.1"))

    def test_range(self):
        self.assertTrue(cli.satisfies("0.19.2", "0.19.0 <= v < 0.20.0"))
        self.assertFalse(cli.satisfies("0.20.0", "0.19.0 <= v < 0.20.0"))
        self.assertTrue(cli.satisfies("0.20.0", "0.19.0 <= v <= 0.20.0"))
        self.assertFalse(cli.satisfies("0.19.0", "0.19.0 < v < 0.20.0"))

    def test_versions_compare_as_numbers(self):
        self.assertLess(cli.version_key("0.19.2"), cli.version_key("0.19.10"))


class CompilerSelection(unittest.TestCase):
    def setUp(self):
        os.environ["ELM_PURIFIER_TOOLCHAINS"] = json.dumps(TOOLCHAINS)

    def test_application_takes_its_exact_version(self):
        self.assertEqual(cli.select_compiler({"elm-version": "0.19.1"}), "0.19.1")

    def test_package_takes_the_newest_in_range(self):
        self.assertEqual(cli.select_compiler({"elm-version": "0.19.0 <= v < 0.20.0"}), "0.19.2")

    def test_unknown_version_fails(self):
        with self.assertRaises(SystemExit):
            cli.select_compiler({"elm-version": "0.18.0"})


class TestRunner(unittest.TestCase):
    def test_major_of_an_application(self):
        elm_json = {"type": "application",
                    "test-dependencies": {"direct": {"elm-explorations/test": "1.2.2"}, "indirect": {}}}
        self.assertEqual(cli.test_major(elm_json), "1")

    def test_major_of_a_package_range(self):
        elm_json = {"type": "package",
                    "test-dependencies": {"elm-explorations/test": "2.0.0 <= v < 3.0.0"}}
        self.assertEqual(cli.test_major(elm_json), "2")

    def test_no_test_package(self):
        self.assertIsNone(cli.test_major({"type": "package", "test-dependencies": {}}))

    def test_runner_by_major(self):
        elm_json = {"type": "package", "test-dependencies": {"elm-explorations/test": "1.0.0 <= v < 2.0.0"}}
        command = cli.elm_test_command(TOOLCHAINS["0.19.1"], elm_json, offline=True)
        self.assertEqual(command, ["/t9/bin/elm-test", "--compiler", "/e1/bin/elm"])

    def test_offline_arguments(self):
        elm_json = {"type": "package", "test-dependencies": {"elm-explorations/test": "2.0.0 <= v < 3.0.0"}}
        command = cli.elm_test_command(TOOLCHAINS["0.19.2"], elm_json, offline=True)
        self.assertEqual(command[-1], "--offline")

    def test_missing_runner_fails(self):
        elm_json = {"type": "package", "test-dependencies": {"elm-explorations/test": "1.0.0 <= v < 2.0.0"}}
        with self.assertRaises(SystemExit):
            cli.elm_test(TOOLCHAINS["0.19.2"], elm_json)


class ProjectScanning(unittest.TestCase):
    def project(self, files):
        root = tempfile.mkdtemp()
        for path, text in files.items():
            full = os.path.join(root, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as f:
                f.write(text)
        return root

    def test_finds_modules_that_define_main(self):
        root = self.project({
            "src/Main.elm": "module Main exposing (main)\n\nmain = text \"\"\n",
            "src/Pages/Admin.elm": "port module Pages.Admin exposing (main)\n\nmain : Program () () ()\nmain = worker\n",
            "src/Helpers.elm": "module Helpers exposing (x)\n\nx = mainly\n",
            "lib/Other.elm": "module Other exposing (main)\n\nmain = 1\n",
        })
        mains = cli.find_mains(root, {"source-directories": ["src"]})
        self.assertEqual(mains, ["src/Main.elm", "src/Pages/Admin.elm"])
        self.assertEqual(cli.module_name(os.path.join(root, mains[1])), "Pages.Admin")

    def test_tests_need_an_elm_module(self):
        self.assertFalse(cli.has_tests(self.project({"tests/elm-package.json": "{}"})))
        self.assertTrue(cli.has_tests(self.project({"tests/Suite/A.elm": "module Suite.A exposing (x)"})))


class PackageCache(unittest.TestCase):
    def test_trim_keeps_what_the_compiler_keeps(self):
        package = tempfile.mkdtemp()
        for path in ["elm.json", "README.md", "LICENSE", "src/Basics.elm", "tests/Test.elm", ".travis.yml"]:
            os.makedirs(os.path.dirname(os.path.join(package, path)), exist_ok=True)
            with open(os.path.join(package, path), "w") as f:
                f.write(path)
        elm_home.trim(package)
        found = sorted(
            os.path.relpath(os.path.join(d, f), package)
            for d, _, fs in os.walk(package) for f in fs
        )
        self.assertEqual(found, ["LICENSE", "README.md", "elm.json", "src/Basics.elm"])

    def test_registry_encoding(self):
        data = elm_home.registry(["elm/core/1.0.2", "elm/core/1.0.5", "a/b/300.0.1"])
        position = 0

        def take(n):
            nonlocal position
            chunk = data[position:position + n]
            position += n
            return chunk

        self.assertEqual(struct.unpack(">qq", take(16)), (3, 2))
        # Names in byte order: "a" sorts before "elm".
        self.assertEqual(take(2), b"\x01a")
        self.assertEqual(take(2), b"\x01b")
        # 300 does not fit in a byte, so the version takes the long form.
        self.assertEqual(take(7), b"\xff" + struct.pack(">HHH", 300, 0, 1))
        self.assertEqual(struct.unpack(">q", take(8)), (0,))
        self.assertEqual(take(4), b"\x03elm")
        self.assertEqual(take(5), b"\x04core")
        self.assertEqual(take(3), bytes([1, 0, 5]))
        self.assertEqual(struct.unpack(">q", take(8)), (1,))
        self.assertEqual(take(3), bytes([1, 0, 2]))
        self.assertEqual(position, len(data))


if __name__ == "__main__":
    unittest.main()
