"""Exercise durable imports, picker generations and solar-cache boundaries."""

import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from test_helper import load_helper


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="appearance-storage-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.helper = load_helper()
        self.helper.OMARCHY_PATH = self.root / "system"
        self.helper.STOCK_THEMES = self.root / "system/themes"
        self.helper.USER_THEMES = self.root / "themes"
        self.helper.USER_BACKGROUNDS = self.root / "backgrounds"
        self.helper.BACKGROUND_PICKER_CACHE = self.root / "picker"
        self.helper.SOLAR_CACHE = self.root / "solar.json"
        (self.helper.USER_THEMES / "sample").mkdir(parents=True)

    def image(self, name, content=b"image-data"):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def test_import_is_idempotent_and_never_overwrites_a_collision(self):
        source = self.image("personal/wallpaper.png", b"new-image")
        collision = self.image("backgrounds/sample/wallpaper.png", b"existing-image")
        result, copied = self.helper.import_personal_wallpaper(source, "sample")
        self.assertTrue(copied)
        self.assertEqual(result.name, "wallpaper (2).png")
        self.assertEqual(result.read_bytes(), source.read_bytes())
        self.assertEqual(collision.read_bytes(), b"existing-image")
        same, copied_again = self.helper.import_personal_wallpaper(source, "sample")
        self.assertEqual(same, result)
        self.assertFalse(copied_again)
        self.assertEqual(source.read_bytes(), b"new-image")

    def test_picker_reuses_exact_generation_and_rejects_changed_source(self):
        source = self.image("personal/wallpaper.png")
        record = self.helper.wallpaper_record("sample", source, "user-background")
        stage, manifest = self.helper.stage_wallpaper_pool("theme", "sample", "dark", [record])
        original_inode = stage.stat().st_ino
        same, _ = self.helper.stage_wallpaper_pool("theme", "sample", "dark", [record])
        self.assertEqual(same.stat().st_ino, original_inode)
        selected = str(stage / manifest["items"][0]["stage"])
        self.assertEqual(self.helper.selected_picker_record(stage, manifest, selected)["path"], str(source))
        source.write_bytes(b"different-image-with-different-size")
        with self.assertRaisesRegex(self.helper.AppearanceError, "changed"):
            self.helper.selected_picker_record(stage, manifest, selected)
        _, updated = self.helper.stage_wallpaper_pool("theme", "sample", "dark", [record])
        self.assertNotEqual(updated, manifest)
        with self.assertRaisesRegex(self.helper.AppearanceError, "pool changed"):
            self.helper.selected_picker_record(stage, manifest, selected)

    def test_solar_cache_rejects_new_location_and_expired_event_window(self):
        cache = {"version": 1, "weatherFingerprint": "location-a", "fetchedAt": 100,
                 "events": [{"epoch": 50000, "event": "sunset"}]}
        self.assertIsNotNone(self.helper.cached_solar_schedule(cache, "location-a", 200, fresh_only=True))
        self.assertIsNone(self.helper.cached_solar_schedule(cache, "location-b", 200, fresh_only=False))
        self.assertIsNone(self.helper.cached_solar_schedule(cache, "location-a", 22000, fresh_only=True))
        self.assertIsNotNone(self.helper.cached_solar_schedule(cache, "location-a", 22000, fresh_only=False))
        self.assertIsNone(self.helper.cached_solar_schedule(cache, "location-a", 50000, fresh_only=False))

    def test_offline_solar_refresh_uses_future_events_and_keeps_the_cache(self):
        settings = {"name": "Test", "latitude": 10, "longitude": 20}
        cache = {"version": 1, "weatherFingerprint": self.helper.weather_fingerprint(settings),
                 "fetchedAt": 100, "events": [{"epoch": 50000, "event": "sunset"}]}
        self.helper.SOLAR_CACHE.write_text(json.dumps(cache))
        with patch.object(self.helper, "weather_location_settings", return_value=settings), \
             patch.object(self.helper.time, "time", return_value=22000), \
             patch.object(self.helper, "detect_location", side_effect=self.helper.AppearanceError("offline")):
            result = self.helper.solar_schedule()
        self.assertTrue(result["stale"])
        self.assertTrue(result["cached"])
        self.assertEqual(result["events"], cache["events"])
        self.assertEqual(json.loads(self.helper.SOLAR_CACHE.read_text()), cache)


if __name__ == "__main__":
    unittest.main()
