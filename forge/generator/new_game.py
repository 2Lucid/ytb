#!/usr/bin/env python3
"""FORGE : du brief au squelette de jeu jouable.

Prend un `brief.json` produit par ORACLE et écrit un projet Rojo complet, qui compile, se teste
et se déploie dès la première minute. Le code de gameplay reste à écrire — mais tout ce qui est
répétitif (structure, kit partagé, tests, CI, manifest) est posé.

Ce qui est copié depuis American Dream : le kit qui a déjà servi (utilitaires, sauvegarde,
garde des remotes, génération de monde, harnais de test). Ce qui est généré : la configuration
d'économie dérivée du genre, les chaînes, le manifest d'assets.

  python3 new_game.py --brief ../briefs/lemon-sell.brief.json
  python3 new_game.py --brief ../briefs/x.brief.json --out ../../games --force
"""

import argparse
import json
import os
import re
import shutil
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
TEMPLATE = os.path.join(REPO, "games", "american-dream")

# Ce qui est réutilisable tel quel d'un jeu à l'autre : c'est le capital de l'usine.
SHARED_KIT = [
    "src/shared/Util/Signal.luau",
    "src/shared/Util/PRNG.luau",
    "src/shared/Util/Format.luau",
    "src/shared/Util/RateLimiter.luau",
    "src/shared/Types.luau",
    "src/shared/Sim/SaveSchema.luau",
    "src/shared/Sim/Progression.luau",
    "src/shared/Config/Telemetry.luau",
    "src/shared/WorldGen/Palette.luau",
    "src/shared/AssetRegistry.luau",
    "src/shared/AnimationRegistry.luau",
    "src/shared/Generated/AssetIds.luau",
    "src/shared/Remotes.luau",
    "src/server/RemoteGuard.luau",
    "src/server/Vendor/ProfileStore.luau",
    "src/server/Vendor/ProfileStore-LICENSE.txt",
    "src/server/Vendor/README.md",
    "src/server/Services/DataService.luau",
    "src/server/Services/TelemetryService.luau",
    "src/server/Builder/Greybox.luau",
    "src/server/Builder/AssetCache.luau",
    "src/client/UI/Theme.luau",
    "tests/loader.luau",
    "tests/harness.luau",
    "tests/run.luau",
    "tests/util.spec.luau",
    ".luaurc",
    "rokit.toml",
]

# Paramètres d'économie dérivés du genre : un point de départ défendable, pas une vérité.
ECONOMY_BY_GENRE = {
    "Simulation": {"tiers": 5, "ratio": 12, "first_value": 1, "first_interval": 2.0},
    "Obby": {"tiers": 4, "ratio": 8, "first_value": 5, "first_interval": 1.0},
    "Party": {"tiers": 3, "ratio": 10, "first_value": 10, "first_interval": 1.5},
    "Puzzle": {"tiers": 4, "ratio": 9, "first_value": 4, "first_interval": 1.5},
    "Adventure": {"tiers": 5, "ratio": 11, "first_value": 2, "first_interval": 1.8},
}
DEFAULT_ECONOMY = ECONOMY_BY_GENRE["Simulation"]


def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "jeu"


def pascal(text: str) -> str:
    return "".join(part.capitalize() for part in re.split(r"[^a-zA-Z0-9]+", text) if part) or "Jeu"


def copy_kit(destination: str) -> list[str]:
    copied = []
    for relative in SHARED_KIT:
        source = os.path.join(TEMPLATE, relative)
        if not os.path.exists(source):
            print(f"  absent du gabarit, ignoré : {relative}", file=sys.stderr)
            continue
        target = os.path.join(destination, relative)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(source, target)
        copied.append(relative)
    return copied


def economy_module(brief: dict) -> str:
    genre = brief["production"]["genre"]
    shape = ECONOMY_BY_GENRE.get(genre, DEFAULT_ECONOMY)
    cycle = brief["production"]["cycleSeconds"]
    tiers = []
    cost = 0.0
    value = float(shape["first_value"])
    interval = float(shape["first_interval"])
    minutes = cycle / 60
    for index in range(1, shape["tiers"] + 1):
        tiers.append(
            "\t{\n"
            f"\t\ttier = {index},\n"
            f'\t\tnameKey = "tier.{index}.name",\n'
            f"\t\tunlockCost = {int(cost)},\n"
            f"\t\tdropValue = {int(value)},\n"
            f"\t\tdropInterval = {round(interval, 2)},\n"
            f"\t\ttargetMinutes = {round(minutes, 1)},\n"
            f"\t\textraCosts = {{ {int(max(1, cost * 0.4)) if cost else 8}, {int(max(2, cost)) if cost else 15}, {int(max(4, cost * 2)) if cost else 25} }},\n"
            f"\t\tupgraderCost = {int(max(10, cost * 1.8)) if cost else 40},\n"
            "\t},"
        )
        cost = max(500.0, cost * shape["ratio"]) if cost else 500.0
        value *= shape["ratio"] * 0.7
        interval = max(0.8, interval * 0.9)
        minutes *= 2.6
    joined = "\n".join(tiers)
    return f"""--!strict
-- Économie générée depuis le brief ORACLE : {brief['concept']} ({genre}).
-- Ce sont des HYPOTHÈSES. Les tests vérifient la forme de la progression, pas les chiffres,
-- pour que le job de réglage de LEDGER puisse les ajuster sur la rétention réelle.

export type TierConfig = {{
	tier: number,
	nameKey: string,
	unlockCost: number,
	dropValue: number,
	dropInterval: number,
	targetMinutes: number,
	extraCosts: {{ number }},
	upgraderCost: number,
}}

local Economy = {{}}

Economy.CURRENCY = "Cash"
Economy.MAX_PLOTS = 6
Economy.SAVE_INTERVAL = 120
Economy.LIVE_DROPS_PER_PLOT = 150
Economy.TARGET_SESSION_MINUTES = {brief['production']['targetSessionMinutes']}
Economy.CYCLE_SECONDS = {cycle}

Economy.Tiers = {{
{joined}
}} :: {{ TierConfig }}

function Economy.tier(index: number): TierConfig
	local tier = Economy.Tiers[index]
	assert(tier ~= nil, "palier inconnu : " .. tostring(index))
	return tier
end

function Economy.maxTier(): number
	return #Economy.Tiers
end

return Economy
"""


def strings_module(brief: dict, title: str) -> str:
    tiers = ECONOMY_BY_GENRE.get(brief["production"]["genre"], DEFAULT_ECONOMY)["tiers"]
    entries = [f'\t["tier.{index}.name"] = {{ fr = "Palier {index}", en = "Tier {index}" }},' for index in range(1, tiers + 1)]
    joined = "\n".join(entries)
    return f"""--!strict
-- Tous les textes, FR et EN. Aucun texte en dur ailleurs dans le code.
-- Le test strings.spec vérifie que chaque clé existe dans les deux langues.

export type Locale = "fr" | "en"

local Strings = {{}}

Strings.DEFAULT_LOCALE = "fr" :: Locale

local T: {{ [string]: {{ fr: string, en: string }} }} = {{
	["game.title"] = {{ fr = "{title}", en = "{title}" }},
{joined}
	["hud.cash"] = {{ fr = "CASH", en = "CASH" }},
	["hud.collect"] = {{ fr = "COLLECTER", en = "COLLECT" }},
	["hud.shop"] = {{ fr = "BOUTIQUE", en = "SHOP" }},
	["hud.close"] = {{ fr = "FERMER", en = "CLOSE" }},
	["shop.reason.cost"] = {{ fr = "Pas assez de cash.", en = "Not enough cash." }},
	["shop.reason.owned"] = {{ fr = "Déjà possédé.", en = "Already owned." }},
	["shop.honest"] = {{ fr = "Tout ici s'obtient aussi gratuitement, plus lentement. Aucune offre n'expire.", en = "Everything here can also be earned for free, more slowly. No offer expires." }},
	["notify.welcome"] = {{ fr = "Bienvenue.", en = "Welcome." }},
}}

Strings.Table = T

function Strings.normalizeLocale(locale: string?): Locale
	if locale and string.sub(locale, 1, 2) == "en" then
		return "en"
	end
	return "fr"
end

function Strings.has(key: string): boolean
	return T[key] ~= nil
end

function Strings.get(key: string, locale: string?, params: {{ [string]: any }}?): string
	local entry = T[key]
	if entry == nil then
		return "[" .. key .. "]"
	end
	local text = entry[Strings.normalizeLocale(locale)]
	if params then
		text = string.gsub(text, "{{(%w+)}}", function(name: string): string
			local value = params[name]
			return if value == nil then "{{" .. name .. "}}" else tostring(value)
		end)
	end
	return text
end

return Strings
"""


def project_file(title: str) -> str:
    return json.dumps({
        "name": pascal(title),
        "globIgnorePaths": ["**/*.spec.luau", "**/README.md"],
        "tree": {
            "$className": "DataModel",
            "ReplicatedStorage": {
                "$className": "ReplicatedStorage",
                "Shared": {"$path": "src/shared"},
                "Remotes": {"$className": "Folder"},
                "Assets": {"$className": "Folder"},
            },
            "ServerScriptService": {"$className": "ServerScriptService", "Server": {"$path": "src/server"}},
            "StarterPlayer": {
                "$className": "StarterPlayer",
                "StarterPlayerScripts": {"$className": "StarterPlayerScripts", "Client": {"$path": "src/client"}},
            },
            "Workspace": {
                "$className": "Workspace",
                "$properties": {"StreamingEnabled": True, "StreamingTargetRadius": 512},
                "Baseplate": {
                    "$className": "Part",
                    "$properties": {
                        "Anchored": True, "Size": [1024, 4, 1024], "CFrame": [0, -2, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1],
                        "Color": [0.2, 0.2, 0.22], "Material": "Concrete", "Locked": True,
                    },
                },
            },
            "Lighting": {"$className": "Lighting", "$properties": {"Brightness": 2, "ClockTime": 14, "GlobalShadows": True}},
            "StarterGui": {"$className": "StarterGui"},
        },
    }, ensure_ascii=False, indent=2) + "\n"


def economy_spec(brief: dict) -> str:
    return f"""-- Ces tests décrivent la FORME de la progression, pas des chiffres figés : le job de réglage
-- de LEDGER ajuste les coûts sur la rétention réelle et doit pouvoir le faire sans casser la suite.
return function(t, loader)
	local Economy = loader.shared("Config.Economy")

	t.describe("Économie ({brief['concept']})", function()
		t.it("a des paliers dont le premier est gratuit et les coûts strictement croissants", function()
			t.expect(#Economy.Tiers).toBeGreaterThan(2)
			t.expect(Economy.Tiers[1].unlockCost).toBe(0)
			for index = 3, #Economy.Tiers do
				t.expect(Economy.Tiers[index].unlockCost).toBeGreaterThan(Economy.Tiers[index - 1].unlockCost)
			end
		end)
		t.it("accélère la cadence et augmente la valeur à chaque palier", function()
			for index = 2, #Economy.Tiers do
				t.expect(Economy.Tiers[index].dropInterval).toBeLessThanOrEqual(Economy.Tiers[index - 1].dropInterval)
				t.expect(Economy.Tiers[index].dropValue).toBeGreaterThan(Economy.Tiers[index - 1].dropValue)
			end
		end)
		t.it("vise une session d'au moins {brief['production']['targetSessionMinutes']} minutes", function()
			t.expect(Economy.TARGET_SESSION_MINUTES).toBeGreaterThanOrEqual(4)
		end)
	end)
end
"""


def strings_spec() -> str:
    return """return function(t, loader)
	local Strings = loader.shared("Strings")

	t.describe("Strings", function()
		t.it("a une traduction FR et EN non vide pour chaque clé", function()
			local count = 0
			for _, entry in Strings.Table do
				count += 1
				t.expect(type(entry.fr) == "string" and #entry.fr > 0).toBe(true)
				t.expect(type(entry.en) == "string" and #entry.en > 0).toBe(true)
			end
			t.expect(count).toBeGreaterThan(5)
		end)
		t.it("signale les clés inconnues au lieu de renvoyer du vide", function()
			t.expect(Strings.get("clé.absente")).toBe("[clé.absente]")
		end)
	end)
end
"""


def readme(brief: dict, title: str, slug: str) -> str:
    signal = brief["signal"]
    references = "\n".join(
        f"- [{entry['name']}]({entry['url']}) — {entry['ccu']} joueurs" if entry.get("url") else f"- {entry['name']}"
        for entry in brief["reference"]["playFirst"]
    ) or "- aucune référence en base"
    forbidden = "\n".join(f"- {item}" for item in brief["monetisation"]["forbidden"])
    systems = "\n".join(f"- [ ] {item}" for item in brief["production"]["requiredSystems"])
    return f"""# {title}

Généré par FORGE depuis un brief ORACLE, le {datetime.now(timezone.utc).strftime('%d/%m/%Y')}.

**Verdict d'ORACLE : {brief['verdict']['call']}** — {brief['verdict']['why']}

## Le signal

| Mesure | Valeur |
|---|---|
| Joueurs simultanés | {signal['ccu']} |
| Vélocité | {signal['velocityPerHour']:+.1%} par heure |
| Accélération | {signal['acceleration']:+.1%} |
| Saturation | {signal['saturation']:.2f} ({signal['clones']} clone(s)) |
| Âge de la tendance | {signal['ageDays'] if signal['ageDays'] is not None else '?'} jours |
| Fenêtre d'action | {signal['windowDays'][0]} à {signal['windowDays'][1]} jours |

## La boucle

{brief['production']['coreLoop']} — cycle de {brief['production']['cycleSeconds']} secondes,
session cible de {brief['production']['targetSessionMinutes']} minutes.

## À jouer avant de produire

Vingt minutes sur chacun. Noter l'emplacement des boutons, la distance entre les machines,
la vue au spawn.

{references}

## Systèmes à coder

{systems}

## Monétisation

Stratégie : **{brief['monetisation']['strategy']}**. {brief['monetisation']['policyService']}.

Interdits, sans exception :

{forbidden}

## Les chiffres de la première semaine

- Rétention à J+1 sous **{brief['successCriteria']['retentionD1']:.0%}** : le jeu ne décollera pas,
  ne pas mettre un Robux en publicité.
- Session médiane sous **{brief['successCriteria']['sessionMinutes']} minutes** : c'est le design
  qu'il faut reprendre, pas le code.
- Décision à **J+{brief['successCriteria']['decisionAtDays']}**.

## Commandes

```bash
bash ../../tools/check.sh games/{slug}    # lint, typecheck, tests, build
rojo serve default.project.json            # développement branché sur Studio
```

## Ce qui reste à faire à la main

Voir `docs/MANUEL-RESTANT.md` : créer l'univers, activer les gamepasses, cocher les toggles
de Game Settings, publier la première fois. Environ 20 minutes, une seule fois.
"""


def build(brief_path: str, out_dir: str, force: bool) -> str:
    with open(brief_path, encoding="utf-8") as handle:
        brief = json.load(handle)
    if brief.get("verdict", {}).get("call") == "passer":
        print(f"Attention : ORACLE dit « passer » sur ce concept ({brief['verdict']['why']}).", file=sys.stderr)
    slug = brief.get("slug") or slugify(brief["concept"])
    title = brief["production"].get("workingTitle") or pascal(slug)
    destination = os.path.join(out_dir, slug)
    if os.path.exists(destination):
        if not force:
            raise SystemExit(f"{destination} existe déjà (utiliser --force pour écraser)")
        shutil.rmtree(destination)
    os.makedirs(destination)

    copied = copy_kit(destination)

    files: dict[str, str] = {
        "default.project.json": project_file(title),
        # selene.toml propre au jeu : pas de bibliothèque de plugin tant qu'il n'y a pas de plugin.
        "selene.toml": 'std = "roblox"\nexclude = ["src/server/Vendor/**", "tests/run.luau", "tests/loader.luau"]\n\n[lints]\nmixed_table = "allow"\n',
        "src/shared/Config/Economy.luau": economy_module(brief),
        "src/shared/Strings.luau": strings_module(brief, title),
        "tests/economy.spec.luau": economy_spec(brief),
        "tests/strings.spec.luau": strings_spec(),
        "README.md": readme(brief, title, slug),
        "brief.json": json.dumps(brief, ensure_ascii=False, indent=1) + "\n",
        "PROGRESS.md": f"# PROGRESS — {title}\n\n## {datetime.now(timezone.utc).strftime('%Y-%m-%d')} : squelette généré\n\n"
                       f"**Fait.** Structure Rojo, kit partagé ({len(copied)} fichiers réutilisés), économie dérivée du brief, tests de forme.\n\n"
                       f"**Reste.** Toute la boucle de jeu : voir la liste des systèmes dans README.md.\n",
    }
    for relative, content in files.items():
        target = os.path.join(destination, relative)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(content)

    # points d'entrée minimaux : le jeu démarre et dit bonjour, dès la première minute
    entry_server = """--!strict
-- Point d'entrée serveur. Les services arrivent au fur et à mesure : l'ordre est celui des dépendances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

Remotes.create()

local Services = script:FindFirstChild("Services")
local ORDER = { "DataService", "TelemetryService" }

type Service = { Init: () -> (), Start: () -> () }
local loaded: { { name: string, service: Service } } = {}

for _, name in ORDER do
	local module = Services and Services:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		table.insert(loaded, { name = name, service = require(module) :: Service })
	end
end

for _, entry in loaded do
	local ok, err = pcall(entry.service.Init :: any)
	if not ok then
		error(string.format("[Boot] Init de %s a échoué : %s", entry.name, tostring(err)))
	end
end
for _, entry in loaded do
	local ok, err = pcall(entry.service.Start :: any)
	if not ok then
		error(string.format("[Boot] Start de %s a échoué : %s", entry.name, tostring(err)))
	end
end

print(string.format("[Boot] %d service(s) démarré(s)", #loaded))
"""
    entry_client = """--!strict
-- Point d'entrée client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
ReplicatedStorage:WaitForChild("Remotes", 30)
ReplicatedStorage:WaitForChild("Shared", 30)

local Strings = require(ReplicatedStorage.Shared.Strings)
print("[Client] " .. Strings.get("game.title"))
"""
    for relative, content in (("src/server/init.server.luau", entry_server), ("src/client/init.client.luau", entry_client)):
        with open(os.path.join(destination, relative), "w", encoding="utf-8") as handle:
            handle.write(content)

    # manifest d'assets vide mais valide : le jeu tourne en greybox
    manifest = {
        "game": slug,
        "style": "low poly stylized, chunky proportions, flat colors, clean topology, game asset, no text on the model",
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "rateLimitPerMinute": 5,
        "counts": {},
        "assets": [],
    }
    os.makedirs(os.path.join(destination, "assets"), exist_ok=True)
    with open(os.path.join(destination, "assets", "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=1)
        handle.write("\n")

    return destination


def main() -> None:
    parser = argparse.ArgumentParser(description="Génère un squelette de jeu depuis un brief ORACLE")
    parser.add_argument("--brief", required=True)
    parser.add_argument("--out", default=os.path.join(REPO, "games"))
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    destination = build(args.brief, args.out, args.force)
    print(f"jeu généré : {destination}")
    print("\nprochaines étapes :")
    print(f"  bash tools/check.sh games/{os.path.basename(destination)}")
    print(f"  cat {os.path.join(destination, 'README.md')}")


if __name__ == "__main__":
    main()
