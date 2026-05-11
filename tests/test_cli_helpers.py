import importlib.machinery
import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin" / "docker-migrate"


def load_module():
    loader = importlib.machinery.SourceFileLoader("docker_migrate", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


docker_migrate = load_module()


class HelperTests(unittest.TestCase):
    def test_parse_selection_supports_ranges_and_dedupes(self):
        self.assertEqual(docker_migrate.parse_selection("1,3-4,3", 5), [0, 2, 3])

    def test_parse_selection_all_and_empty(self):
        self.assertEqual(docker_migrate.parse_selection("all", 3), [0, 1, 2])
        self.assertEqual(docker_migrate.parse_selection("", 3), [])

    def test_archive_name_default_extension(self):
        self.assertEqual(docker_migrate.ensure_archive_name("backup"), "backup.tar.gz")
        self.assertEqual(docker_migrate.ensure_archive_name("backup.tgz"), "backup.tgz")

    def test_mount_spec_for_volume(self):
        spec = docker_migrate.mount_spec(
            {
                "Type": "volume",
                "Name": "app_data",
                "Destination": "/var/lib/app",
                "RW": False,
            }
        )
        self.assertEqual(spec, "type=volume,source=app_data,target=/var/lib/app,readonly")

    def test_restart_policy(self):
        self.assertEqual(
            docker_migrate.restart_policy_arg({"Name": "on-failure", "MaximumRetryCount": 3}),
            "on-failure:3",
        )
        self.assertIsNone(docker_migrate.restart_policy_arg({"Name": "no"}))


if __name__ == "__main__":
    unittest.main()
