#!/usr/bin/env python3
"""Test du générateur FORGE : un brief doit produire un jeu qui compile, se lint et se teste.

Ne lance pas les outils Luau (ils ne sont pas toujours installés en CI Python) : vérifie la
structure, la cohérence du contenu généré, et que le kit partagé est complet, c'est-à-dire que
chaque `require` d'un fichier copié pointe vers un fichier qui existe.

  python3 test_generator.py
"""

import json
import os
import re
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import new_game

BRIEF = {
    "schemaVersion": 1,
    "concept": "lemon-sell",
    "slug": "lemon-sell",
    "verdict": {"call": "y aller", "why": "accélération réelle, marché encore ouvert"},
    "signal": {"score": 0.42, "ccu": 7000, "velocityPerHour": 0.18, "acceleration": 0.09,
               "saturation": 0.25, "clones": 3, "ageDays": 12.0, "sponsoredShare": 0.0,
               "externalSignal": 0.5, "windowDays": [10, 25]},
    "production": {"genre": "Simulation", "ease": 0.95, "coreLoop": "récolter, revendre, améliorer",
                   "cycleSeconds": 90, "targetSessionMinutes": 20,
                   "requiredSystems": ["monnaie unique", "5 paliers", "sauvegarde DataStore"],
                   "workingTitle": "Lemon Sell",
                   "assetBudget": {"heroMeshes": 6, "propMeshes": 40, "images": 12, "audioTracks": 6},
                   "targetDays": 14},
    "reference": {"playFirst": [{"name": "Sell Lemons", "placeId": 1, "ccu": 7000, "url": "https://www.roblox.com/games/1"}],
                  "note": "jouer avant de produire"},
    "monetisation": {"strategy": "conversion par la valeur", "allowed": ["cosmétiques"],
                     "forbidden": ["loot box", "faux compte à rebours", "fausse rareté"],
                     "policyService": "PolicyService obligatoire"},
    "successCriteria": {"retentionD1": 0.10, "sessionMinutes": 4, "decisionAtDays": 21, "note": ""},
}


class TestGenerator(unittest.TestCase):
    def setUp(self):
        self.out = tempfile.mkdtemp()
        handle, self.brief_path = tempfile.mkstemp(suffix=".json")
        with os.fdopen(handle, "w", encoding="utf-8") as file:
            json.dump(BRIEF, file)
        self.game = new_game.build(self.brief_path, self.out, force=True)

    def tearDown(self):
        shutil.rmtree(self.out, ignore_errors=True)
        os.unlink(self.brief_path)

    def read(self, relative: str) -> str:
        with open(os.path.join(self.game, relative), encoding="utf-8") as handle:
            return handle.read()

    def test_produces_a_complete_rojo_project(self):
        for relative in ("default.project.json", ".luaurc", "selene.toml", "rokit.toml",
                         "src/server/init.server.luau", "src/client/init.client.luau",
                         "src/shared/Config/Economy.luau", "src/shared/Strings.luau",
                         "tests/run.luau", "assets/manifest.json", "README.md", "brief.json"):
            self.assertTrue(os.path.exists(os.path.join(self.game, relative)), relative)

    def test_shared_kit_has_no_missing_dependency(self):
        """Chaque require d'un fichier copié doit pointer vers un fichier réellement présent.

        C'est le test qui empêche de livrer un squelette qui ne compile pas.
        """
        missing = []
        for root, _, names in os.walk(os.path.join(self.game, "src")):
            for name in names:
                if not name.endswith(".luau"):
                    continue
                path = os.path.join(root, name)
                if "Vendor" in path:
                    continue
                source = open(path, encoding="utf-8").read()
                for match in re.finditer(r"require\((?:ReplicatedStorage\.)?Shared\.([\w.]+)\)", source):
                    target = os.path.join(self.game, "src", "shared", *match.group(1).split(".")) + ".luau"
                    if not os.path.exists(target):
                        missing.append(f"{os.path.relpath(path, self.game)} -> Shared.{match.group(1)}")
        self.assertEqual(missing, [], "dépendances manquantes dans le kit partagé")

    def test_economy_shape_follows_the_brief(self):
        source = self.read("src/shared/Config/Economy.luau")
        self.assertIn("--!strict", source)
        self.assertIn("lemon-sell", source)
        self.assertIn("TARGET_SESSION_MINUTES = 20", source)
        costs = [int(value) for value in re.findall(r"unlockCost = (\d+)", source)]
        self.assertGreaterEqual(len(costs), 3)
        self.assertEqual(costs[0], 0, "le premier palier doit être gratuit")
        for previous, current in zip(costs[1:], costs[2:]):
            self.assertGreater(current, previous, "les coûts doivent croître")

    def test_strings_are_bilingual(self):
        source = self.read("src/shared/Strings.luau")
        entries = re.findall(r'fr = "([^"]*)", en = "([^"]*)"', source)
        self.assertGreater(len(entries), 5)
        for french, english in entries:
            self.assertTrue(french.strip(), "traduction FR vide")
            self.assertTrue(english.strip(), "traduction EN vide")

    def test_readme_carries_the_forbidden_list_and_the_thresholds(self):
        readme = self.read("README.md")
        self.assertIn("loot box", readme)
        self.assertIn("faux compte à rebours", readme)
        self.assertIn("10%", readme.replace(" ", ""))
        self.assertIn("y aller", readme)

    def test_every_luau_file_is_strict(self):
        for root, _, names in os.walk(os.path.join(self.game, "src")):
            for name in names:
                if not name.endswith(".luau") or "Vendor" in root:
                    continue
                first = open(os.path.join(root, name), encoding="utf-8").readline()
                self.assertTrue(first.startswith("--!strict"), os.path.join(root, name))

    def test_project_file_is_valid_json_and_names_the_game(self):
        project = json.loads(self.read("default.project.json"))
        self.assertEqual(project["name"], "LemonSell")
        self.assertEqual(project["tree"]["$className"], "DataModel")
        self.assertTrue(project["tree"]["Workspace"]["$properties"]["StreamingEnabled"])

    def test_refuses_to_overwrite_without_force(self):
        with self.assertRaises(SystemExit):
            new_game.build(self.brief_path, self.out, force=False)

    def test_warns_when_oracle_says_skip(self):
        skip_brief = json.loads(json.dumps(BRIEF))
        skip_brief["verdict"] = {"call": "passer", "why": "marché saturé"}
        skip_brief["slug"] = "skip-me"
        handle, path = tempfile.mkstemp(suffix=".json")
        with os.fdopen(handle, "w", encoding="utf-8") as file:
            json.dump(skip_brief, file)
        try:
            game = new_game.build(path, self.out, force=True)
            self.assertIn("passer", open(os.path.join(game, "README.md"), encoding="utf-8").read())
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main(verbosity=1)
