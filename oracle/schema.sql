-- ORACLE : schéma de la base de tendances.
-- SQLite par défaut (zéro dépendance). Migration Postgres/TimescaleDB : voir le bas du fichier.

PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

-- Une expérience Roblox suivie. `concept_key` regroupe les clones d'un même concept.
CREATE TABLE IF NOT EXISTS experiences (
    universe_id      INTEGER PRIMARY KEY,
    root_place_id    INTEGER,
    name             TEXT NOT NULL,
    creator_id       INTEGER,
    creator_name     TEXT,
    creator_type     TEXT,
    creator_verified INTEGER DEFAULT 0,
    genre_l1         TEXT,
    genre_l2         TEXT,
    created_at       TEXT,       -- date de création de l'univers (ISO)
    updated_at       TEXT,       -- dernière mise à jour publiée
    max_players      INTEGER,
    content_maturity TEXT,
    concept_key      TEXT,       -- famille de concept (clustering)
    first_seen       TEXT NOT NULL,
    last_seen        TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_experiences_concept ON experiences(concept_key);
CREATE INDEX IF NOT EXISTS idx_experiences_created ON experiences(created_at);

-- Série temporelle. `ts` est arrondi au quart d'heure : deux ingestions dans la même fenêtre
-- écrasent la même ligne au lieu de gonfler la base.
CREATE TABLE IF NOT EXISTS snapshots (
    universe_id   INTEGER NOT NULL,
    ts            TEXT NOT NULL,
    playing       INTEGER,
    visits        INTEGER,
    favorites     INTEGER,
    up_votes      INTEGER,
    down_votes    INTEGER,
    PRIMARY KEY (universe_id, ts),
    FOREIGN KEY (universe_id) REFERENCES experiences(universe_id)
);
CREATE INDEX IF NOT EXISTS idx_snapshots_ts ON snapshots(ts);

-- Présence et rang dans les classements publics, par appareil.
CREATE TABLE IF NOT EXISTS sort_membership (
    universe_id  INTEGER NOT NULL,
    sort_id      TEXT NOT NULL,
    device       TEXT NOT NULL,
    rank         INTEGER NOT NULL,
    is_sponsored INTEGER DEFAULT 0,
    ts           TEXT NOT NULL,
    PRIMARY KEY (universe_id, sort_id, device, ts)
);
CREATE INDEX IF NOT EXISTS idx_sort_ts ON sort_membership(ts, sort_id);

-- Signaux hors plateforme : TikTok, YouTube, Google Trends. Renseignés par les workers externes.
CREATE TABLE IF NOT EXISTS external_signals (
    source      TEXT NOT NULL,     -- tiktok | youtube | trends | reddit
    term        TEXT NOT NULL,     -- mot-clé ou concept_key
    ts          TEXT NOT NULL,
    value       REAL NOT NULL,     -- vues, score, volume selon la source
    velocity    REAL,              -- variation par rapport au relevé précédent
    metadata    TEXT,              -- JSON libre
    PRIMARY KEY (source, term, ts)
);
CREATE INDEX IF NOT EXISTS idx_external_term ON external_signals(term, ts);

-- Scores calculés, un par univers et par passage.
CREATE TABLE IF NOT EXISTS opportunity_scores (
    universe_id   INTEGER NOT NULL,
    ts            TEXT NOT NULL,
    score         REAL NOT NULL,
    velocity      REAL,
    acceleration  REAL,
    saturation    REAL,
    ease          REAL,
    external      REAL,
    age_days      REAL,
    ccu           INTEGER,
    clones        INTEGER,
    components    TEXT,            -- JSON du détail, pour comprendre un score après coup
    PRIMARY KEY (universe_id, ts)
);
CREATE INDEX IF NOT EXISTS idx_scores_ts ON opportunity_scores(ts, score);

-- LE journal qui rend le système impossible à copier : toute décision, y compris les refus.
-- La moitié du signal est dans ce que tu écartes.
CREATE TABLE IF NOT EXISTS predictions_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    concept_key     TEXT NOT NULL,
    universe_id     INTEGER,        -- l'univers déclencheur, si la piste vient d'un jeu repéré
    decided_at      TEXT NOT NULL,
    predicted_score REAL NOT NULL,
    components      TEXT,           -- JSON du score au moment de la décision
    decision        TEXT NOT NULL,  -- shipped | skipped
    reason          TEXT,           -- pourquoi, en une phrase
    -- Résultat mesuré à J+30 (rempli plus tard par `predictions.py --settle`)
    settled_at      TEXT,
    peak_ccu        INTEGER,
    revenue_robux   INTEGER,
    outcome_score   REAL,           -- résultat normalisé 0..1, comparable au score prédit
    notes           TEXT
);
CREATE INDEX IF NOT EXISTS idx_predictions_concept ON predictions_log(concept_key);
CREATE INDEX IF NOT EXISTS idx_predictions_decided ON predictions_log(decided_at);

-- Poids du score, versionnés : la régression écrit une nouvelle ligne, elle n'écrase jamais.
CREATE TABLE IF NOT EXISTS score_weights (
    version      INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at   TEXT NOT NULL,
    weights      TEXT NOT NULL,   -- JSON {acceleration: .., velocity: .., ...}
    sample_size  INTEGER NOT NULL,
    r_squared    REAL,
    note         TEXT
);

-- Journal des passages d'ingestion : sert à repérer une source qui se ferme sans prévenir.
CREATE TABLE IF NOT EXISTS ingest_runs (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at    TEXT NOT NULL,
    finished_at   TEXT,
    experiences   INTEGER DEFAULT 0,
    snapshots     INTEGER DEFAULT 0,
    errors        INTEGER DEFAULT 0,
    note          TEXT
);

-- ---------------------------------------------------------------------------
-- Migration Postgres / TimescaleDB (quand le volume dépasse quelques millions de lignes) :
--   INTEGER PRIMARY KEY AUTOINCREMENT  ->  BIGSERIAL PRIMARY KEY
--   TEXT (dates ISO)                   ->  TIMESTAMPTZ
--   INTEGER (identifiants Roblox)      ->  BIGINT
--   puis : SELECT create_hypertable('snapshots', 'ts');
--          SELECT create_hypertable('opportunity_scores', 'ts');
-- ---------------------------------------------------------------------------
