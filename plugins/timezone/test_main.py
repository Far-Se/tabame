import importlib.util
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path


SPEC = importlib.util.spec_from_file_location("tabame_timezone_plugin", Path(__file__).with_name("main.py"))
plugin = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(plugin)


class TimezonePluginTests(unittest.TestCase):
    def test_catalog_expands_default_world_regions(self):
        self.assertGreaterEqual(len(plugin.TIMEZONE_CATALOG), 100)
        self.assertGreaterEqual(len(plugin.CATALOG_SPECS), 100)
        self.assertGreater(len(plugin.WORLD), 10)

    def test_catalog_supports_city_and_multiword_region_aliases(self):
        cairo_tz, cairo_name, _ = plugin.resolve_token("Cairo", date(2026, 1, 15))
        cairo_time = datetime(2026, 1, 15, tzinfo=cairo_tz)
        self.assertEqual(cairo_name, "Cairo")
        self.assertEqual(cairo_time.utcoffset(), timedelta(hours=2))

        base, source_name, _, _, _ = plugin.parse_query("3 PM Central Asia Standard Time")
        self.assertEqual(source_name, "Nur-Sultan (Astana)")
        self.assertEqual(base.utcoffset(), timedelta(hours=6))

    def test_catalog_supports_iana_aliases_with_fixed_offset_fallback(self):
        zone, _, _ = plugin.resolve_token("America/Sao_Paulo", date(2026, 1, 15))
        self.assertEqual(datetime(2026, 1, 15, tzinfo=zone).utcoffset(), timedelta(hours=-3))

    def test_zone_only_query_converts_current_local_time_to_requested_zone(self):
        base, source_name, source_spec, destination, has_seconds = plugin.parse_query("Los Angeles")
        self.assertEqual(source_name, "Local")
        self.assertIsNone(source_spec)
        self.assertEqual(destination[1], "Pacific Time")
        self.assertFalse(has_seconds)
        self.assertEqual(base.tzinfo, plugin.LOCAL_TZ)

        sent = []
        original_send = plugin.send
        plugin.send = sent.append
        try:
            plugin.render(5, "Los Angeles")
        finally:
            plugin.send = original_send

        frame = sent[-1]
        self.assertEqual(frame["rev"], 5)
        self.assertIn("Pacific Time", frame["items"][0]["subtitle"])
        self.assertIn("(Local)", frame["items"][0]["preview"]["markdown"])

    def test_render_includes_catalog_regions(self):
        sent = []
        original_send = plugin.send
        plugin.send = sent.append
        try:
            plugin.render(4, "3 PM")
        finally:
            plugin.send = original_send

        frame = sent[-1]
        self.assertEqual(frame["view"], "list")
        self.assertEqual(frame["rev"], 4)
        self.assertGreaterEqual(len(frame["items"]), 100)
        self.assertTrue(any("Cairo" in item["subtitle"] for item in frame["items"]))


if __name__ == "__main__":
    unittest.main()
