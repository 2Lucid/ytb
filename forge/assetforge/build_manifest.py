#!/usr/bin/env python3
"""Génère assets/manifest.json : la liste complète des assets d'American Dream.

Chaque entrée porte :
  id        identifiant de manifest (MSH_A3_DROP_HydraulicPress)
  category  DROP / UPG / COLL / CONV / DECO / CITY / CHAR / LORE / GP / TEX / SFX / MUS / ANM
  act       1..5, ou 0 pour ce qui est commun à la ville
  kind      mesh | image | audio | animation
  prompt    prompt Cube 3D (meshes) ou brief (2D / audio)
  schema    Body1 (défaut) ou Car5 (véhicules et objets multi-parties)
  scale     taille cible en studs [x, y, z]
  decalSlot face où poser le texte en Decal / SurfaceGui (Cube 3D est mauvais sur le texte)
  hero      true = asset vu de près, à produire en modèle détaillé plutôt qu'en lot
  status    pending | done | failed
  assetId   0 tant que non généré

Usage : python3 build_manifest.py [--out ../../games/american-dream/assets/manifest.json]
"""

import argparse
import json
import os
from datetime import datetime, timezone

# Préfixe de style imposé à chaque prompt Cube 3D : cohérence visuelle du jeu entier.
STYLE = "low poly stylized, chunky proportions, flat colors, clean topology, game asset, no text on the model"

# (id, prompt, scale, schema, decalSlot, hero)
MESHES: dict[str, list[tuple]] = {
    # ---------------------------------------------------------------- Acte 1 : La Ruelle
    "A1": [
        ("DROP_LemonadeStand", "wooden lemonade stand with a hand painted sign board, crates of lemons, small awning", [4, 5, 4], "Body1", "Front", True),
        ("UPG_RustyJuicer", "rusty cast iron manual citrus juicer press on a small metal table, worn paint", [3, 4, 3], "Body1", None, False),
        ("COLL_CoinJar", "large glass jar half filled with coins on a wooden crate, metal lid with a slot", [3, 4, 3], "Body1", None, True),
        ("CONV_PlankTrestle", "long wooden plank resting on two sawhorse trestles, weathered timber", [30, 1, 3], "Body1", None, False),
        ("DECO_CardboardShelter", "makeshift cardboard box shelter with a folded blanket, damp corrugated texture", [6, 4, 5], "Body1", None, False),
        ("DECO_Dumpster", "dented green metal dumpster with a separate hinged lid part", [7, 5, 4], "Car5", "Front", False),
        ("DECO_TrashBags", "pile of four black plastic garbage bags, glossy crumpled surface", [4, 3, 4], "Body1", None, False),
        ("DECO_FireEscape", "modular steel fire escape section with stairs and railing, flaking black paint", [8, 12, 4], "Body1", None, False),
        ("DECO_Pallet", "stack of two wooden shipping pallets, splintered edges", [4, 2, 4], "Body1", None, False),
        ("DECO_ShoppingCart", "supermarket shopping cart with one bent wheel, chrome wire basket", [3, 4, 5], "Car5", None, False),
        ("DECO_RustyBike", "rusty bicycle leaning on nothing, flat tires, missing seat", [6, 4, 2], "Body1", None, False),
        ("DECO_BentLamppost", "bent street lamppost with a cracked lamp head, chipped grey paint", [2, 14, 2], "Body1", None, False),
        ("DECO_Crate", "wooden fruit crate with slatted sides, stencil marks worn off", [3, 2, 3], "Body1", "Front", False),
        ("DECO_Puddle", "flat shallow water puddle disc with a rippled reflective surface", [6, 1, 5], "Body1", None, False),
    ],
    # ---------------------------------------------------------------- Acte 2 : Le Commerce
    "A2": [
        ("DROP_VendingMachine", "illuminated drinks vending machine with a glass front and lit product rows", [4, 7, 3], "Body1", "Front", True),
        ("UPG_CoffeeMachine", "stainless steel espresso machine with portafilter and steam wand, commercial size", [4, 4, 3], "Body1", None, False),
        ("COLL_CashRegister", "vintage brass cash register with a separate sliding drawer part and round keys", [4, 4, 3], "Car5", None, True),
        ("CONV_CheckoutBelt", "supermarket checkout conveyor belt segment with rubber belt and metal frame", [24, 1, 4], "Body1", None, False),
        ("DECO_StorefrontFacade", "small corner store facade with a wide window, door and blank sign panel above", [20, 12, 2], "Body1", "Front", False),
        ("DECO_Gondola", "supermarket gondola shelving unit with four shelves of boxed goods", [8, 6, 3], "Body1", None, False),
        ("DECO_GlassFridge", "upright glass door drinks fridge with lit interior shelves", [4, 7, 3], "Body1", "Front", False),
        ("DECO_NeonOpen", "blank oval neon sign tube ring on a dark backing plate", [4, 2, 1], "Body1", "Front", False),
        ("DECO_WhiteVan", "plain white delivery van with blank side panels, boxy shape", [16, 7, 7], "Car5", "Right", False),
        ("DECO_HandTruck", "two wheeled hand truck dolly leaning against nothing, steel frame", [3, 5, 2], "Body1", None, False),
        ("DECO_SecurityCamera", "wall mounted dome security camera on a short bracket arm", [2, 2, 3], "Body1", None, False),
        ("DECO_SmallSafe", "small floor safe with a round combination dial and thick door", [3, 3, 3], "Car5", None, False),
        ("DECO_FruitCrates", "stack of three open crates of apples and oranges", [4, 4, 3], "Body1", None, False),
    ],
    # ---------------------------------------------------------------- Acte 3 : L'Usine
    "A3": [
        ("DROP_HydraulicPress", "industrial hydraulic press with a separate vertical piston part and yellow safety frame", [6, 8, 5], "Car5", None, True),
        ("UPG_RobotArm", "yellow industrial robot arm with three articulated segments on a round base", [4, 7, 4], "Car5", None, True),
        ("COLL_Palletizer", "factory palletizer station with a roller table and stacked output pallet", [7, 6, 6], "Body1", None, False),
        ("CONV_RollerBelt", "heavy industrial roller conveyor section with steel rollers and side rails", [30, 2, 4], "Body1", None, False),
        ("DECO_SteelHangar", "modular corrugated steel hangar wall section with ribbed panels", [20, 14, 2], "Body1", None, False),
        ("DECO_Chimney", "tall red brick factory chimney tapering upward with a metal band at the top", [5, 30, 5], "Body1", None, False),
        ("DECO_ChemicalTank", "large cylindrical chemical storage tank with pipes and a top hatch", [7, 9, 7], "Body1", None, False),
        ("DECO_ToxicBarrel", "rusted steel barrel with a warning stripe band, dented lid", [3, 4, 3], "Body1", "Front", False),
        ("DECO_Container", "shipping container with separate hinged double doors on one end", [20, 8, 8], "Car5", "Front", False),
        ("DECO_Forklift", "warehouse forklift with separate fork carriage and four wheels", [8, 7, 5], "Car5", None, False),
        ("DECO_Gantry", "overhead gantry crane rail section with a trolley block", [20, 6, 4], "Body1", None, False),
        ("DECO_Lockers", "row of four dented metal changing room lockers", [6, 7, 2], "Body1", None, False),
        ("DECO_Generator", "portable diesel generator unit with exhaust pipe and control panel", [5, 4, 3], "Body1", "Front", False),
        ("DECO_SafetySign", "blank rectangular safety sign on a short metal post", [3, 4, 1], "Body1", "Front", False),
    ],
    # ---------------------------------------------------------------- Acte 4 : La Tour
    "A4": [
        ("DROP_ServerRack", "black server rack cabinet with rows of blinking LED strips and mesh doors", [3, 8, 3], "Body1", None, True),
        ("UPG_TradingScreen", "curved ultrawide trading monitor on a desk arm, dark bezel", [6, 4, 2], "Body1", "Front", False),
        ("COLL_ExecutiveDesk", "executive desk of glass and brushed steel with a leather blotter", [10, 4, 5], "Body1", None, True),
        ("CONV_PneumaticTube", "clear pneumatic tube section with brass couplings, straight run", [20, 2, 2], "Body1", None, False),
        ("DECO_OfficeFloor", "modular open plan office floor plate with low partitions", [20, 3, 20], "Body1", None, False),
        ("DECO_Workstation", "office workstation with monitor, keyboard and swivel chair", [5, 4, 5], "Body1", None, False),
        ("DECO_Photocopier", "large floor standing office photocopier with paper trays", [4, 5, 3], "Body1", "Front", False),
        ("DECO_WaterCooler", "office water cooler with an inverted blue bottle and two taps", [2, 5, 2], "Body1", None, False),
        ("DECO_BoardTable", "long oval boardroom table in dark polished wood", [16, 3, 7], "Body1", None, False),
        ("DECO_GlassElevator", "glass elevator shaft section with separate sliding double doors", [6, 12, 6], "Car5", None, False),
        ("DECO_LeatherChair", "high backed black leather executive chair on a chrome base", [3, 5, 3], "Body1", None, False),
        ("DECO_PlasticPlant", "artificial ficus plant in a square white pot, slightly dusty", [3, 6, 3], "Body1", None, False),
        ("DECO_AbstractSculpture", "abstract twisted chrome sculpture on a black marble plinth", [3, 7, 3], "Body1", None, False),
        ("DECO_Helipad", "rooftop helipad circle platform with edge lights and a blank centre", [20, 1, 20], "Body1", "Top", False),
    ],
    # ---------------------------------------------------------------- Acte 5 : La Holding
    "A5": [
        ("DROP_MoneyPrinter", "industrial banknote printing press with a paper feed and stacked output tray", [7, 6, 5], "Car5", None, True),
        ("UPG_SatelliteDish", "white parabolic satellite dish on a motorised mount", [7, 7, 6], "Car5", None, False),
        ("COLL_Vault", "art deco bank vault door with a separate spoked wheel handle and a separate dial, bronze and green marble", [7, 8, 3], "Car5", None, True),
        ("CONV_GoldRail", "polished brass rail conveyor section with gold trim", [20, 2, 3], "Body1", None, False),
        ("DECO_Penthouse", "glass penthouse corner section with floor to ceiling windows and a steel frame", [20, 12, 20], "Body1", None, False),
        ("DECO_GoldBars", "neat stack of twelve gold bullion bars", [4, 2, 3], "Body1", None, False),
        ("DECO_PrivateJet", "small private jet with separate wings and landing gear, glossy white", [30, 10, 28], "Car5", None, False),
        ("DECO_Yacht", "small luxury motor yacht hull with an upper deck, white and teak", [40, 12, 12], "Body1", None, False),
        ("DECO_MarbleStatue", "white marble statue of a businessman with one arm raised in triumph, on a plinth", [4, 9, 4], "Body1", None, True),
        ("DECO_ChampagneCart", "gold trolley cart with a champagne bucket and glasses", [4, 4, 3], "Car5", None, False),
        ("DECO_GoldGlobe", "gilded world globe on a curved brass stand", [4, 5, 4], "Body1", None, False),
        ("DECO_BiometricGate", "glass biometric security gate pair with a scanner pillar", [6, 6, 3], "Car5", None, False),
        ("DECO_TrophyCabinet", "tall empty glass trophy display cabinet with lit shelves", [4, 8, 2], "Body1", None, False),
    ],
    # ---------------------------------------------------------------- Ville et environnement
    "CITY": [
        ("BuildingBrick", "modular old brick apartment building block, twenty stud module, fire escape and window rows", [20, 20, 20], "Body1", None, False),
        ("BuildingConcrete", "modular nineteen seventies concrete office block module, horizontal window bands", [20, 20, 20], "Body1", None, False),
        ("BuildingGlass", "modular corporate glass curtain wall tower module, blue tinted panes", [20, 20, 20], "Body1", None, False),
        ("Sidewalk", "modular concrete sidewalk slab section with a kerb edge", [20, 1, 5], "Body1", None, False),
        ("Manhole", "cast iron manhole cover disc with a radial pattern, no text", [3, 1, 3], "Body1", "Top", False),
        ("BillboardPole", "large blank billboard panel on two steel support poles with a catwalk", [16, 22, 2], "Body1", "Front", True),
        ("BillboardWall", "blank wall mounted billboard frame with a lighting bar", [14, 8, 1], "Body1", "Front", False),
        ("TrafficLight", "city traffic light on a curved pole with three lamp housings", [2, 14, 3], "Body1", None, False),
        ("SignPost", "blank street sign post with two empty rectangular plates", [1, 8, 3], "Body1", "Front", False),
        ("Sedan", "generic four door city sedan car, matte paint, no badges", [14, 5, 7], "Car5", None, False),
        ("Taxi", "yellow city taxi sedan with a blank roof sign box", [14, 5, 7], "Car5", "Top", False),
        ("Bus", "city transit bus with blank side advertising panels", [30, 9, 9], "Car5", "Right", False),
        ("BusStop", "bus shelter with a bench and a blank advertising panel on one side", [10, 8, 4], "Body1", "Right", False),
        ("Bench", "public park bench with wooden slats and cast iron ends", [6, 3, 2], "Body1", None, False),
        ("TrashCan", "city street trash can, perforated metal cylinder with a lid ring", [2, 4, 2], "Body1", None, False),
        ("Hydrant", "red fire hydrant with two side valves and a chain cap", [2, 3, 2], "Body1", None, False),
        ("PlanterTree", "small city tree in a square concrete planter box", [5, 12, 5], "Body1", None, False),
        ("Lamppost", "straight city lamppost with a curved arm and a lamp head", [2, 14, 4], "Body1", None, False),
        ("NeonVertical", "blank vertical neon sign blade mounted on a wall bracket", [2, 10, 1], "Body1", "Front", False),
    ],
    # ---------------------------------------------------------------- Collectibles lore
    "LORE": [
        ("Journal", "folded newspaper with a blank front page, slightly creased", [3, 1, 2], "Body1", "Top", False),
        ("UsbKey", "small USB flash drive with a pulled off cap", [1, 1, 2], "Body1", None, False),
        ("PhotoFrame", "small standing photo frame with a blank photo area", [2, 3, 1], "Body1", "Front", False),
        ("EmployeeBadge", "employee ID badge on a lanyard, blank card face", [2, 3, 1], "Body1", "Front", False),
        ("LongReceipt", "very long crumpled paper receipt roll trailing on the ground", [2, 1, 6], "Body1", "Top", False),
        ("BusinessCard", "single business card lying flat, blank face", [2, 1, 1], "Body1", "Top", False),
        ("AudioCassette", "audio cassette tape with a blank label area", [2, 1, 2], "Body1", "Top", False),
        ("PillBottle", "tipped over prescription pill bottle with spilled white tablets", [2, 2, 3], "Body1", "Front", False),
    ],
    # ---------------------------------------------------------------- Objets de gameplay
    "GP": [
        ("ButtonBase", "round illuminated floor button pad with a metal rim and a glowing centre disc", [4, 1, 4], "Body1", "Top", False),
        ("PlotBorder", "low modular boundary kerb strip with a lit edge line", [20, 1, 1], "Body1", None, False),
        ("LifeTotem", "tall thin glowing glass column totem on a dark metal base", [2, 8, 2], "Body1", None, False),
        ("ExitDoor", "heavy red emergency exit door in a steel frame with a push bar", [4, 8, 1], "Body1", "Front", True),
        ("StockTicker", "narrow dark display strip panel for a scrolling stock ticker", [20, 3, 1], "Body1", "Front", False),
        ("PRD_Lemon", "single bright yellow lemon", [1, 1, 1], "Body1", None, False),
        ("PRD_Can", "sealed aluminium drinks can with a blank wrap", [1, 2, 1], "Body1", "Front", False),
        ("PRD_Crate", "small sealed cardboard shipping box with tape", [2, 2, 2], "Body1", "Top", False),
        ("PRD_DataIngot", "glowing translucent data block ingot with circuit etching", [2, 1, 2], "Body1", None, False),
        ("PRD_Briefcase", "closed metal briefcase with combination latches", [3, 1, 2], "Body1", None, False),
    ],
}

# Personnages : rigs R15 obligatoires (sinon aucune animation ne s'applique).
CHARACTERS = [
    ("CHAR_Worker", "factory worker in blue coveralls with a yellow hard hat", ["hard hat", "work gloves"]),
    ("CHAR_Vendor", "street vendor in an apron over a t-shirt", ["apron", "cap"]),
    ("CHAR_Clerk", "shop clerk in a green apron with a name badge", ["apron", "badge"]),
    ("CHAR_OfficeWorker", "office worker in a white shirt with a lanyard badge", ["lanyard badge", "headset"]),
    ("CHAR_Executive", "executive in a dark tailored suit carrying a briefcase", ["briefcase", "wristwatch"]),
    ("CHAR_Investor", "elderly investor in a brown three piece suit with a pocket watch", ["pocket watch", "spectacles"]),
    ("CHAR_Homeless", "man in a worn long coat with a blanket over the shoulders", ["blanket", "wool hat"]),
    ("CHAR_Mascot", "person in a smiling dollar bill mascot costume, slightly unsettling", ["mascot head"]),
]

# Animations R15 : passe automatique en text-to-anim, puis retouche manuelle des trois dernières.
ANIMATIONS = [
    ("ANM_NPC_WorkerLift", "worker lifts a heavy box from the floor to chest height and sets it down", True, False),
    ("ANM_NPC_WorkerIdle", "worker stands and wipes sweat from the forehead with a forearm", True, False),
    ("ANM_NPC_ClerkScan", "clerk scans an item across a counter scanner and slides it aside", True, False),
    ("ANM_NPC_OfficeType", "office worker types at a keyboard with rounded hunched shoulders", True, False),
    ("ANM_NPC_ExecPhone", "executive paces while talking into a phone held to the ear", True, False),
    ("ANM_NPC_InvestorNod", "elderly man nods slowly with arms crossed", True, False),
    ("ANM_NPC_Patrol", "security guard walks a short patrol and looks left and right", True, False),
    ("ANM_PLR_CountCash", "character counts a stack of banknotes held in one hand", True, False),
    ("ANM_PLR_CheckWatch", "character glances at a wristwatch then lets the arm drop", True, False),
    ("ANM_PLR_Handshake", "character extends a hand forward for a business handshake", True, False),
    ("ANM_PLR_Celebrate", "character raises both arms in a short triumphant celebration", True, False),
    ("ANM_PLR_Exhausted", "character stands with drooped shoulders, head low, breathing heavily", True, True),
    ("ANM_PLR_Collapse", "character sinks slowly to the knees then sits back against nothing", True, True),
    ("ANM_PLR_WakeUp", "character pushes up from the ground and stands unsteadily", True, True),
]

# 2D : logo, thumbnail, affiches, marques, journaux, HUD, icônes. Outil : Claude Design, un par un.
IMAGES = [
    ("TEX_LOGO_Main", "logo of the game, wordmark on a neon city skyline silhouette", [1024, 512]),
    ("TEX_LOGO_Square", "square app icon version of the logo, readable at 64 pixels", [512, 512]),
    ("TEX_LOGO_Mono", "single colour version of the logo for overlays", [1024, 512]),
    ("TEX_THUMB_A", "game thumbnail: a lone figure at a lemonade stand dwarfed by neon towers, dramatic rim light", [1920, 1080]),
    ("TEX_THUMB_B", "game thumbnail: split composition, cardboard box on the left, penthouse on the right", [1920, 1080]),
    ("TEX_THUMB_C", "game thumbnail: close up of a hand holding a lemon in front of a stock ticker wall", [1920, 1080]),
    ("TEX_HUD_Cash", "cash icon for the HUD, coin stack, flat style", [256, 256]),
    ("TEX_HUD_Life", "subtle pulse line icon for the silent Life gauge", [256, 256]),
    ("TEX_HUD_Shop", "shop icon, shopping bag, flat style", [256, 256]),
    ("TEX_HUD_Journal", "folded newspaper icon, flat style", [256, 256]),
    ("TEX_HUD_Board", "stock index icon, rising bar chart, flat style", [256, 256]),
    ("TEX_UI_Renaissance", "full screen art for the rebirth screen: dawn light over an empty alley", [1920, 1080]),
    ("TEX_PASS_DoubleCash", "gamepass icon for double cash, two coin stacks", [512, 512]),
    ("TEX_PASS_AutoCollect", "gamepass icon for auto collector, a hand and a conveyor", [512, 512]),
    ("TEX_PASS_Skins", "gamepass icon for base skins, four colour swatches", [512, 512]),
    ("TEX_PASS_FastRebirth", "gamepass icon for fast rebirth, an open exit door with light", [512, 512]),
    ("TEX_BRAND_1", "fictional brand logo: a soft drink company, retro red and cream", [512, 512]),
    ("TEX_BRAND_2", "fictional brand logo: a logistics company, blue arrow monogram", [512, 512]),
    ("TEX_BRAND_3", "fictional brand logo: a fast food chain, yellow smiling wordmark", [512, 512]),
    ("TEX_BRAND_4", "fictional brand logo: a bank, navy shield with an eagle", [512, 512]),
    ("TEX_BRAND_5", "fictional brand logo: a tech firm, minimal lowercase wordmark", [512, 512]),
    ("TEX_BRAND_6", "fictional brand logo: an energy drink, aggressive lightning mark", [512, 512]),
    ("TEX_BRAND_7", "fictional brand logo: a pharmaceutical company, teal cross", [512, 512]),
    ("TEX_BRAND_8", "fictional brand logo: a real estate holding, gold serif monogram", [512, 512]),
]
# Douze couvertures de journaux, une par entrée de Config/Lore.
IMAGES += [(f"TEX_NEWS_J{index:02d}", f"newspaper front page layout for journal {index:02d}, masthead and blank column blocks", [1024, 1024]) for index in range(1, 13)]

# Audio : cinq musiques d'acte, un thème de Renaissance, cinq ambiances, effets.
AUDIO_MUSIC = [
    ("SFX_MUS_Act1", "sparse lo-fi hip hop loop, rain, single muted piano motif, 70 bpm, loopable"),
    ("SFX_MUS_Act2", "same motif on a brighter electric piano with a light shuffle beat, 88 bpm, loopable"),
    ("SFX_MUS_Act3", "same motif on industrial percussion and a distorted bass, 104 bpm, loopable"),
    ("SFX_MUS_Act4", "same motif on synth arpeggios with a driving kick, compressed, 120 bpm, loopable"),
    ("SFX_MUS_Act5", "same motif maximally compressed, saturated synth brass, 132 bpm, loopable"),
    ("SFX_MUS_Renaissance", "same motif slowed to half tempo on solo piano, relieved and sad, 60 bpm"),
]
AUDIO_AMBIENCE = [
    ("SFX_AMB_Alley", "quiet rainy back alley ambience, distant traffic, dripping water, loopable"),
    ("SFX_AMB_Street", "busy shopping street ambience, footsteps, chatter, a door chime, loopable"),
    ("SFX_AMB_Factory", "factory floor ambience, machinery hum, hydraulic hiss, loopable"),
    ("SFX_AMB_Office", "open plan office ambience, keyboards, printer, muffled calls, loopable"),
    ("SFX_AMB_Penthouse", "near silent penthouse ambience, air conditioning, faint city far below, loopable"),
]
AUDIO_SFX = [
    ("SFX_UI_Purchase", "short satisfying purchase confirm chime"),
    ("SFX_UI_Denied", "short soft denial thud, not harsh"),
    ("SFX_UI_Collect", "coins sliding into a jar, short"),
    ("SFX_UI_Conveyor", "short conveyor belt roller loop"),
    ("SFX_UI_Press", "hydraulic press stamping down once"),
    ("SFX_UI_SlotMachine", "slot machine reel stopping, three clicks"),
    ("SFX_UI_Register", "vintage cash register drawer opening with a bell"),
    ("SFX_UI_Rent", "paper envelope dropping through a letterbox slot"),
    ("SFX_UI_TierUp", "short ascending fanfare, brass, two seconds"),
    ("SFX_UI_LifeLow", "low sub bass swell warning, subtle"),
    ("SFX_UI_Heartbeat", "single slow heartbeat thump"),
    ("SFX_UI_Phone", "office desk phone ringing twice"),
    ("SFX_UI_Elevator", "elevator arrival ding and door slide"),
    ("SFX_UI_Applause", "canned television applause, three seconds"),
    ("SFX_UI_Jingle", "three second cheerful advertising jingle, deliberately repetitive"),
    ("SFX_EVT_BoomFanfare", "upbeat market boom fanfare, two seconds"),
    ("SFX_EVT_CrashAlarm", "market crash alarm klaxon, two seconds"),
    ("SFX_EVT_Opa", "corporate takeover alert sting, cold synth"),
    ("SFX_EVT_Journal", "paper page turn, soft"),
    ("SFX_EVT_Badge", "short bright badge unlock chime"),
    ("SFX_EVT_Burnout", "everything cutting to silence with a single low thud"),
    ("SFX_EVT_WakeUp", "distant morning birdsong and a slow breath in"),
]


def mesh_entries() -> list[dict]:
    out = []
    for group, items in MESHES.items():
        act = int(group[1]) if group.startswith("A") and group[1].isdigit() else 0
        for suffix, prompt, scale, schema, decal, hero in items:
            category = suffix.split("_")[0]
            asset_id = f"MSH_{group}_{suffix}" if group != "CITY" and group != "LORE" and group != "GP" else f"MSH_{group}_{suffix}"
            out.append({
                "id": asset_id,
                "kind": "mesh",
                "category": category,
                "act": act,
                "prompt": f"{prompt}, {STYLE}",
                "schema": schema,
                "scale": scale,
                "decalSlot": decal,
                "maxTriangles": 5000 if hero else 2000,
                "hero": hero,
                "status": "pending",
                "assetId": 0,
            })
    return out


def character_entries() -> list[dict]:
    return [{
        "id": identifier,
        "kind": "character",
        "category": "CHAR",
        "act": 0,
        "prompt": f"{prompt}, {STYLE}",
        "schema": "R15",
        "scale": [4, 6, 2],
        "accessories": accessories,
        "note": "Générer sur base de rig R15 standard, jamais en mesh libre : sinon aucune animation ne s'applique. Accessoires en mesh attachés par Motor6D.",
        "status": "pending",
        "assetId": 0,
    } for identifier, prompt, accessories in CHARACTERS]


def animation_entries() -> list[dict]:
    return [{
        "id": identifier,
        "kind": "animation",
        "category": "ANM",
        "act": 0,
        "prompt": prompt,
        "rig": "R15",
        "autoPass": auto,
        "manualPolish": polish,
        "note": "Retouche manuelle obligatoire dans l'Animation Editor" if polish else "Passe automatique suffisante",
        "status": "pending",
        "assetId": 0,
    } for identifier, prompt, auto, polish in ANIMATIONS]


def image_entries() -> list[dict]:
    return [{
        "id": identifier,
        "kind": "image",
        "category": "TEX",
        "act": 0,
        "prompt": prompt,
        "size": size,
        "tool": "Claude Design",
        "status": "pending",
        "assetId": 0,
    } for identifier, prompt, size in IMAGES]


def audio_entries() -> list[dict]:
    out = []
    for identifier, prompt in AUDIO_MUSIC:
        out.append({"id": identifier, "kind": "audio", "category": "MUS", "act": 0, "prompt": prompt, "tool": "Suno", "loop": True, "status": "pending", "assetId": 0})
    for identifier, prompt in AUDIO_AMBIENCE:
        out.append({"id": identifier, "kind": "audio", "category": "AMB", "act": 0, "prompt": prompt, "tool": "Suno", "loop": True, "status": "pending", "assetId": 0})
    for identifier, prompt in AUDIO_SFX:
        out.append({"id": identifier, "kind": "audio", "category": "SFX", "act": 0, "prompt": prompt, "tool": "ElevenLabs", "loop": False, "status": "pending", "assetId": 0})
    return out


def build() -> dict:
    assets = mesh_entries() + character_entries() + animation_entries() + image_entries() + audio_entries()
    seen: set[str] = set()
    for asset in assets:
        if asset["id"] in seen:
            raise SystemExit(f"identifiant en double dans le manifest : {asset['id']}")
        seen.add(asset["id"])
    counts: dict[str, int] = {}
    for asset in assets:
        counts[asset["kind"]] = counts.get(asset["kind"], 0) + 1
    return {
        "game": "american-dream",
        "style": STYLE,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "rateLimitPerMinute": 5,
        "counts": counts,
        "assets": assets,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Génère le manifest des assets")
    default_out = os.path.join(os.path.dirname(__file__), "..", "..", "games", "american-dream", "assets", "manifest.json")
    parser.add_argument("--out", default=os.path.normpath(default_out))
    parser.add_argument("--preserve", action="store_true", help="conserve les status et assetId déjà présents")
    args = parser.parse_args()

    manifest = build()
    if args.preserve and os.path.exists(args.out):
        with open(args.out, encoding="utf-8") as handle:
            previous = json.load(handle)
        known = {asset["id"]: asset for asset in previous.get("assets", [])}
        for asset in manifest["assets"]:
            old = known.get(asset["id"])
            if old and old.get("assetId", 0) > 0:
                asset["assetId"] = old["assetId"]
                asset["status"] = old.get("status", "done")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=1)
        handle.write("\n")
    total = len(manifest["assets"])
    print(f"manifest écrit : {args.out}")
    print(f"{total} assets : " + ", ".join(f"{count} {kind}" for kind, count in sorted(manifest["counts"].items())))
    heroes = [asset["id"] for asset in manifest["assets"] if asset.get("hero")]
    print(f"{len(heroes)} assets héros (modèle détaillé, pas de lot) : {', '.join(heroes)}")


if __name__ == "__main__":
    main()
