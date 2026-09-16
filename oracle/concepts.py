#!/usr/bin/env python3
"""Regroupement des jeux par concept.

Sans regroupement, ORACLE compte quarante fois le même jeu et croit voir quarante tendances.
Deux niveaux :

  concept_key(name)     regroupement lexical, zéro dépendance, disponible tout de suite ;
  cluster(names)        regroupement par similarité (Jaccard sur les jetons + bigrammes),
                        qui rattrape les variantes que la clé lexicale sépare.

La version à embeddings arrive quand le volume le justifie : voir `--embeddings` dans features.py,
qui bascule automatiquement si un fichier de vecteurs est fourni.
"""

import re
import unicodedata

# Mots qui ne disent rien du concept : genre, marketing, mise à jour, emoji de vitrine.
STOPWORDS = {
    "simulator", "simulateur", "tycoon", "obby", "obbies", "rpg", "game", "games", "jeu",
    "update", "updated", "new", "beta", "alpha", "release", "remastered", "remake", "reborn",
    "codes", "code", "free", "vip", "best", "ultimate", "super", "mega", "ultra", "extreme",
    "the", "a", "an", "of", "and", "or", "in", "on", "for", "with", "your", "you", "my", "me",
    "le", "la", "les", "un", "une", "des", "de", "du", "et", "ou", "pour", "avec", "ton", "ta",
    "roblox", "official", "v1", "v2", "v3", "x2", "sale", "event", "halloween", "christmas",
    "summer", "winter", "update1", "fixed", "fix", "early", "access", "test", "demo",
}

# Jetons qui portent le concept même s'ils sont courts.
KEEP_SHORT = {"pet", "egg", "car", "gun", "war", "fly", "run", "box", "jam", "spy", "zoo"}

EMOJI = re.compile(
    "[" "\U0001F000-\U0001FAFF" "\U00002600-\U000027BF" "\U0001F1E6-\U0001F1FF" "\U00002190-\U000021FF" "\U00002B00-\U00002BFF" "]+",
    flags=re.UNICODE,
)
BRACKETS = re.compile(r"[\[\(【].*?[\]\)】]")
NON_WORD = re.compile(r"[^a-z0-9 ]+")
SPACES = re.compile(r"\s+")


def normalize(name: str) -> str:
    """Minuscules, sans accents, sans emoji, sans crochets marketing."""
    text = unicodedata.normalize("NFKD", name)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = EMOJI.sub(" ", text)
    text = BRACKETS.sub(" ", text)
    text = text.lower()
    text = NON_WORD.sub(" ", text)
    return SPACES.sub(" ", text).strip()


# Racinisation minimale : sans elle, « Steal An Egg » et « Steal Eggs » sont deux concepts,
# et ORACLE croit voir deux tendances là où il n'y en a qu'une.
IRREGULAR = {
    "people": "person", "children": "child", "men": "man", "women": "woman",
    "feet": "foot", "teeth": "tooth", "mice": "mouse", "geese": "goose", "knives": "knife",
    "lives": "life", "wolves": "wolf", "leaves": "leaf", "thieves": "thief",
}


def stem(token: str) -> str:
    if token in IRREGULAR:
        return IRREGULAR[token]
    if len(token) <= 3:
        return token
    if token.endswith("ies") and len(token) > 4:
        return token[:-3] + "y"
    if token.endswith("ses") or token.endswith("xes") or token.endswith("zes") or token.endswith("ches") or token.endswith("shes"):
        return token[:-2]
    if token.endswith("s") and not token.endswith("ss") and not token.endswith("us"):
        return token[:-1]
    if token.endswith("ing") and len(token) > 5:
        base = token[:-3]
        # doubled consonant : running -> run
        if len(base) > 2 and base[-1] == base[-2]:
            return base[:-1]
        return base
    # Pas de règle sur « -er » : elle abîme plus de mots (water, monster, master) qu'elle n'en aide.
    return token


def tokens(name: str) -> list[str]:
    out = []
    for token in normalize(name).split():
        if token in STOPWORDS:
            continue
        if token.isdigit():
            continue
        if len(token) < 3 and token not in KEEP_SHORT:
            continue
        rooted = stem(token)
        if rooted in STOPWORDS:
            continue
        out.append(rooted)
    return out


def concept_key(name: str) -> str:
    """Clé lexicale : les deux premiers jetons significatifs, triés pour être stables.

    « Steal an Egg », « Steal Eggs! », « 🥚 Steal Egg Simulator » tombent sur la même clé.
    """
    significant = tokens(name)
    if not significant:
        return normalize(name)[:24] or "inconnu"
    # Les deux premiers jetons portent le concept ; le tri rend la clé indépendante de l'ordre.
    head = sorted(significant[:2])
    return "-".join(head)


def _shingles(name: str) -> set[str]:
    """Jetons plus bigrammes : rattrape « pet catchers » et « catch pets »."""
    significant = tokens(name)
    grams = set(significant)
    for left, right in zip(significant, significant[1:]):
        grams.add("-".join(sorted((left, right))))
    return grams


def similarity(left: str, right: str) -> float:
    """Jaccard sur les jetons et bigrammes : 1.0 = même concept, 0.0 = rien en commun."""
    a, b = _shingles(left), _shingles(right)
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def cluster(names: list[str], threshold: float = 0.4) -> dict[str, str]:
    """Regroupe une liste de titres. Renvoie {titre: clé du groupe}.

    Glouton sur les titres triés par longueur : le titre le plus court d'un groupe donne son nom,
    ce qui produit des clés lisibles dans les alertes.
    """
    ordered = sorted(set(names), key=lambda name: (len(tokens(name)), name))
    groups: list[tuple[str, list[str]]] = []
    for name in ordered:
        placed = False
        for index, (leader, members) in enumerate(groups):
            if similarity(leader, name) >= threshold:
                groups[index][1].append(name)
                placed = True
                break
        if not placed:
            groups.append((name, [name]))
    mapping: dict[str, str] = {}
    for leader, members in groups:
        key = concept_key(leader)
        for member in members:
            mapping[member] = key
    return mapping


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        for argument in sys.argv[1:]:
            print(f"{argument!r} -> {concept_key(argument)}  jetons={tokens(argument)}")
    else:
        samples = [
            "Steal An Egg", "🥚 Steal Eggs!", "Steal an Egg Simulator [UPDATE]",
            "Lemonade Tycoon 🍋", "Sell Lemons 🍋", "Busy Business! 💸",
            "Grow a Garden", "Grow A Garden! 🌱", "Anime Fighters Simulator",
        ]
        mapping = cluster(samples)
        print("clé lexicale :")
        for sample in samples:
            print(f"  {sample:<36} -> {concept_key(sample)}")
        print("\nregroupement par similarité :")
        for sample in samples:
            print(f"  {sample:<36} -> {mapping[sample]}")
