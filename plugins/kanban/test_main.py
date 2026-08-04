import importlib.util
import json
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location("tabame_kanban_plugin", Path(__file__).with_name("main.py"))
plugin = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(plugin)


class KanbanPluginTests(unittest.TestCase):
    def setUp(self):
        self.sent = []
        self.original_send = plugin.send
        plugin.send = self.sent.append
        plugin.STATE.update(
            {
                "loaded": True,
                "load_requested": True,
                "workspace": plugin.default_workspace(),
                "screen": "boards",
                "board_id": "starter-board",
                "card_id": None,
                "card_return": "board",
                "form_mode": None,
                "query": "",
                "board_pages": 1,
                "activity_pages": 1,
                "archive_pages": 1,
                "select_id": None,
            }
        )

    def tearDown(self):
        plugin.send = self.original_send

    def test_board_frame_uses_kanban_and_breadcrumbs(self):
        plugin.render_board(7)
        frame = self.sent[-1]
        self.assertEqual(frame["view"], "kanban")
        self.assertEqual(frame["rev"], 7)
        self.assertEqual(frame["page"]["breadcrumbs"][0]["id"], "kanban:boards")
        self.assertEqual(len(frame["kanban"]["columns"]), 5)
        self.assertTrue(all(item.get("column") for item in frame["items"]))

    def test_structured_filters_can_be_combined(self):
        board = plugin.find_board("starter-board")
        matches = [
            card["id"]
            for card in board["cards"]
            if plugin.card_matches(board, card, "priority:high tag:getting-started focused")
        ]
        self.assertEqual(matches, ["card-filter"])

    def test_activity_list_paginates_with_full_first_page(self):
        plugin.render_activity(3)
        frame = self.sent[-1]
        self.assertEqual(frame["view"], "list")
        self.assertEqual(frame["rev"], 3)
        self.assertEqual(len(frame["items"]), plugin.ACTIVITY_PAGE_SIZE)
        self.assertTrue(frame["hasMore"])

    def test_wip_limit_rejects_new_card_when_column_is_full(self):
        board = plugin.find_board("starter-board")
        review = plugin.find_column(board, "review")
        review["limit"] = 1
        candidate = {
            "id": "new-card",
            "title": "Overflow",
            "column": "review",
            "archived": False,
        }
        allowed, reason = plugin.can_enter_column(board, candidate, "review")
        self.assertFalse(allowed)
        self.assertIn("WIP limit", reason)

    def test_workspace_import_validation_is_non_destructive(self):
        self.assertIsNone(plugin.normalize_workspace({"version": 1}))
        normalized = plugin.normalize_workspace(plugin.default_workspace())
        self.assertEqual(normalized["version"], 1)
        self.assertEqual(normalized["boards"][0]["id"], "starter-board")

    def test_importing_an_existing_board_creates_a_copy(self):
        board = plugin.find_board("starter-board")
        plugin.handle_clipboard(
            {
                "requestId": "kanban-import-board",
                "text": json.dumps({"format": "tabame-kanban-board-v1", "board": board}),
            }
        )
        self.assertEqual(len(plugin.boards()), 2)
        self.assertNotEqual(plugin.boards()[0]["id"], "starter-board")
        self.assertTrue(plugin.boards()[0]["name"].endswith("copy"))


if __name__ == "__main__":
    unittest.main()
