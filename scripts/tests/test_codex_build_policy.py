#!/usr/bin/env python3
"""Policy tests for scripts/codex-build.sh.

These tests execute the exact bytes of the repository build helper inside a
disposable fixture tree with PATH stubs for Git, Xcode, tee and the prune
helper. They assert fail-closed behaviour, discovery semantics, exit-status
propagation, marker truthfulness and artifact preservation.
"""

from __future__ import annotations

import hashlib
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HELPER_PATH = REPO_ROOT / "scripts" / "codex-build.sh"
HELPER_BYTES = HELPER_PATH.read_bytes()

GIT_STUB = r"""#!/bin/bash
set -u
printf 'git %s\n' "$*" >> "${CALL_LOG}"
command_name=""
for argument in "$@"; do
  case "${argument}" in
    rev-parse|diff|ls-files)
      command_name="${argument}"
      break
      ;;
  esac
done
case "${command_name}" in
  rev-parse)
    exit "${GIT_HEAD_EXIT:-0}"
    ;;
  diff)
    if [[ -n "${GIT_TRACKED_OUTPUT_FILE:-}" ]]; then
      cat "${GIT_TRACKED_OUTPUT_FILE}"
    fi
    exit "${GIT_TRACKED_EXIT:-0}"
    ;;
  ls-files)
    if [[ -n "${GIT_UNTRACKED_OUTPUT_FILE:-}" ]]; then
      cat "${GIT_UNTRACKED_OUTPUT_FILE}"
    fi
    exit "${GIT_UNTRACKED_EXIT:-0}"
    ;;
  *)
    echo "unexpected git invocation: $*" >&2
    exit 99
    ;;
esac
"""

XCODEBUILD_STUB = r"""#!/bin/bash
set -u
printf 'xcodebuild %s\n' "$*" >> "${CALL_LOG}"
if [[ -n "${XCODE_OUTPUT_FILE:-}" ]]; then
  cat "${XCODE_OUTPUT_FILE}"
fi
exit "${XCODE_EXIT:-0}"
"""

TEE_STUB = r"""#!/bin/bash
set -u
printf 'tee %s\n' "$*" >> "${CALL_LOG}"
if [[ "${TEE_FAIL:-0}" == "1" ]]; then
  cat >/dev/null
  exit 1
fi
exec /usr/bin/tee "$@"
"""

PRUNE_STUB = r"""#!/bin/bash
set -u
printf 'prune %s\n' "$*" >> "${CALL_LOG}"
exit 0
"""


class CodexBuildPolicyTests(unittest.TestCase):
    """Fail-closed build-helper policy, exercised through the real script bytes."""

    def setUp(self) -> None:
        self._tempdir = tempfile.TemporaryDirectory(prefix="codex-build-policy-")
        self.root = Path(self._tempdir.name)
        self.call_log = self.root / "calls.log"
        self.call_log.write_text("")
        self.bin_dir = self.root / "stub-bin"
        self.bin_dir.mkdir()
        self._write_stub("git", GIT_STUB)
        self._write_stub("xcodebuild", XCODEBUILD_STUB)
        self._write_stub("tee", TEE_STUB)

        scripts = self.root / "scripts"
        scripts.mkdir()
        # The fixture helper is byte-identical to the repository helper.
        (scripts / "codex-build.sh").write_bytes(HELPER_BYTES)
        self._write_stub_in(scripts / "prune-app-bundles.sh", PRUNE_STUB)
        for directory in ("AudioMator", "AudioMatorTests", "AudioMator.xcodeproj", "Config"):
            (self.root / directory).mkdir()
        (self.root / "Docs").mkdir()
        (self.root / "Tests").mkdir()
        self.tmpdir = self.root / "tmp"
        self.tmpdir.mkdir()

        # Two disposable artifacts that the old helper's implicit prune would
        # have removed: an alternate derived-data root and an app bundle.
        self.other_derived_data = self.root / ".deriveddata-other" / "Build" / "Products" / "Debug"
        self.other_derived_data.mkdir(parents=True)
        (self.other_derived_data / "Other.app").mkdir()
        (self.other_derived_data / "Other.app" / "Contents").mkdir()
        (self.other_derived_data / "Other.app" / "Contents" / "Info.plist").write_text("other")
        self.other_app = self.root / "TestAssets" / "Other.app"
        self.other_app.mkdir(parents=True)
        (self.other_app / "Contents").mkdir()
        (self.other_app / "Contents" / "Info.plist").write_text("other")

        self.git_tracked_file = self.root / "git-tracked.bin"
        self.git_untracked_file = self.root / "git-untracked.bin"
        self.xcode_output_file = self.root / "xcode-output.txt"
        self.set_git_output(tracked=b"", untracked=b"")
        self.set_xcode_output(b"** BUILD SUCCEEDED **\n", exit_code=0)

    def tearDown(self) -> None:
        self._tempdir.cleanup()

    # -- fixture helpers -----------------------------------------------------

    def _write_stub(self, name: str, contents: str) -> None:
        self._write_stub_in(self.bin_dir / name, contents)

    def _write_stub_in(self, path: Path, contents: str) -> None:
        path.write_text(contents)
        path.chmod(0o755)

    def set_git_output(
        self,
        tracked: bytes,
        untracked: bytes,
        tracked_exit: int = 0,
        untracked_exit: int = 0,
        head_exit: int = 0,
    ) -> None:
        self.git_tracked_file.write_bytes(tracked)
        self.git_untracked_file.write_bytes(untracked)
        self.git_env = {
            "GIT_TRACKED_OUTPUT_FILE": str(self.git_tracked_file),
            "GIT_UNTRACKED_OUTPUT_FILE": str(self.git_untracked_file),
            "GIT_TRACKED_EXIT": str(tracked_exit),
            "GIT_UNTRACKED_EXIT": str(untracked_exit),
            "GIT_HEAD_EXIT": str(head_exit),
        }

    def set_xcode_output(self, output: bytes, exit_code: int) -> None:
        self.xcode_output_file.write_bytes(output)
        self.xcode_env = {
            "XCODE_OUTPUT_FILE": str(self.xcode_output_file),
            "XCODE_EXIT": str(exit_code),
        }

    def _environment(self, extra: dict[str, str] | None = None) -> dict[str, str]:
        environment = {
            "PATH": f"{self.bin_dir}:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": str(self.root),
            "TMPDIR": str(self.tmpdir),
            "CALL_LOG": str(self.call_log),
            "LANG": "en_US.UTF-8",
        }
        environment.update(self.git_env)
        environment.update(self.xcode_env)
        if extra:
            environment.update(extra)
        return environment

    def run_helper(
        self,
        arguments: list[str] | None = None,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        command = ["/bin/bash", str(self.root / "scripts" / "codex-build.sh")]
        command.extend(arguments or [])
        return subprocess.run(
            command,
            cwd=self.root,
            env=self._environment(extra_env),
            capture_output=True,
            text=True,
            timeout=120,
        )

    def recorded_calls(self) -> list[str]:
        return [line for line in self.call_log.read_text().splitlines() if line]

    def xcodebuild_calls(self) -> list[str]:
        return [line for line in self.recorded_calls() if line.startswith("xcodebuild ")]

    def git_calls(self) -> list[str]:
        return [line for line in self.recorded_calls() if line.startswith("git ")]

    def prune_calls(self) -> list[str]:
        return [line for line in self.recorded_calls() if line.startswith("prune ")]

    def build_log_path(self) -> Path:
        return self.root / ".deriveddata-codex" / "xcodebuild.log"

    def expected_xcodebuild_arguments(self) -> list[str]:
        return [
            "xcodebuild",
            "-project",
            str(self.root / "AudioMator.xcodeproj"),
            "-scheme",
            "AudioMator",
            "-configuration",
            "Debug",
            "-destination",
            "generic/platform=macOS",
            "-derivedDataPath",
            str(self.root / ".deriveddata-codex"),
            "CODE_SIGNING_ALLOWED=NO",
            "build",
        ]

    def assert_other_artifacts_preserved(self) -> None:
        self.assertTrue(
            (self.other_derived_data / "Other.app" / "Contents" / "Info.plist").is_file(),
            "alternate derived-data app bundle must survive the build helper",
        )
        self.assertTrue(
            (self.other_app / "Contents" / "Info.plist").is_file(),
            "standalone app bundle must survive the build helper",
        )

    # -- tests ---------------------------------------------------------------

    def test_fixture_executes_repository_helper_bytes(self) -> None:
        fixture_bytes = (self.root / "scripts" / "codex-build.sh").read_bytes()
        self.assertEqual(
            hashlib.sha256(fixture_bytes).hexdigest(),
            hashlib.sha256(HELPER_BYTES).hexdigest(),
        )

    def test_clean_checkout_skips_with_no_xcode_or_cleanup(self) -> None:
        result = self.run_helper()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CODEX_BUILD_SKIPPED", result.stdout)
        self.assertNotIn("CODEX_BUILD_COMPLETED", result.stdout)
        self.assertEqual(self.xcodebuild_calls(), [])
        self.assertEqual(self.prune_calls(), [])
        self.assertEqual(len(self.git_calls()), 3, self.git_calls())
        self.assertFalse(
            (self.root / ".deriveddata-codex").exists(),
            "skip path must not create build output directories",
        )
        self.assert_other_artifacts_preserved()

    def test_documentation_and_swiftpm_only_changes_skip(self) -> None:
        self.set_git_output(
            tracked=(
                b"Docs/README.md\0"
                b"Docs/Development/BUILD.md\0"
                b"Package.swift\0"
                b"Tests/AudioMatorCoreLogicTests/AudioMatorCoreLogicTests.swift\0"
                b"scripts/tests/test_test_evidence.py\0"
                b".github/workflows/ci.yml\0"
            ),
            untracked=b"Docs/Engineering/new-note.md\0",
        )

        result = self.run_helper()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CODEX_BUILD_SKIPPED", result.stdout)
        self.assertEqual(self.xcodebuild_calls(), [])
        self.assert_other_artifacts_preserved()

    def test_build_inputs_trigger_exactly_one_build_with_expected_arguments(self) -> None:
        cases: dict[str, tuple[bytes, bytes]] = {
            "app-icon-resource": (
                b"AudioMator/AppIcon.icon/Assets/app-icon.json\0",
                b"",
            ),
            "localizable-xcstrings-staged": (
                b"AudioMator/Localizable.xcstrings\0",
                b"",
            ),
            "localizable-xcstrings-deleted": (
                b"AudioMator/Localizable.xcstrings\0",
                b"",
            ),
            "package-resolved-lockfile": (
                b"AudioMator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved\0",
                b"",
            ),
            "test-audio-fixture": (
                b"AudioMatorTests/Fixtures/Audio/testAudioFile.flac\0",
                b"",
            ),
            "bundled-license": (
                b"AudioMator/Resources/Licenses/LICENSE-TagLib\0",
                b"",
            ),
            "configuration-input": (b"", b"Config/AudioMator.entitlements\0"),
            "untracked-resource": (b"", b"AudioMator/Resources/Images/New.imageset/Contents.json\0"),
            "helper-itself": (b"scripts/codex-build.sh\0", b""),
            "staged-and-untracked": (
                b"AudioMator/App/Main.swift\0",
                b"AudioMator/Resources/new.txt\0",
            ),
        }

        for name, (tracked, untracked) in cases.items():
            with self.subTest(case=name):
                self.call_log.write_text("")
                self.set_git_output(tracked=tracked, untracked=untracked)

                result = self.run_helper()

                self.assertEqual(result.returncode, 0, result.stderr)
                calls = self.xcodebuild_calls()
                self.assertEqual(len(calls), 1, calls)
                self.assertEqual(calls[0].split(" "), self.expected_xcodebuild_arguments())
                self.assertIn("CODEX_BUILD_COMPLETED", result.stdout)
                self.assertTrue(self.build_log_path().is_file())
                self.assertIn("** BUILD SUCCEEDED **", self.build_log_path().read_text())
                self.assertEqual(self.prune_calls(), [])
                self.assert_other_artifacts_preserved()

    def test_cross_root_rename_evaluates_both_sides(self) -> None:
        cases = {
            "deleted-from-app-tree": (b"AudioMator/Moved.swift\0Docs/Moved.swift\0", b""),
            "added-to-app-tree": (b"Docs/Moved.swift\0AudioMator/Moved.swift\0", b""),
        }

        for name, (tracked, untracked) in cases.items():
            with self.subTest(case=name):
                self.call_log.write_text("")
                self.set_git_output(tracked=tracked, untracked=untracked)

                result = self.run_helper()

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(self.xcodebuild_calls()), 1)

    def test_weird_path_names_are_preserved_in_discovery(self) -> None:
        tracked = (
            b"AudioMator/Resources/Weird/line\nbreak.txt\0"
            b"AudioMator/Resources/Weird/trailing-space .txt\0"
            b"AudioMator/Resources/Weird/leading-dash.txt\0"
        )
        self.set_git_output(tracked=tracked, untracked=b"")

        result = self.run_helper()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("AudioMator/Resources/Weird/line\nbreak.txt", result.stdout)
        self.assertIn("AudioMator/Resources/Weird/trailing-space .txt", result.stdout)
        self.assertIn("AudioMator/Resources/Weird/leading-dash.txt", result.stdout)
        self.assertEqual(len(self.xcodebuild_calls()), 1)

    def test_git_discovery_failures_fail_closed_without_xcode(self) -> None:
        cases = {
            "head-unavailable": {"head_exit": 128},
            "tracked-diff-failed": {"tracked_exit": 128},
            "untracked-listing-failed": {"untracked_exit": 128},
            "all-discovery-failed": {
                "head_exit": 128,
                "tracked_exit": 128,
                "untracked_exit": 128,
            },
        }

        for name, failures in cases.items():
            with self.subTest(case=name):
                self.call_log.write_text("")
                self.set_git_output(
                    tracked=b"AudioMator/App/Main.swift\0",
                    untracked=b"",
                    tracked_exit=failures.get("tracked_exit", 0),
                    untracked_exit=failures.get("untracked_exit", 0),
                    head_exit=failures.get("head_exit", 0),
                )

                result = self.run_helper()

                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.xcodebuild_calls(), [])
                self.assertNotIn("CODEX_BUILD_COMPLETED", result.stdout)
                self.assertIn("--force", result.stderr)
                self.assertIn("error:", result.stderr)
                self.assertFalse((self.root / ".deriveddata-codex").exists())
                self.assert_other_artifacts_preserved()

    def test_forced_build_ignores_git_discovery_failures(self) -> None:
        self.call_log.write_text("")
        self.set_git_output(
            tracked=b"",
            untracked=b"",
            tracked_exit=128,
            untracked_exit=128,
            head_exit=128,
        )

        result = self.run_helper(arguments=["--force"])

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git_calls(), [])
        self.assertEqual(len(self.xcodebuild_calls()), 1)
        self.assertIn("CODEX_BUILD_COMPLETED", result.stdout)
        self.assert_other_artifacts_preserved()

    def test_compiler_only_failure_preserves_exit_status_and_omits_marker(self) -> None:
        self.set_xcode_output(b"Synthetic.swift:1:1: error: unrelated compiler error\n", exit_code=65)

        result = self.run_helper(arguments=["--force"])

        self.assertEqual(result.returncode, 65)
        self.assertNotIn("CODEX_BUILD_COMPLETED", result.stdout)
        self.assertIn("Synthetic.swift:1:1: error", self.build_log_path().read_text())
        self.assertIn("Build failed", result.stderr)
        self.assertNotIn("Known Codex CLI limitation detected", result.stdout)

    def test_appicon_only_failure_exits_65_and_omits_marker(self) -> None:
        self.set_xcode_output(
            (
                "CompileAssetCatalogVariant\n"
                "Exception while running actool\n"
                "The file “AppIcon.icon” couldn’t be opened.\n"
            ).encode(),
            exit_code=65,
        )

        result = self.run_helper(arguments=["--force"])

        self.assertEqual(result.returncode, 65)
        self.assertNotIn("CODEX_BUILD_COMPLETED", result.stdout)
        self.assertIn("Known Codex CLI limitation detected", result.stdout)
        self.assertIn("not valid build evidence", result.stdout)

    def test_mixed_appicon_and_compiler_failure_exits_65_and_omits_marker(self) -> None:
        self.set_xcode_output(
            (
                "CompileAssetCatalogVariant\n"
                "Exception while running actool\n"
                "The file “AppIcon.icon” couldn’t be opened.\n"
                "Synthetic.swift:1:1: error: unrelated compiler error\n"
            ).encode(),
            exit_code=65,
        )

        result = self.run_helper(arguments=["--force"])

        self.assertEqual(result.returncode, 65)
        self.assertNotIn("CODEX_BUILD_COMPLETED", result.stdout)
        self.assertIn("Known Codex CLI limitation detected", result.stdout)
        self.assertIn("Build failed (xcodebuild exit 65)", result.stderr)

    def test_log_capture_failure_is_nonzero_and_not_evidence(self) -> None:
        self.set_xcode_output(b"** BUILD SUCCEEDED **\n", exit_code=0)

        result = self.run_helper(arguments=["--force"], extra_env={"TEE_FAIL": "1"})

        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("CODEX_BUILD_COMPLETED", result.stdout)
        self.assertIn("not valid build evidence", result.stderr)

    def test_log_capture_failure_during_failing_build_stays_nonzero(self) -> None:
        self.set_xcode_output(b"error: real compiler failure\n", exit_code=65)

        result = self.run_helper(arguments=["--force"], extra_env={"TEE_FAIL": "1"})

        self.assertEqual(result.returncode, 65)
        self.assertNotIn("CODEX_BUILD_COMPLETED", result.stdout)

    def test_unknown_option_exits_usage_without_running_tools(self) -> None:
        result = self.run_helper(arguments=["--bogus"])

        self.assertEqual(result.returncode, 2)
        self.assertIn("Usage: bash scripts/codex-build.sh [--force]", result.stderr)
        self.assertEqual(self.recorded_calls(), [])

    def test_unwritable_output_directory_fails_before_xcode(self) -> None:
        (self.root / ".deriveddata-codex").write_text("not a directory")

        result = self.run_helper(arguments=["--force"])

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unable to create the derived data directory", result.stderr)
        self.assertEqual(self.xcodebuild_calls(), [])
        self.assertNotIn("CODEX_BUILD_COMPLETED", result.stdout)

    def test_skip_and_build_never_prune_or_delete_unrelated_artifacts(self) -> None:
        skip_result = self.run_helper()
        self.assertEqual(skip_result.returncode, 0, skip_result.stderr)
        self.assertEqual(self.prune_calls(), [])
        self.assert_other_artifacts_preserved()

        self.call_log.write_text("")
        build_result = self.run_helper(arguments=["--force"])
        self.assertEqual(build_result.returncode, 0, build_result.stderr)
        self.assertEqual(self.prune_calls(), [])
        self.assert_other_artifacts_preserved()


if __name__ == "__main__":
    unittest.main()
