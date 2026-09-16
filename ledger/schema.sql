-- LEDGER : télémétrie de jeu, rétention, et réglage de l'économie.
-- Alimenté soit par le collecteur HTTP (collector.py), soit par un export du Creator Dashboard.

PRAGMA journal_mode = WAL;

-- Événements bruts envoyés par le jeu. `layout` porte la variante A/B du plot.
CREATE TABLE IF NOT EXISTS events (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    place_id   INTEGER,
    job_id     TEXT,
    user_id    INTEGER NOT NULL,
    layout     INTEGER DEFAULT 0,
    event      TEXT NOT NULL,
    value      REAL DEFAULT 1,
    payload    TEXT,
    ts         INTEGER NOT NULL,       -- horodatage Unix envoyé par le serveur de jeu
    received   INTEGER NOT NULL        -- horodatage à la réception : détecte une horloge décalée
);
CREATE INDEX IF NOT EXISTS idx_events_user ON events(user_id, ts);
CREATE INDEX IF NOT EXISTS idx_events_name ON events(event, ts);
CREATE INDEX IF NOT EXISTS idx_events_layout ON events(layout, event);

-- Une ligne par joueur et par jour : base de tous les calculs de rétention.
CREATE TABLE IF NOT EXISTS player_days (
    user_id    INTEGER NOT NULL,
    day        TEXT NOT NULL,          -- AAAA-MM-JJ
    layout     INTEGER DEFAULT 0,
    seconds    INTEGER DEFAULT 0,
    sessions   INTEGER DEFAULT 0,
    max_act    INTEGER DEFAULT 1,
    purchases  INTEGER DEFAULT 0,
    robux      INTEGER DEFAULT 0,
    PRIMARY KEY (user_id, day)
);
CREATE INDEX IF NOT EXISTS idx_player_days_day ON player_days(day);

-- Instantané quotidien des métriques qui décident si le jeu continue ou non.
CREATE TABLE IF NOT EXISTS daily_metrics (
    day               TEXT PRIMARY KEY,
    new_players       INTEGER DEFAULT 0,
    returning_players INTEGER DEFAULT 0,
    retention_d1      REAL,
    retention_d7      REAL,
    median_seconds    INTEGER,
    conversion_rate   REAL,
    arpdau_robux      REAL,
    computed_at       TEXT NOT NULL
);

-- Étapes de l'entonnoir : où les joueurs s'arrêtent.
CREATE TABLE IF NOT EXISTS funnel_daily (
    day        TEXT NOT NULL,
    step       INTEGER NOT NULL,
    step_name  TEXT NOT NULL,
    layout     INTEGER DEFAULT 0,
    players    INTEGER DEFAULT 0,
    PRIMARY KEY (day, step, layout)
);

-- Propositions de réglage de l'économie, avec ce qui les a motivées.
-- Rien n'est appliqué automatiquement : le job ouvre une proposition, un humain valide.
CREATE TABLE IF NOT EXISTS tuning_proposals (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at   TEXT NOT NULL,
    window_days  INTEGER NOT NULL,
    diagnosis    TEXT NOT NULL,
    changes      TEXT NOT NULL,      -- JSON : chemin de configuration -> {avant, après}
    evidence     TEXT NOT NULL,      -- JSON : les chiffres qui justifient
    applied      INTEGER DEFAULT 0,
    applied_at   TEXT
);
