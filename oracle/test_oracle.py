#!/usr/bin/env python3
"""Tests d'ORACLE. Stdlib uniquement (unittest), aucun appel réseau.

  python3 test_oracle.py
"""

import json
import os
import sqlite3
import sys
import tempfile
import unittest
from datetime import datetime, timezone, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import brief
import concepts
import features
import ingest
import predictions


def iso(moment: datetime) -> str:
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


class TestConcepts(unittest.TestCase):
    def test_plural_and_decoration_collapse(self):
        """Sans ça, ORACLE compte deux tendances là où il n'y en a qu'une."""
        for variant in ("Steal An Egg", "🥚 Steal Eggs!", "Steal an Egg Simulator [UPDATE]", "STEAL EGGS (CODES)"):
            self.assertEqual(concepts.concept_key(variant), "egg-steal", variant)

    def test_word_order_does_not_matter(self):
        self.assertEqual(concepts.concept_key("Garden Grow"), concepts.concept_key("Grow a Garden"))

    def test_stemming_leaves_real_words_alone(self):
        for word in ("water", "monster", "master", "business", "class", "boss"):
            self.assertEqual(concepts.stem(word), word, word)

    def test_stemming_handles_plurals(self):
        self.assertEqual(concepts.stem("eggs"), "egg")
        self.assertEqual(concepts.stem("babies"), "baby")
        self.assertEqual(concepts.stem("boxes"), "box")
        self.assertEqual(concepts.stem("running"), "run")

    def test_similarity_and_clustering(self):
        self.assertGreater(concepts.similarity("Pet Simulator", "Pet Simulator 99"), 0.5)
        self.assertLess(concepts.similarity("Pet Simulator", "Murder Mystery"), 0.2)
        mapping = concepts.cluster(["Grow a Garden", "Growing Gardens 🌱", "Murder Mystery 2"])
        self.assertEqual(mapping["Grow a Garden"], mapping["Growing Gardens 🌱"])
        self.assertNotEqual(mapping["Grow a Garden"], mapping["Murder Mystery 2"])

    def test_empty_and_emoji_only_names_do_not_crash(self):
        self.assertTrue(concepts.concept_key("🎮🎮🎮"))
        self.assertTrue(concepts.concept_key(""))


class OracleDatabaseCase(unittest.TestCase):
    def setUp(self):
        handle, self.path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        os.unlink(self.path)
        self.db = ingest.connect(self.path)
        self.now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)

    def tearDown(self):
        self.db.close()
        if os.path.exists(self.path):
            os.unlink(self.path)

    def add_game(self, universe_id: int, name: str, genre: str = "Simulation", age_days: int = 10, concept: str | None = None):
        created = iso(self.now - timedelta(days=age_days))
        self.db.execute(
            """INSERT INTO experiences (universe_id, root_place_id, name, genre_l1, created_at, concept_key, first_seen, last_seen)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (universe_id, universe_id * 10, name, genre, created, concept or concepts.concept_key(name), iso(self.now), iso(self.now)),
        )

    def add_series(self, universe_id: int, values: list[tuple[float, int]]):
        """values = [(heures avant maintenant, joueurs)]"""
        for hours_ago, playing in values:
            self.db.execute(
                "INSERT OR REPLACE INTO snapshots (universe_id, ts, playing, visits) VALUES (?, ?, ?, ?)",
                (universe_id, iso(self.now - timedelta(hours=hours_ago)), playing, 100000),
            )
        self.db.commit()


class TestScoring(OracleDatabaseCase):
    def test_small_games_are_filtered_out(self):
        """Le bug du premier test : un jeu à 3 joueurs qui passe à 9 affichait +200 % et sortait premier."""
        self.add_game(1, "Medal Hub")
        self.add_series(1, [(8, 3), (4, 5), (0, 9)])
        self.assertEqual(features.rank(self.db, 10), [])

    def test_growth_needs_two_points_and_a_real_gap(self):
        self.assertIsNone(features.growth([]))
        self.assertIsNone(features.growth([(self.now, 5000)]))
        points = [(self.now - timedelta(minutes=5), 1000), (self.now, 1200)]
        self.assertIsNone(features.growth(points), "moins de 30 min : pas de signal")

    def test_growth_is_relative_not_absolute(self):
        """Doubler de 1 000 à 2 000 doit valoir autant que de 10 000 à 20 000."""
        small = features.growth([(self.now - timedelta(hours=4), 1000), (self.now, 2000)])
        large = features.growth([(self.now - timedelta(hours=4), 10000), (self.now, 20000)])
        self.assertAlmostEqual(small, large, places=6)

    def test_accelerating_game_beats_flat_game(self):
        self.add_game(1, "Rocket Climb")
        self.add_series(1, [(12, 1000), (8, 1100), (4, 1400), (0, 2600)])
        self.add_game(2, "Steady Walk")
        self.add_series(2, [(12, 1000), (8, 1100), (4, 1200), (0, 1300)])
        ranked = features.rank(self.db, 10)
        self.assertEqual(ranked[0]["name"], "Rocket Climb")
        self.assertGreater(ranked[0]["acceleration"], ranked[1]["acceleration"])

    def test_saturation_defaults_to_unknown_not_free(self):
        """Sans mesure, on ne doit pas annoncer qu'un marché est libre."""
        self.add_game(1, "Fresh Thing")
        self.add_series(1, [(6, 1000), (0, 2000)])
        level, clones = features.saturation(self.db, "fresh-thing")
        self.assertGreaterEqual(level, 0.5)
        self.assertEqual(clones, 1)

    def test_measured_saturation_wins_over_database_count(self):
        self.add_game(1, "Crowded Concept")
        self.add_series(1, [(6, 1000), (0, 2000)])
        self.db.execute(
            """INSERT INTO external_signals (source, term, ts, value, metadata)
               VALUES ('search', ?, ?, ?, ?)""",
            (concepts.concept_key("Crowded Concept"), iso(self.now), 24.0, json.dumps({"concentration": 0.95})),
        )
        self.db.commit()
        level, clones = features.saturation(self.db, concepts.concept_key("Crowded Concept"))
        self.assertEqual(clones, 24)
        self.assertEqual(level, 1.0)

    def test_saturated_concept_scores_below_open_one(self):
        for index, (name, clones) in enumerate([("Open Market", 1.0), ("Closed Market", 30.0)], start=1):
            self.add_game(index, name)
            self.add_series(index, [(12, 1000), (8, 1200), (4, 1600), (0, 2400)])
            self.db.execute(
                "INSERT INTO external_signals (source, term, ts, value, metadata) VALUES ('search', ?, ?, ?, ?)",
                (concepts.concept_key(name), iso(self.now), clones, json.dumps({"concentration": 0.5})),
            )
        self.db.commit()
        ranked = {item["name"]: item["score"] for item in features.rank(self.db, 10)}
        self.assertGreater(ranked["Open Market"], ranked["Closed Market"])

    def test_age_window_penalises_old_trends(self):
        self.assertEqual(features.age_factor(10), 1.0)
        self.assertEqual(features.age_factor(100), 0.0)
        self.assertLess(features.age_factor(1), 0.5, "deux jours de données ne prouvent rien")
        self.assertIsNone(features.age_days(None, self.now))
        self.assertAlmostEqual(features.age_days(iso(self.now - timedelta(days=5)), self.now), 5.0, places=1)

    def test_sponsored_games_are_discounted(self):
        for index, name in enumerate(["Organic", "Bought"], start=1):
            self.add_game(index, name)
            self.add_series(index, [(12, 1000), (8, 1200), (4, 1600), (0, 2400)])
        for rank_index in range(4):
            self.db.execute(
                "INSERT INTO sort_membership (universe_id, sort_id, device, rank, is_sponsored, ts) VALUES (2, 'top', 'computer', 1, 1, ?)",
                (iso(self.now - timedelta(hours=rank_index)),),
            )
        self.db.commit()
        ranked = {item["name"]: item["score"] for item in features.rank(self.db, 10)}
        self.assertGreater(ranked["Organic"], ranked["Bought"])

    def test_ease_by_genre_favours_what_an_ai_can_build(self):
        self.assertGreater(features.ease_for("Simulation"), features.ease_for("Shooter"))
        self.assertEqual(features.ease_for(None), features.DEFAULT_EASE)
        self.assertEqual(features.ease_for("Genre Inconnu"), features.DEFAULT_EASE)


class TestPredictions(OracleDatabaseCase):
    def test_outcome_is_logarithmic(self):
        """Loi de puissance : de 100 à 1 000 joueurs vaut autant que de 1 000 à 10 000."""
        for entry_id, ccu in enumerate([100, 1000, 10000], start=1):
            self.db.execute(
                """INSERT INTO predictions_log (id, concept_key, decided_at, predicted_score, decision)
                   VALUES (?, ?, ?, 0.5, 'shipped')""",
                (entry_id, f"c{entry_id}", iso(self.now)),
            )
            predictions.settle(self.db, entry_id, ccu, 0, "")
        scores = [row["outcome_score"] for row in self.db.execute("SELECT outcome_score FROM predictions_log ORDER BY id")]
        first_step = scores[1] - scores[0]
        second_step = scores[2] - scores[1]
        self.assertAlmostEqual(first_step, second_step, places=5)

    def test_fit_refuses_to_run_on_too_few_samples(self):
        result = predictions.fit(self.db, apply_weights=False)
        self.assertFalse(result["fitted"])
        self.assertEqual(result["needed"], predictions.MIN_SAMPLES_TO_FIT)

    def test_fit_recovers_hidden_weights(self):
        """La régression doit retrouver quels signaux comptent vraiment."""
        import random
        random.seed(11)
        truth = {"acceleration": 0.7, "velocity": 0.0, "unsaturation": 0.4, "ease": 0.0, "external": 0.0, "age_penalty": 0.2}
        for index in range(16):
            components = {key: random.random() for key in truth}
            outcome = sum(truth[key] * components[key] * (-1 if key == "age_penalty" else 1) for key in truth)
            outcome = max(0.0, min(1.0, outcome))
            self.db.execute(
                """INSERT INTO predictions_log (concept_key, decided_at, predicted_score, components, decision,
                                                settled_at, peak_ccu, outcome_score)
                   VALUES (?, ?, 0.4, ?, 'shipped', ?, 1000, ?)""",
                (f"t{index}", iso(self.now), json.dumps(components), iso(self.now), outcome),
            )
        self.db.commit()
        result = predictions.fit(self.db, apply_weights=True)
        self.assertTrue(result["fitted"])
        self.assertGreater(result["r_squared"], 0.9)
        weights = result["weights"]
        self.assertGreater(weights["acceleration"], weights["velocity"])
        self.assertGreater(weights["unsaturation"], weights["ease"])
        # les poids ajustés doivent être rechargés par features
        reloaded = features.load_weights(self.db)
        self.assertAlmostEqual(reloaded["acceleration"], weights["acceleration"], places=6)

    def test_weights_stay_positive(self):
        """Un signal ne doit jamais changer de sens par accident de descente de gradient."""
        import random
        random.seed(5)
        for index in range(12):
            components = {key: random.random() for key in features.DEFAULT_WEIGHTS}
            self.db.execute(
                """INSERT INTO predictions_log (concept_key, decided_at, predicted_score, components, decision,
                                                settled_at, peak_ccu, outcome_score)
                   VALUES (?, ?, 0.4, ?, 'skipped', ?, 100, 0.0)""",
                (f"z{index}", iso(self.now), json.dumps(components), iso(self.now)),
            )
        self.db.commit()
        result = predictions.fit(self.db, apply_weights=False)
        for key, value in result["weights"].items():
            self.assertGreaterEqual(value, 0.0, key)


class TestBrief(OracleDatabaseCase):
    def _candidate(self, **overrides):
        base = {"concept": "test-concept", "name": "Test", "score": 0.5, "ccu": 5000, "velocity": 0.2,
                "acceleration": 0.1, "saturation": 0.2, "clones": 2, "ease": 0.9, "external": 0.5,
                "age_days": 12.0, "sponsored": 0.0, "components": {}}
        base.update(overrides)
        return base

    def test_verdict_refuses_saturated_market(self):
        call, why = brief.verdict(self._candidate(saturation=0.95))
        self.assertEqual(call, "passer")
        self.assertIn("satur", why)

    def test_verdict_refuses_old_trend(self):
        self.assertEqual(brief.verdict(self._candidate(age_days=120))[0], "passer")

    def test_verdict_refuses_bought_visibility(self):
        self.assertEqual(brief.verdict(self._candidate(sponsored=0.9))[0], "passer")

    def test_verdict_waits_when_growth_slows(self):
        self.assertEqual(brief.verdict(self._candidate(acceleration=-0.1))[0], "attendre")

    def test_verdict_goes_when_window_is_open(self):
        self.assertEqual(brief.verdict(self._candidate(score=0.5, saturation=0.2))[0], "y aller")

    def test_brief_always_carries_the_forbidden_list(self):
        self.add_game(1, "Test Concept", concept="test-concept")
        self.add_series(1, [(6, 4000), (0, 5000)])
        built = brief.build(self.db, self._candidate())
        self.assertEqual(built["monetisation"]["strategy"], "conversion par la valeur")
        joined = " ".join(built["monetisation"]["forbidden"]).lower()
        for banned in ("loot box", "compte à rebours", "rareté", "progression"):
            self.assertIn(banned, joined)
        self.assertIn("PolicyService", built["monetisation"]["policyService"])

    def test_brief_sets_measurable_success_criteria(self):
        self.add_game(1, "Test Concept", concept="test-concept")
        self.add_series(1, [(6, 4000), (0, 5000)])
        built = brief.build(self.db, self._candidate())
        self.assertEqual(built["successCriteria"]["retentionD1"], 0.10)
        self.assertGreater(built["successCriteria"]["sessionMinutes"], 0)
        self.assertIn("slug", built)
        self.assertTrue(built["production"]["requiredSystems"])

    def test_prompt_mentions_constraints(self):
        self.add_game(1, "Test Concept", concept="test-concept")
        self.add_series(1, [(6, 4000), (0, 5000)])
        text = brief.prompt_for(brief.build(self.db, self._candidate()))
        self.assertIn("Serveur autoritatif", text)
        self.assertIn("mobile", text)
        self.assertIn("FR et EN", text)


class TestIngest(OracleDatabaseCase):
    def test_quarter_hour_bucketing(self):
        moment = datetime(2026, 9, 16, 14, 37, 22, tzinfo=timezone.utc)
        self.assertEqual(ingest.quarter_hour(moment), "2026-09-16T14:30:00Z")
        moment = datetime(2026, 9, 16, 14, 59, 59, tzinfo=timezone.utc)
        self.assertEqual(ingest.quarter_hour(moment), "2026-09-16T14:45:00Z")

    def test_upsert_is_idempotent_and_keeps_details(self):
        game = {"universeId": 7, "name": "Thing", "rootPlaceId": 70, "genreL1": "Simulation"}
        details = {"created": "2026-01-01T00:00:00.000Z", "visits": 5, "creator": {"id": 3, "name": "me", "type": "User"}}
        ingest.upsert_experience(self.db, 7, game, details, iso(self.now))
        ingest.upsert_experience(self.db, 7, game, None, iso(self.now))
        self.db.commit()
        rows = self.db.execute("SELECT * FROM experiences WHERE universe_id = 7").fetchall()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["created_at"], "2026-01-01T00:00:00.000Z", "un détail connu ne doit pas être écrasé par NULL")
        self.assertEqual(rows[0]["creator_name"], "me")

    def test_prune_removes_old_rows_only(self):
        self.add_game(1, "Old Game")
        self.add_series(1, [(24 * 60, 1000), (1, 2000)])
        removed = ingest.prune(self.db, days=45)
        self.assertEqual(removed, 1)
        remaining = self.db.execute("SELECT COUNT(*) AS n FROM snapshots").fetchone()["n"]
        self.assertEqual(remaining, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
