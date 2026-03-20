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
        self.assertIn("use_release_deb: true", workflow)
        self.assertIn("release_deb_artifact_prefix: release-deb", workflow)
        self.assertIn(
            "needs: [build-release-debs, smoke-release, release-integration]",
            workflow,
        )

    def test_integration_workflow_can_consume_release_deb_artifact(self) -> None:
        workflow = read_text(".github/workflows/integration-test.yml")
        self.assertIn("use_release_deb:", workflow)
        self.assertIn("release_deb_artifact_prefix:", workflow)
        self.assertIn("Download release deb artifact", workflow)
        self.assertIn("Resolve release deb path", workflow)
        self.assertIn("matrix.arch", workflow)
        self.assertIn("ubuntu-24.04-arm", workflow)
        self.assertIn("rclone-linux-${{ matrix.arch }}", workflow)
        self.assertIn('-e PACKAGE_DEB="${{ env.PACKAGE_DEB }}"', workflow)
        self.assertIn("PACKAGE_DEB=/workspace/$DEB", workflow)
        self.assertIn("MATCHES=(dist/*.deb)", workflow)
        self.assertIn('[ "${#MATCHES[@]}" -eq 1 ]', workflow)
        self.assertIn(
            "${{ inputs.release_deb_artifact_prefix }}-${{ matrix.arch }}", workflow
        )
        self.assertIn(
            "- ubuntu: jammy\n            image: ubuntu:22.04\n            arch: amd64\n            runner: ubuntu-22.04",
            workflow,
        )
        self.assertIn(
            "- ubuntu: noble\n            image: ubuntu:24.04\n            arch: amd64\n            runner: ubuntu-22.04",
            workflow,
        )
        self.assertIn(
            "- ubuntu: jammy\n            image: ubuntu:22.04\n            arch: arm64\n            runner: ubuntu-24.04-arm",
            workflow,
        )
        self.assertIn(
            "- ubuntu: noble\n            image: ubuntu:24.04\n            arch: arm64\n            runner: ubuntu-24.04-arm",
            workflow,
        )

    def test_private_link_mock_covers_amd64_and_arm64(self) -> None:
        workflow = read_text(".github/workflows/integration-test.yml")
        self.assertIn("Private Link DNS mock test (${{ matrix.arch }})", workflow)
        self.assertIn(
            'ZIP="rclone-v${RCLONE_VER}-linux-${{ matrix.arch }}.zip"', workflow
        )
        self.assertIn("rclone-bins/rclone-linux-${{ matrix.arch }}", workflow)
        self.assertIn(
            "--build-arg RCLONE_BIN=rclone-linux-${{ matrix.arch }}", workflow
        )
        self.assertIn("- arch: amd64\n            runner: ubuntu-22.04", workflow)
        self.assertIn("- arch: arm64\n            runner: ubuntu-24.04-arm", workflow)
        dockerfile = read_text(".github/docker/Dockerfile.private-link")
        self.assertIn("ARG RCLONE_BIN=rclone-linux-amd64", dockerfile)
        self.assertIn(
            "COPY rclone-bins/${RCLONE_BIN} /usr/local/bin/rclone", dockerfile
        )

    def test_integration_script_supports_package_runtime_path(self) -> None:
        integration_script = read_text(".github/scripts/run-integration-test.sh")
        self.assertIn('PACKAGE_DEB="${PACKAGE_DEB:-}"', integration_script)
        self.assertIn('dpkg -i "$RESOLVED_PACKAGE_DEB"', integration_script)
        self.assertIn(
            "mapfile -t matches < <(for f in $pattern; do", integration_script
        )
        self.assertIn('case "$RCLONE_BIN_ARCH" in', integration_script)
        self.assertIn(
            "/usr/share/rclone-azureblob-airgap/scripts/verify-azureblob.sh",
            integration_script,
        )
        self.assertIn("/usr/bin/rclone", integration_script)
        self.assertIn('red "release deb 설치 후 libfuse3-3 미설치"', integration_script)

    def test_acceptance_criteria_mentions_arm64_private_link_coverage(self) -> None:
        acceptance = read_text("docs/engineering/acceptance-criteria.md")
        self.assertIn(
            "amd64 + arm64 runner 에서 DNS mock + Azurite endpoint",
            acceptance,
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

    def test_private_link_mount_success_requires_mountpoint(self) -> None:
        private_link_script = read_text(".github/scripts/docker-private-link-test.sh")
        self.assertIn('mountpoint -q "$MOUNT_PT" 2>/dev/null', private_link_script)
        self.assertNotIn('if ls "$MOUNT_PT" &>/dev/null; then', private_link_script)
        self.assertNotIn('|| ls "$MOUNT_PT"', private_link_script)
        self.assertIn(
            "--vfs-write-back 0s",
            private_link_script,
        )
        self.assertIn(
            'rclone cat "azblob-private:private-test/$WRITE_BASENAME"',
            private_link_script,
        )
        self.assertIn(
            'if echo "$WRITE_CONTENT" >"$MOUNT_PT/$WRITE_BASENAME"; then',
            private_link_script,
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

    def test_verify_azureblob_defines_info_helper(self) -> None:
        verify = read_text("scripts/verify-azureblob.sh")
        self.assertIn("info() {", verify)

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
