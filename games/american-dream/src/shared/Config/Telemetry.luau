--!strict
-- Collecteur externe optionnel (ledger/collector.py). Vide = AnalyticsService uniquement.
-- Ne jamais mettre de secret ici : COLLECTOR_KEY est un identifiant de flux, pas une clé d'API.
return {
	COLLECTOR_URL = "",
	COLLECTOR_KEY = "american-dream",
	FLUSH_INTERVAL = 30,
}
