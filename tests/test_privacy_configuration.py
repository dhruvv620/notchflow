import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENTITLEMENTS = ROOT / "DynamicIsland" / "DynamicIsland.entitlements"
INFO_PLIST = ROOT / "DynamicIsland" / "Info.plist"
PROJECT = ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj"
BUILD_SCRIPT = ROOT / "Build.command"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "notchflow-ci.yml"
MEDIA_KEY_INTERCEPTOR = ROOT / "DynamicIsland" / "managers" / "MediaKeyInterceptor.swift"
SYSTEM_CHANGES_OBSERVER = ROOT / "DynamicIsland" / "managers" / "SystemChangesObserver.swift"
SYSTEM_HUD_MANAGER = ROOT / "DynamicIsland" / "managers" / "SystemHUDManager.swift"


class PrivacyConfigurationTests(unittest.TestCase):
    def test_cuely_microphone_and_speech_permissions_are_declared(self):
        info = plistlib.loads(INFO_PLIST.read_bytes())
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertTrue(entitlements.get("com.apple.security.device.audio-input"))
        # Removed in 001435b: the restricted speech-recognition entitlement
        # cannot be signed ad hoc, and the usage description below suffices.
        self.assertIsNone(entitlements.get("com.apple.developer.speech-recognition"))
        project = PROJECT.read_text()
        self.assertNotIn("ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = NO;", project)
        self.assertEqual(project.count("ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES;"), 2)
        for key in (
            "NSMicrophoneUsageDescription",
            "NSSpeechRecognitionUsageDescription",
        ):
            usage_description = info.get(key)
            self.assertIsInstance(usage_description, str)
            self.assertIn("NotchFlow", usage_description)
            self.assertIn("Cuely", usage_description)

    def test_camera_capture_is_explicitly_entitled(self):
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertTrue(entitlements.get("com.apple.security.device.camera"))

    def test_notes_sync_is_authorized_for_apple_events(self):
        project = PROJECT.read_text()
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertNotIn("AUTOMATION_APPLE_EVENTS = NO;", project)
        self.assertIn(
            "com.apple.Notes",
            entitlements["com.apple.security.temporary-exception.apple-events"],
        )

    def test_automation_usage_text_names_notes(self):
        project = PROJECT.read_text()

        self.assertEqual(
            2,
            project.count(
                'INFOPLIST_KEY_NSAppleEventsUsageDescription = "NotchFlow uses AppleScript to control Spotify, Apple Music and Notes, to send the replies you type in the notch through Messages, to read the address of your browser tab during a Pomodoro when the distraction meter is on, and to open Terminal or iTerm when you start an AI agent from the notch.";'
            ),
        )

    def test_contacts_access_is_entitled_and_explained(self):
        project = PROJECT.read_text()
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertTrue(entitlements.get("com.apple.security.personal-information.addressbook"))
        self.assertEqual(2, project.count("INFOPLIST_KEY_NSContactsUsageDescription ="))

    def test_full_access_reminder_api_has_matching_usage_text(self):
        project = PROJECT.read_text()

        self.assertEqual(
            2,
            project.count("INFOPLIST_KEY_NSRemindersFullAccessUsageDescription ="),
        )

    def test_signing_keeps_the_app_entitlements(self):
        # Build.command (also used by Release.command) signs with a copy of the
        # repository's entitlements, so camera, microphone, speech and
        # automation survive re-signing.
        script = BUILD_SCRIPT.read_text()
        self.assertIn('cp "$SOURCE_DIR/DynamicIsland/DynamicIsland.entitlements" "$LOCAL_ENTITLEMENTS"', script)
        self.assertIn('--options runtime --entitlements "$LOCAL_ENTITLEMENTS" "$BUILT_APP"', script)

    def test_ci_checks_the_privacy_configuration(self):
        workflow = CI_WORKFLOW.read_text()

        self.assertIn("python3 -m unittest tests.test_privacy_configuration", workflow)

    def test_media_key_startup_never_prompts_for_accessibility(self):
        source = MEDIA_KEY_INTERCEPTOR.read_text()

        self.assertNotIn("AXIsProcessTrustedWithOptions", source)
        self.assertNotIn("kAXTrustedCheckOptionPrompt", source)
        self.assertIn("AXIsProcessTrusted()", source)

    def test_native_hud_is_suppressed_only_after_interception_is_ready(self):
        observer_source = SYSTEM_CHANGES_OBSERVER.read_text()
        manager_source = SYSTEM_HUD_MANAGER.read_text()

        self.assertIn(
            "func startObserving(volumeEnabled: Bool, brightnessEnabled: Bool, keyboardBacklightEnabled: Bool) -> Bool",
            observer_source,
        )
        readiness_check = manager_source.index("guard interceptionReady else")
        suppression = manager_source.index("suppressNativeSystemHUDIfNeeded()", readiness_check)
        self.assertLess(readiness_check, suppression)
        self.assertIn("restoreNativeSystemHUDIfNeeded()", manager_source[readiness_check:suppression])

    def test_failed_interception_retries_after_app_activation(self):
        source = SYSTEM_HUD_MANAGER.read_text()

        self.assertIn("NSApplication.didBecomeActiveNotification", source)
        self.assertIn("self.changesObserver == nil", source)
        self.assertIn("AccessibilityPermissionStore.shared.$isAuthorized", source)


if __name__ == "__main__":
    unittest.main()
