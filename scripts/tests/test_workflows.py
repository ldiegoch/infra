"""Pruebas estáticas de los workflows de GitHub Actions (requisitos 7.2, 7.4, 9.1, 9.2, 9.4).

Las funciones `*_errors` reciben el directorio de workflows, así que las
mismas reglas se prueban contra .github/workflows y contra los ejemplos
inválidos de fixtures/workflows.
"""

import re
import unittest
from pathlib import Path

import yaml

TESTS = Path(__file__).resolve().parent
ROOT = TESTS.parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"
FIXTURES = TESTS / "fixtures" / "workflows"

SHA_REF = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")
DIGEST_REF = re.compile(r"@sha256:[0-9a-f]{64}$")


def load(path):
    with open(path, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def workflows(directory):
    """Devuelve [(nombre, documento)] de los .yml/.yaml del directorio."""
    paths = sorted(p for p in Path(directory).iterdir() if p.suffix in (".yml", ".yaml"))
    return [(p.name, load(p)) for p in paths]


def triggers(doc):
    """Disparadores del workflow. PyYAML lee la clave `on` como True."""
    on = doc.get("on", doc.get(True))
    if isinstance(on, str):
        return {on: None}
    if isinstance(on, list):
        return {name: None for name in on}
    return on or {}


def uses_refs(doc):
    """Todos los `uses:` del workflow: de jobs (reutilizables) y de pasos."""
    for job_id, job in (doc.get("jobs") or {}).items():
        if "uses" in job:
            yield job_id, job["uses"]
        for step in job.get("steps") or []:
            if "uses" in step:
                yield job_id, step["uses"]


def pinning_errors(directory):
    errors = []
    for name, doc in workflows(directory):
        for job_id, ref in uses_refs(doc):
            if ref.startswith("./"):
                continue  # workflow o acción local del mismo repositorio
            if ref.startswith("docker://"):
                ok = bool(DIGEST_REF.search(ref))
            else:
                ok = bool(SHA_REF.match(ref))
            if not ok:
                errors.append(f"{name}: jobs.{job_id}: {ref} no está fijada a un SHA")
    return errors


def permissions_errors(directory):
    errors = []
    for name, doc in workflows(directory):
        if set(triggers(doc)) <= {"workflow_call"}:
            continue  # reutilizable: hereda los permisos del llamador
        if "permissions" not in doc:
            errors.append(f"{name}: falta permissions a nivel de workflow")
        elif doc["permissions"] != {"contents": "read"}:
            errors.append(f"{name}: permissions por defecto debe ser solo contents: read")
    return errors


class WorkflowsTest(unittest.TestCase):
    def setUp(self):
        self.docs = dict(workflows(WORKFLOWS))
        for required in ("apply.yml", "pr.yml", "_tofu-stack.yml"):
            self.assertIn(required, self.docs, f"falta .github/workflows/{required}")

    # 9.1
    def test_actions_pinned_to_sha(self):
        self.assertEqual(pinning_errors(WORKFLOWS), [])

    def test_workflows_have_remote_actions(self):
        # Evita que la prueba de SHA pase en vacío.
        refs = [r for _, d in self.docs.items() for _, r in uses_refs(d) if not r.startswith("./")]
        self.assertTrue(refs, "no se encontró ninguna acción remota")

    def test_tag_instead_of_sha_is_rejected(self):
        errors = pinning_errors(FIXTURES / "tag-pinned")
        self.assertEqual(errors, ["ci.yml: jobs.build: actions/checkout@v4 no está fijada a un SHA"])

    # 9.2
    def test_permissions_declared(self):
        self.assertEqual(permissions_errors(WORKFLOWS), [])

    def test_reusable_workflow_is_exempt(self):
        stack = self.docs["_tofu-stack.yml"]
        self.assertEqual(set(triggers(stack)), {"workflow_call"})
        self.assertNotIn("permissions", stack)

    def test_missing_permissions_is_rejected(self):
        errors = permissions_errors(FIXTURES / "no-permissions")
        self.assertEqual(errors, ["ci.yml: falta permissions a nivel de workflow"])

    # 7.2
    def test_apply_only_on_push_to_main(self):
        on = triggers(self.docs["apply.yml"])
        self.assertEqual(set(on), {"push"}, "apply.yml solo debe dispararse con push")
        push = on["push"] or {}
        self.assertEqual(push.get("branches"), ["main"], "apply.yml solo debe correr en main")
        for key in ("branches-ignore", "tags", "tags-ignore"):
            self.assertNotIn(key, push, f"apply.yml no debe usar {key}")

    # 7.4
    def test_apply_concurrency(self):
        concurrency = self.docs["apply.yml"].get("concurrency")
        self.assertEqual(
            concurrency,
            {"group": "tofu-production", "cancel-in-progress": False},
            "apply.yml necesita concurrency tofu-production sin cancelación",
        )

    def test_apply_jobs_do_not_redefine_concurrency(self):
        # Un grupo igual a nivel de job bloquearía al de workflow.
        for job_id, job in self.docs["apply.yml"]["jobs"].items():
            self.assertNotIn("concurrency", job, f"apply.yml: jobs.{job_id} redefine concurrency")

    # 9.4
    def test_pr_plan_only_same_repository(self):
        plan = self.docs["pr.yml"]["jobs"].get("plan")
        self.assertIsNotNone(plan, "pr.yml: falta el job plan")
        condition = re.sub(r"\s+", " ", str(plan.get("if", ""))).strip()
        condition = condition.removeprefix("${{").removesuffix("}}").strip()
        self.assertEqual(
            condition,
            "github.event.pull_request.head.repo.full_name == github.repository",
            "pr.yml: el plan debe condicionarse al mismo repositorio",
        )

    def test_pr_plan_needs_checks(self):
        plan = self.docs["pr.yml"]["jobs"]["plan"]
        needs = plan.get("needs")
        needs = [needs] if isinstance(needs, str) else needs or []
        self.assertIn("checks", needs, "pr.yml: el plan debe depender de checks")

    def test_pr_plan_is_never_cancelled(self):
        # Cancelar un plan con el bloqueo de R2 tomado lo deja huérfano.
        doc = self.docs["pr.yml"]
        self.assertFalse(doc.get("concurrency", {}).get("cancel-in-progress"), "pr.yml: concurrency de workflow cancela el plan")
        plan = doc["jobs"]["plan"].get("concurrency", {})
        self.assertIs(plan.get("cancel-in-progress"), False, "pr.yml: el plan necesita cancel-in-progress: false")


if __name__ == "__main__":
    unittest.main()
