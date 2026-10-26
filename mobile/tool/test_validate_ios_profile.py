from datetime import datetime, timedelta, timezone
import unittest

from validate_ios_profile import ProfileValidationError, validate_profile


class ValidateIOSProfileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.now = datetime(2026, 10, 14, tzinfo=timezone.utc)
        self.profile = {
            "ExpirationDate": self.now + timedelta(days=30),
            "TeamIdentifier": ["ABCDE12345"],
            "ApplicationIdentifierPrefix": ["ABCDE12345"],
            "Entitlements": {
                "application-identifier": "ABCDE12345.kg.com.stroy.app",
                "get-task-allow": False,
            },
            "UUID": "12345678-1234-5678-9abc-def012345678",
        }

    def test_accepts_matching_app_store_profile(self) -> None:
        self.assertEqual(
            validate_profile(
                self.profile,
                team_id="ABCDE12345",
                bundle_id="kg.com.stroy.app",
                now=self.now,
            ),
            self.profile["UUID"],
        )

    def test_accepts_legacy_app_identifier_prefix(self) -> None:
        self.profile["ApplicationIdentifierPrefix"] = ["OLDPREFIX1"]
        self.profile["Entitlements"]["application-identifier"] = (
            "OLDPREFIX1.kg.com.stroy.app"
        )
        self.assertEqual(
            validate_profile(
                self.profile,
                team_id="ABCDE12345",
                bundle_id="kg.com.stroy.app",
                now=self.now,
            ),
            self.profile["UUID"],
        )

    def test_rejects_expired_profile(self) -> None:
        self.profile["ExpirationDate"] = self.now
        with self.assertRaisesRegex(ProfileValidationError, "expired"):
            validate_profile(
                self.profile,
                team_id="ABCDE12345",
                bundle_id="kg.com.stroy.app",
                now=self.now,
            )

    def test_rejects_team_or_bundle_mismatch(self) -> None:
        with self.assertRaisesRegex(ProfileValidationError, "different Apple team"):
            validate_profile(
                self.profile,
                team_id="FGHIJ67890",
                bundle_id="kg.com.stroy.app",
                now=self.now,
            )
        with self.assertRaisesRegex(ProfileValidationError, "bundle ID"):
            validate_profile(
                self.profile,
                team_id="ABCDE12345",
                bundle_id="kg.com.other.app",
                now=self.now,
            )

    def test_rejects_non_app_store_profiles(self) -> None:
        self.profile["Entitlements"]["get-task-allow"] = True
        with self.assertRaisesRegex(ProfileValidationError, "App Store distribution"):
            validate_profile(
                self.profile,
                team_id="ABCDE12345",
                bundle_id="kg.com.stroy.app",
                now=self.now,
            )

        self.profile["Entitlements"]["get-task-allow"] = False
        self.profile["ProvisionedDevices"] = ["device-udid"]
        with self.assertRaisesRegex(ProfileValidationError, "ad hoc"):
            validate_profile(
                self.profile,
                team_id="ABCDE12345",
                bundle_id="kg.com.stroy.app",
                now=self.now,
            )


if __name__ == "__main__":
    unittest.main()
