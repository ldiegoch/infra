"""Pruebas de check_catalog.py (requisitos 4.1–4.9)."""

import io
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path

TESTS = Path(__file__).resolve().parent
ROOT = TESTS.parent.parent
FIXTURES = TESTS / "fixtures" / "catalog"
sys.path.insert(0, str(ROOT / "scripts"))

import check_catalog  # noqa: E402


def run(*argv):
    out = io.StringIO()
    with redirect_stdout(out):
        code = check_catalog.main(list(argv))
    return code, out.getvalue().splitlines()


def check(app):
    return run(str(FIXTURES / app / "app.yaml"))


class CheckCatalogTest(unittest.TestCase):
    def assertRejected(self, app, field, lines, fragment=None):
        self.assertTrue(lines, f"{app}: se esperaba al menos un error")
        prefix = f"{app}: {field}: "
        matching = [line for line in lines if line.startswith(prefix)]
        self.assertTrue(matching, f"ningún error empieza con {prefix!r}: {lines}")
        if fragment:
            self.assertTrue(any(fragment in line for line in matching), matching)

    def test_valid_app(self):
        self.assertEqual(check("valid-app"), (0, []))

    def test_image_without_digest(self):  # 4.3
        code, lines = check("image-tag")
        self.assertEqual(code, 1)
        self.assertRejected("image-tag", "services.web.image", lines, "digest")

    def test_name_not_kebab_case(self):  # 4.4
        code, lines = check("Bad_Name")
        self.assertEqual(code, 1)
        self.assertRejected("Bad_Name", "name", lines, "kebab-case")

    def test_name_differs_from_folder(self):  # 4.4
        code, lines = check("name-mismatch")
        self.assertEqual(code, 1)
        self.assertRejected("name-mismatch", "name", lines, "carpeta")

    def test_private_service_with_hostname(self):  # 4.5
        code, lines = check("private-hostname")
        self.assertEqual(code, 1)
        self.assertRejected("private-hostname", "services.web.hostname", lines, "public: true")

    def test_public_service_without_hostname(self):  # 4.5
        code, lines = check("public-no-hostname")
        self.assertEqual(code, 1)
        self.assertRejected("public-no-hostname", "services.web", lines, "hostname")

    def test_wildcard_hostname(self):  # 4.6
        code, lines = check("wildcard-hostname")
        self.assertEqual(code, 1)
        self.assertRejected("wildcard-hostname", "services.web.hostname", lines)

    def test_uses_database_without_neon(self):  # 4.7
        code, lines = check("db-without-neon")
        self.assertEqual(code, 1)
        self.assertRejected("db-without-neon", "services.web.uses_database", lines, "database.neon")

    def test_secrets_must_be_names(self):  # 4.8
        code, lines = check("secret-value")
        self.assertEqual(code, 1)
        self.assertRejected("secret-value", "services.web.secrets.0", lines)
        self.assertFalse(any("valor-falso" in line for line in lines), "el mensaje expone el valor")

    def test_template_folder_ignored_when_passed(self):  # 4.9
        self.assertEqual(run(str(FIXTURES / "_template" / "app.yaml")), (0, []))

    def test_template_folder_ignored_on_discovery(self):  # 4.9
        code, lines = run("--catalog", str(FIXTURES))
        self.assertEqual(code, 1)
        self.assertFalse(any(line.startswith("_template:") for line in lines), lines)
        self.assertTrue(any(line.startswith("image-tag:") for line in lines), lines)

    def test_real_catalog_passes(self):
        self.assertEqual(run("--catalog", str(ROOT / "catalog")), (0, []))

    def test_missing_schema_exits_2(self):
        code, _ = run("--schema", str(TESTS / "no-existe.json"), str(FIXTURES / "valid-app" / "app.yaml"))
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
