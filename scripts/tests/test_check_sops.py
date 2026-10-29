"""Pruebas de check_sops.py (requisitos 3.1–3.4 y 3.7).

Los fixtures usan metadatos falsos: no hay archivos cifrados reales ni llaves.
"""

import io
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

TESTS = Path(__file__).resolve().parent
ROOT = TESTS.parent.parent
FIXTURES = TESTS / "fixtures" / "sops"
CATALOG = FIXTURES / "catalog"
REAL_CONFIG = ROOT / ".sops.yaml"
sys.path.insert(0, str(ROOT / "scripts"))

import check_sops  # noqa: E402

PERSONAL = "age1rxr6aweysej7xvdcdejw9dlyp3vzp0rtmhn64rfzcn0q72z08ues62h44y"
CI = "age1fnuy5xuw0udwz0mggcgfuj7hy5u689dz6y46sqfvcp5svf40259qg3lxwc"
PLAINTEXT_MARKER = "not-a-secret-plaintext-marker"


def run(*argv):
    out = io.StringIO()
    with redirect_stdout(out):
        code = check_sops.main(["--catalog", str(CATALOG), *argv])
    return code, out.getvalue().splitlines()


def check(case, *extra):
    return run(*extra, str(CATALOG / case / "secrets.enc.yaml"))


def display(case):
    return f"catalog/{case}/secrets.enc.yaml"


class ConfigTest(unittest.TestCase):
    def test_config_has_one_rule_with_both_public_keys(self):  # 3.1, 3.2
        rules = check_sops.load_rules(REAL_CONFIG)
        self.assertEqual(len(rules), 1)
        regex, recipients = rules[0]
        self.assertEqual(recipients, {PERSONAL, CI})
        self.assertTrue(regex.search("catalog/demo/secrets.enc.yaml"))
        self.assertFalse(regex.search("catalog/demo/app.yaml"))
        self.assertFalse(regex.search("catalog/a/b/secrets.enc.yaml"))

    def test_config_contains_no_private_key(self):  # 3.2
        self.assertNotIn("AGE-SECRET-KEY", REAL_CONFIG.read_text(encoding="utf-8").upper())


class CheckSopsTest(unittest.TestCase):
    def assertRejected(self, case, lines, fragment):
        prefix = f"{display(case)}: "
        matching = [line for line in lines if line.startswith(prefix)]
        self.assertTrue(matching, f"ningún error empieza con {prefix!r}: {lines}")
        self.assertTrue(any(fragment in line for line in matching), matching)
        for line in lines:
            self.assertNotIn("ENC[", line)
            self.assertNotIn("RkFLRQ", line)
            self.assertNotIn(PLAINTEXT_MARKER, line)

    def test_valid_file(self):
        self.assertEqual(check("valid"), (0, []))

    def test_without_metadata(self):  # 3.4
        code, lines = check("no-metadata")
        self.assertEqual(code, 1)
        self.assertRejected("no-metadata", lines, "sin metadatos de cifrado")

    def test_plaintext_value(self):
        code, lines = check("plaintext-value")
        self.assertEqual(code, 1)
        self.assertRejected("plaintext-value", lines, "valor sin cifrar en nested.FAKE_PLAIN")

    def test_incomplete_recipients(self):  # 3.3
        code, lines = check("incomplete-recipients")
        self.assertEqual(code, 1)
        self.assertRejected("incomplete-recipients", lines, "destinatarios distintos")
        self.assertTrue(any("faltan" in line and CI in line for line in lines), lines)

    def test_foreign_recipients(self):  # 3.3
        code, lines = check("foreign-recipients")
        self.assertEqual(code, 1)
        self.assertRejected("foreign-recipients", lines, "destinatarios distintos")
        self.assertTrue(any("sobran" in line for line in lines), lines)

    def test_scans_whole_catalog_without_paths(self):
        code, lines = run()
        self.assertEqual(code, 1)
        reported = {line.split(": ", 1)[0] for line in lines}
        self.assertEqual(
            reported,
            {display(c) for c in ("no-metadata", "plaintext-value", "incomplete-recipients", "foreign-recipients")},
        )

    def test_path_without_matching_rule(self):
        with tempfile.TemporaryDirectory() as tmp:
            other = Path(tmp) / "secrets.enc.yaml"
            shutil.copy(CATALOG / "valid" / "secrets.enc.yaml", other)
            code, lines = run(str(other))
        self.assertEqual(code, 1)
        self.assertTrue(lines and "ninguna regla" in lines[0], lines)

    def test_unreadable_yaml(self):
        with tempfile.TemporaryDirectory() as tmp:
            catalog = Path(tmp) / "catalog"
            (catalog / "broken").mkdir(parents=True)
            (catalog / "broken" / "secrets.enc.yaml").write_text("a: [unclosed\n", encoding="utf-8")
            out = io.StringIO()
            with redirect_stdout(out):
                code = check_sops.main(["--catalog", str(catalog)])
        self.assertEqual(code, 1)
        self.assertIn("catalog/broken/secrets.enc.yaml: YAML inválido", out.getvalue())

    def test_underscore_folders_are_scanned(self):  # 3.4: la excepción de 4.9 es solo para app.yaml
        with tempfile.TemporaryDirectory() as tmp:
            catalog = Path(tmp) / "catalog"
            (catalog / "_old").mkdir(parents=True)
            (catalog / "_old" / "secrets.enc.yaml").write_text("API_KEY: valor-falso\n", encoding="utf-8")
            out = io.StringIO()
            with redirect_stdout(out):
                code = check_sops.main(["--catalog", str(catalog)])
        self.assertEqual(code, 1)
        self.assertIn("catalog/_old/secrets.enc.yaml: ", out.getvalue())

    def test_non_utf8_secrets_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            catalog = Path(tmp) / "catalog"
            (catalog / "binary").mkdir(parents=True)
            (catalog / "binary" / "secrets.enc.yaml").write_bytes(b"KEY: \xff\xfe\n")
            out = io.StringIO()
            with redirect_stdout(out):
                code = check_sops.main(["--catalog", str(catalog)])
        lines = out.getvalue().splitlines()
        self.assertEqual(code, 1)
        self.assertEqual(lines, ["catalog/binary/secrets.enc.yaml: no se puede leer (UnicodeDecodeError)"])

    def test_never_invokes_external_tools(self):  # 3.7
        with mock.patch("subprocess.run") as sub_run, mock.patch("subprocess.Popen") as popen:
            check("valid")
            check("foreign-recipients")
        sub_run.assert_not_called()
        popen.assert_not_called()


class ConfigErrorTest(unittest.TestCase):
    def config_case(self, content):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / ".sops.yaml"
            if content is not None:
                config.write_text(content, encoding="utf-8")
            return check("valid", "--config", str(config))

    def test_missing_config(self):
        code, lines = self.config_case(None)
        self.assertEqual(code, 2)
        self.assertTrue(lines and ".sops.yaml" in lines[0], lines)

    def test_non_utf8_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / ".sops.yaml"
            config.write_bytes(b"\xff")
            code, lines = check("valid", "--config", str(config))
        self.assertEqual(code, 2)
        self.assertTrue(lines and "no se puede leer (UnicodeDecodeError)" in lines[0], lines)

    def test_invalid_yaml_config(self):
        self.assertEqual(self.config_case("creation_rules: [\n")[0], 2)

    def test_config_without_rules(self):
        self.assertEqual(self.config_case("other: 1\n")[0], 2)

    def test_rule_without_age(self):
        self.assertEqual(self.config_case("creation_rules:\n  - path_regex: ^catalog/\n")[0], 2)

    def test_rule_with_invalid_regex(self):
        self.assertEqual(self.config_case(f"creation_rules:\n  - path_regex: '['\n    age: {PERSONAL}\n")[0], 2)

    def test_config_with_private_key(self):
        content = f"creation_rules:\n  - path_regex: ^catalog/\n    age: {PERSONAL}\n# AGE-SECRET-KEY-1FAKE\n"
        code, lines = self.config_case(content)
        self.assertEqual(code, 2)
        self.assertFalse(any("FAKE" in line for line in lines), lines)


class RealCatalogTest(unittest.TestCase):
    def test_real_catalog_passes(self):
        out = io.StringIO()
        with redirect_stdout(out):
            code = check_sops.main([])
        self.assertEqual((code, out.getvalue()), (0, ""))


if __name__ == "__main__":
    unittest.main()
