#!/usr/bin/env python3
"""Tests de LEDGER. Stdlib uniquement, aucun serveur lancé.

  python3 test_ledger.py
"""

import json
import os
import random
import shutil
import sqlite3
import sys
import tempfile
import unittest
from datetime import datetime, timezone, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import collector
import tune

GAME_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "games", "american-dream"))


class LedgerCase(unittest.TestCase):
    def setUp(self):
        handle, self.path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        os.unlink(self.path)
        self.db = collector.connect(self.path)
        self.now = datetime.now(timezone.utc)
        # copie du jeu pour pouvoir écrire dans Economy.luau sans toucher au dépôt
        self.game = tempfile.mkdtemp()
        target = os.path.join(self.game, "src", "shared", "Config")
        os.makedirs(target)
        shutil.copy(os.path.join(GAME_DIR, "src", "shared", "Config", "Economy.luau"), target)

    def tearDown(self):
        self.db.close()
        for path in (self.path, self.path + "-wal", self.path + "-shm"):
            if os.path.exists(path):
                os.unlink(path)
        shutil.rmtree(self.game, ignore_errors=True)

    def emit(self, user_id: int, event: str, days_ago: float = 0, value: float = 1, layout: int = 1, **payload):
        ts = int((self.now - timedelta(days=days_ago)).timestamp())
        record = {"event": event, "userId": user_id, "layout": layout, "value": value, "t": ts,
                  "placeId": 1, "jobId": "test"}
        record.update(payload)
        collector.store_events(self.db, [record])

    def population(self, players: int, reach_step: int, days_ago: float = 1, layout: int = 1, seconds: int = 600, start_id: int = 1000):
        for index in range(players):
            user = start_id + index
            for step in range(1, reach_step + 1):
                self.emit(user, "onboarding", days_ago, layout=layout, step=step)
            self.emit(user, "session_end", days_ago, value=seconds, layout=layout)


class TestCollector(LedgerCase):
    def test_stores_and_ignores_nameless_events(self):
        stored = collector.store_events(self.db, [
            {"event": "session_end", "userId": 1, "value": 300, "t": int(self.now.timestamp())},
            {"userId": 2, "value": 1},  # sans nom : ignoré
        ])
        self.assertEqual(stored, 1)

    def test_rollup_builds_player_days(self):
        self.emit(1, "session_end", days_ago=0, value=420)
        self.emit(1, "act", days_ago=0, value=3)
        self.emit(1, "devproduct_pack_small", days_ago=0, value=25)
        collector.rollup(self.db)
        row = self.db.execute("SELECT * FROM player_days WHERE user_id = 1").fetchone()
        self.assertEqual(row["seconds"], 420)
        self.assertEqual(row["max_act"], 3)
        self.assertEqual(row["purchases"], 1)
        self.assertEqual(row["robux"], 25)

    def test_retention_d1_counts_returning_players(self):
        for user in range(1, 11):
            self.emit(user, "session_end", days_ago=2, value=300)
        for user in range(1, 4):  # 3 sur 10 reviennent le lendemain
            self.emit(user, "session_end", days_ago=1, value=300)
        collector.rollup(self.db)
        day = (self.now - timedelta(days=2)).strftime("%Y-%m-%d")
        row = self.db.execute("SELECT retention_d1 FROM daily_metrics WHERE day = ?", (day,)).fetchone()
        self.assertAlmostEqual(row["retention_d1"], 0.3, places=3)

    def test_funnel_counts_each_player_once_per_step(self):
        self.emit(1, "onboarding", step=1)
        self.emit(1, "onboarding", step=1)  # doublon
        self.emit(2, "onboarding", step=1)
        collector.rollup(self.db)
        row = self.db.execute("SELECT players FROM funnel_daily WHERE step = 1").fetchone()
        self.assertEqual(row["players"], 2)

    def test_report_is_readable_when_empty(self):
        self.assertIn("aucune métrique", collector.report(self.db, 7))


class TestTuning(LedgerCase):
    def test_refuses_to_decide_on_too_few_players(self):
        self.population(players=5, reach_step=3)
        collector.rollup(self.db)
        proposal = tune.propose(self.db, self.game, days=7)
        self.assertFalse(proposal["actionable"])
        self.assertIn("trop peu", proposal["diagnosis"])

    def test_detects_funnel_drop_and_lowers_the_right_cost(self):
        """60 joueurs arrivent à l'étape 3, 12 seulement à l'étape 4 : le premier achat est un mur."""
        self.population(players=60, reach_step=3)
        self.population(players=12, reach_step=6, start_id=5000)
        collector.rollup(self.db)
        proposal = tune.propose(self.db, self.game, days=7)
        self.assertTrue(proposal["actionable"])
        self.assertIn("first_purchase", proposal["diagnosis"] + json.dumps(proposal["evidence"]))
        knob = "Economy.Tiers[1].extraDropperCosts[1]"
        self.assertIn(knob, proposal["changes"])
        change = proposal["changes"][knob]
        self.assertLess(change["after"], change["before"])

    def test_never_cuts_a_cost_by_more_than_the_ceiling(self):
        self.population(players=100, reach_step=3)
        self.population(players=1, reach_step=8, start_id=7000)  # décrochage extrême
        collector.rollup(self.db)
        proposal = tune.propose(self.db, self.game, days=7)
        for knob, change in proposal["changes"].items():
            if "dropInterval" in knob:
                continue
            ratio = change["after"] / change["before"]
            self.assertGreaterEqual(ratio, 1 - tune.MAX_COST_CUT - 0.01, knob)

    def test_short_sessions_speed_up_the_first_loop(self):
        self.population(players=80, reach_step=6, seconds=120)  # 2 minutes
        collector.rollup(self.db)
        proposal = tune.propose(self.db, self.game, days=7)
        self.assertIn("Economy.Tiers[1].dropInterval", proposal["changes"])
        change = proposal["changes"]["Economy.Tiers[1].dropInterval"]
        self.assertLess(change["after"], change["before"])
        self.assertGreaterEqual(change["after"], 0.5, "la cadence ne doit jamais descendre sous 0,5 s")

    def test_low_retention_is_reported_with_the_advertising_warning(self):
        for user in range(1, 81):
            self.emit(user, "session_end", days_ago=2, value=600)
            self.emit(user, "onboarding", days_ago=2, step=1)
        self.emit(1, "session_end", days_ago=1, value=600)  # 1 sur 80 revient
        collector.rollup(self.db)
        proposal = tune.propose(self.db, self.game, days=7)
        self.assertIn("publicité", proposal["diagnosis"])

    def test_picks_the_winning_layout_when_the_gap_is_real(self):
        self.population(players=40, reach_step=6, layout=1, seconds=300, start_id=1000)
        self.population(players=40, reach_step=6, layout=2, seconds=900, start_id=2000)
        collector.rollup(self.db)
        winner = tune.layout_winner(self.db, (self.now - timedelta(days=7)).strftime("%Y-%m-%d"))
        self.assertIsNotNone(winner)
        self.assertEqual(winner["winner"], 2)
        self.assertGreater(winner["lift"], 0.5)

    def test_ignores_a_layout_gap_that_is_probably_noise(self):
        self.population(players=40, reach_step=6, layout=1, seconds=600, start_id=1000)
        self.population(players=40, reach_step=6, layout=2, seconds=630, start_id=2000)  # +5 %
        collector.rollup(self.db)
        self.assertIsNone(tune.layout_winner(self.db, (self.now - timedelta(days=7)).strftime("%Y-%m-%d")))

    def test_reads_current_values_from_the_real_config(self):
        source = tune.read_config(self.game)
        self.assertEqual(tune.current_value(source, "Economy.Tiers[2].unlockCost"), 500.0)
        self.assertEqual(tune.current_value(source, "Economy.Tiers[5].unlockCost"), 2500000.0)
        self.assertEqual(tune.current_value(source, "Economy.Tiers[1].dropInterval"), 2.0)
        self.assertEqual(tune.current_value(source, "Economy.Tiers[1].extraDropperCosts[1]"), 8.0)

    def test_apply_rewrites_only_the_targeted_tier(self):
        self.population(players=60, reach_step=5)
        self.population(players=10, reach_step=8, start_id=5000)
        collector.rollup(self.db)
        proposal = tune.propose(self.db, self.game, days=7)
        proposal_id = tune.save(self.db, proposal, 7)
        applied = tune.apply_proposal(self.db, proposal_id, self.game)
        self.assertTrue(applied)
        source = tune.read_config(self.game)
        for knob, change in proposal["changes"].items():
            self.assertEqual(tune.current_value(source, knob), float(change["after"]), knob)
        # les autres paliers n'ont pas bougé
        untouched = tune.current_value(source, "Economy.Tiers[5].unlockCost")
        self.assertEqual(untouched, 2500000.0)

    def test_apply_refuses_to_run_twice(self):
        self.population(players=60, reach_step=5)
        self.population(players=10, reach_step=8, start_id=5000)
        collector.rollup(self.db)
        proposal_id = tune.save(self.db, tune.propose(self.db, self.game, days=7), 7)
        tune.apply_proposal(self.db, proposal_id, self.game)
        with self.assertRaises(SystemExit):
            tune.apply_proposal(self.db, proposal_id, self.game)

    def test_healthy_game_gets_no_changes(self):
        random.seed(2)
        for user in range(1, 121):
            for step in range(1, 9):
                self.emit(user, "onboarding", days_ago=2, step=step)
            self.emit(user, "session_end", days_ago=2, value=900)
            if user <= 60:  # 50 % de rétention
                self.emit(user, "session_end", days_ago=1, value=900)
        collector.rollup(self.db)
        proposal = tune.propose(self.db, self.game, days=7)
        self.assertEqual(proposal["changes"], {})
        self.assertIn("aucun signal d'alerte", proposal["diagnosis"])


if __name__ == "__main__":
    unittest.main(verbosity=1)
