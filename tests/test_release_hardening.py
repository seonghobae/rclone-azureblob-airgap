import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]


def read_text(relative_path: str) -> str:
    return (REPO_ROOT / relative_path).read_text(encoding="utf-8")


class ReleaseHardeningTests(unittest.TestCase):
    def test_release_workflow_reuses_integration_checks_before_create_release(
        self,
    ) -> None:
        workflow = read_text(".github/workflows/release.yml")
        self.assertIn("uses: ./.github/workflows/integration-test.yml", workflow)
        self.assertIn(
            "needs: [build-release-debs, smoke-release, release-integration]",
            workflow,
        )

    def test_package_smoke_paths_do_not_force_depends_install(self) -> None:
        release_workflow = read_text(".github/workflows/release.yml")
        build_workflow = read_text(".github/workflows/build-deb.yml")
        self.assertNotIn("dpkg -i --force-depends dist/*.deb", release_workflow)
        self.assertNotIn("dpkg -i --force-depends dist/*.deb", build_workflow)

    def test_fuse_install_commands_do_not_mask_dpkg_failures(self) -> None:
        postinst = read_text("debian/postinst")
        install_script = read_text("scripts/install.sh")
        self.assertNotIn(
            '| grep -v "^(Selecting\\|Preparing\\|Unpacking\\|Setting up\\|Processing)" || true',
            postinst,
        )
        self.assertNotIn(
            'dpkg -i --force-depends "${pkgs_ordered[@]}" 2>&1 | grep -v "^(Reading\\|Selecting\\|Preparing\\|Unpacking\\|Setting up\\|Processing)" || true',
            install_script,
        )
        self.assertIn(
            'if ! dpkg -i --force-depends "$libpkg" "$fuse3pkg" >"$dpkg_log" 2>&1; then',
            postinst,
        )
        self.assertIn(
            'if ! dpkg -i --force-depends "${pkgs_ordered[@]}" >"$dpkg_log" 2>&1; then',
            install_script,
        )

    def test_mount_success_checks_do_not_fallback_to_ls(self) -> None:
        integration_script = read_text(".github/scripts/run-integration-test.sh")
        verify_azure = read_text("scripts/verify-azureblob.sh")
        self.assertNotIn(
            'mountpoint -q "$MOUNT_POINT" 2>/dev/null || ls "$MOUNT_POINT" &>/dev/null',
            integration_script,
        )
        self.assertNotIn(
            'mountpoint -q "$TMPDIR_MNT" 2>/dev/null || ls "$TMPDIR_MNT" &>/dev/null',
            verify_azure,
        )

    def test_integration_script_does_not_mask_release_critical_failures(self) -> None:
        integration_script = read_text(".github/scripts/run-integration-test.sh")
        self.assertNotIn(
            '2>/dev/null || true\ngreen "verify-azureblob.sh 완료"',
            integration_script,
        )
        self.assertIn("if ! dpkg -i --force-depends \\", integration_script)

    def test_packaged_paths_are_used_in_runtime_guidance(self) -> None:
        configure = read_text("scripts/configure-azureblob.sh")
        verify = read_text("scripts/verify-azureblob.sh")
        self.assertIn(
            "/usr/share/rclone-azureblob-airgap/azure/conf-examples/azblob-key.conf",
            configure,
        )
        self.assertIn("/lib/systemd/system/rclone-azureblob@.service", verify)
        self.assertIn(
            "/usr/share/rclone-azureblob-airgap/azure/rclone-azureblob.conf",
            verify,
        )

    def test_required_canonical_docs_exist(self) -> None:
        required = [
            "docs/engineering/acceptance-criteria.md",
            "docs/engineering/harness-engineering.md",
            "docs/agents/README.md",
            "docs/coderabbit/review-commands.md",
            "docs/operations/deploy-runbook.md",
            "docs/workflow/delivery-plan.md",
            "docs/workflow/one-day-delivery-plan.md",
            "docs/workflow/pr-continuity.md",
        ]
        for relative_path in required:
            with self.subTest(path=relative_path):
                self.assertTrue((REPO_ROOT / relative_path).is_file(), relative_path)


if __name__ == "__main__":
    unittest.main()
