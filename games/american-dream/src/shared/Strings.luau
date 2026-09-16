--!strict
-- Tous les textes du jeu, FR et EN. Aucun texte en dur ailleurs.
-- Strings.get(key, locale, params) remplace {nom} par params.nom.
-- Le test strings.spec vérifie que chaque clé existe dans les deux langues et que les clés référencées existent.

export type Locale = "fr" | "en"
export type Entry = { fr: string, en: string }

local Strings = {}

Strings.DEFAULT_LOCALE = "fr" :: Locale

local T: { [string]: Entry } = {
	-- Actes
	["act.1.name"] = { fr = "La Ruelle", en = "The Alley" },
	["act.2.name"] = { fr = "Le Commerce", en = "The Store" },
	["act.3.name"] = { fr = "L'Usine", en = "The Factory" },
	["act.4.name"] = { fr = "La Tour", en = "The Tower" },
	["act.5.name"] = { fr = "La Holding", en = "The Holding" },

	-- Objets de la boutique physique
	["item.unlock.1"] = { fr = "Stand de limonade", en = "Lemonade stand" },
	["item.unlock.2"] = { fr = "Ouvrir la superette", en = "Open the corner store" },
	["item.unlock.3"] = { fr = "Construire l'usine", en = "Build the factory" },
	["item.unlock.4"] = { fr = "Ériger la tour", en = "Raise the tower" },
	["item.unlock.5"] = { fr = "Fonder la holding", en = "Found the holding" },
	["item.dropper"] = { fr = "Machine supplémentaire", en = "Extra machine" },
	["item.upgrader"] = { fr = "Améliorateur (x2)", en = "Upgrader (x2)" },
	["item.conveyor"] = { fr = "Tapis rapide", en = "Fast conveyor" },
	["item.employee"] = { fr = "Embaucher", en = "Hire" },
	["item.decor.1.1"] = { fr = "Cageot de citrons", en = "Lemon crate" },
	["item.decor.1.2"] = { fr = "Palette de bois", en = "Wooden pallet" },
	["item.decor.2.1"] = { fr = "Néon OPEN", en = "OPEN neon sign" },
	["item.decor.2.2"] = { fr = "Caméra de surveillance", en = "Security camera" },
	["item.decor.3.1"] = { fr = "Panneau de sécurité", en = "Safety sign" },
	["item.decor.3.2"] = { fr = "Cheminée en brique", en = "Brick chimney" },
	["item.decor.4.1"] = { fr = "Plante artificielle", en = "Plastic plant" },
	["item.decor.4.2"] = { fr = "Sculpture abstraite", en = "Abstract sculpture" },
	["item.decor.5.1"] = { fr = "Statue en marbre", en = "Marble statue" },
	["item.decor.5.2"] = { fr = "Vitrine à trophées", en = "Trophy cabinet" },

	["shop.reason.unknown"] = { fr = "Objet inconnu.", en = "Unknown item." },
	["shop.reason.owned"] = { fr = "Déjà possédé.", en = "Already owned." },
	["shop.reason.requires"] = { fr = "Il manque un prérequis.", en = "Missing a prerequisite." },
	["shop.reason.cost"] = { fr = "Pas assez de cash.", en = "Not enough cash." },
	["shop.reason.plot"] = { fr = "Aucun plot attribué.", en = "No plot assigned." },
	["shop.reason.ratelimit"] = { fr = "Doucement.", en = "Slow down." },

	-- HUD
	["hud.cash"] = { fr = "CASH", en = "CASH" },
	["hud.stored"] = { fr = "Dans le collecteur : {amount}", en = "In the collector: {amount}" },
	["hud.collect"] = { fr = "COLLECTER", en = "COLLECT" },
	["hud.act"] = { fr = "Acte {act} : {name}", en = "Act {act}: {name}" },
	["hud.multiplier"] = { fr = "x{multiplier}", en = "x{multiplier}" },
	["hud.renaissances"] = { fr = "Renaissances : {count}", en = "Rebirths: {count}" },
	["hud.market.boom"] = { fr = "BOOM : revenus x2 ({seconds}s)", en = "BOOM: income x2 ({seconds}s)" },
	["hud.market.crash"] = { fr = "KRACH : revenus /2 ({seconds}s)", en = "CRASH: income /2 ({seconds}s)" },
	["hud.index"] = { fr = "INDICE GRIND", en = "GRIND INDEX" },
	["hud.shop"] = { fr = "BOUTIQUE", en = "SHOP" },
	["hud.settings"] = { fr = "RÉGLAGES", en = "SETTINGS" },
	["hud.journals"] = { fr = "JOURNAUX", en = "JOURNALS" },
	["hud.close"] = { fr = "FERMER", en = "CLOSE" },
	["hud.buy"] = { fr = "ACHETER", en = "BUY" },
	["hud.owned"] = { fr = "POSSÉDÉ", en = "OWNED" },
	["hud.unavailable"] = { fr = "INDISPONIBLE", en = "UNAVAILABLE" },
	["hud.next"] = { fr = "Prochain achat : {name} ({cost})", en = "Next purchase: {name} ({cost})" },

	-- Notifications
	["notify.welcome"] = { fr = "Bienvenue. Tu as un carton, un citron et une idée.", en = "Welcome. You have a box, a lemon and an idea." },
	["notify.plot"] = { fr = "Ton coin de ruelle : plot {plot}.", en = "Your corner of the alley: plot {plot}." },
	["notify.purchase"] = { fr = "{name} acheté.", en = "{name} purchased." },
	["notify.collect"] = { fr = "+{amount}", en = "+{amount}" },
	["notify.rent"] = { fr = "Loyer et charges : -{amount}", en = "Rent and bills: -{amount}" },
	["notify.rent.unpaid"] = { fr = "Loyer impayé. Le propriétaire a laissé un mot.", en = "Rent unpaid. The landlord left a note." },
	["notify.act"] = { fr = "Acte {act} : {name}. Regarde le ciel changer.", en = "Act {act}: {name}. Watch the sky change." },
	["notify.market.boom"] = { fr = "Les marchés s'emballent : x2 pendant {seconds}s !", en = "Markets are booming: x2 for {seconds}s!" },
	["notify.market.crash"] = { fr = "Krach. Tout vaut la moitié pendant {seconds}s.", en = "Crash. Everything is worth half for {seconds}s." },
	["notify.market.end"] = { fr = "Les marchés se calment.", en = "Markets settle down." },
	["notify.life.low"] = { fr = "Tu tousses. Personne ne remarque.", en = "You cough. Nobody notices." },
	["notify.life.exhausted"] = { fr = "Tes mains tremblent en comptant.", en = "Your hands shake while you count." },
	["notify.employee"] = { fr = "Nouvel employé. Il ne dit rien.", en = "New employee. They say nothing." },
	["notify.exit.locked"] = { fr = "La porte de secours est fermée. Pour l'instant.", en = "The emergency exit is locked. For now." },
	["notify.exit.open"] = { fr = "La porte de secours est ouverte.", en = "The emergency exit is open." },
	["notify.journal"] = { fr = "Journal ramassé : {title}", en = "Journal picked up: {title}" },
	["notify.badge"] = { fr = "Badge obtenu.", en = "Badge earned." },
	["notify.opa.attacked"] = { fr = "{name} rachète tes parts : 5 % de tes revenus pendant 2 min. Tu peux les racheter.", en = "{name} is buying your shares: 5% of your income for 2 min. You can buy them back." },
	["notify.opa.launched"] = { fr = "OPA lancée sur {name}.", en = "Takeover launched on {name}." },
	["notify.opa.buyback"] = { fr = "Parts rachetées. Tu es de nouveau seul maître à bord.", en = "Shares bought back. You are alone at the helm again." },
	["notify.opa.ended"] = { fr = "L'OPA est terminée.", en = "The takeover is over." },
	["notify.pack"] = { fr = "Pack reçu : +{amount}", en = "Pack received: +{amount}" },
	["notify.pass"] = { fr = "Merci. {name} est actif.", en = "Thank you. {name} is active." },
	["notify.saved"] = { fr = "Progression sauvegardée.", en = "Progress saved." },
	["notify.save_failed"] = { fr = "Sauvegarde indisponible : les achats sont désactivés par sécurité.", en = "Saving unavailable: purchases are disabled for safety." },

	-- OPA
	["opa.reason.self"] = { fr = "Tu ne peux pas racheter tes propres parts.", en = "You cannot buy your own shares." },
	["opa.reason.act"] = { fr = "Réservé aux holdings (acte 5).", en = "Holdings only (act 5)." },
	["opa.reason.target_act"] = { fr = "Cette cible n'est pas cotée.", en = "This target is not listed." },
	["opa.reason.cooldown"] = { fr = "Le conseil d'administration demande une pause.", en = "The board asks for a pause." },
	["opa.reason.target_busy"] = { fr = "Cette cible est déjà en OPA.", en = "This target is already under takeover." },
	["opa.reason.cost"] = { fr = "Pas assez de cash pour l'OPA ({cost}).", en = "Not enough cash for the takeover ({cost})." },
	["opa.title"] = { fr = "OPA", en = "TAKEOVER" },
	["opa.attack"] = { fr = "Lancer une OPA ({cost})", en = "Launch takeover ({cost})" },
	["opa.buyback"] = { fr = "Racheter mes parts ({cost})", en = "Buy my shares back ({cost})" },

	-- Vie / Burnout / Renaissance
	["burnout.title"] = { fr = "BURNOUT", en = "BURNOUT" },
	["burnout.body"] = { fr = "Tout est vendu. Tu te réveilles dans la ruelle.", en = "Everything is sold. You wake up in the alley." },
	["burnout.no_bonus"] = { fr = "Tu n'avais rien à vendre. La ruelle t'attendait.", en = "You had nothing to sell. The alley was waiting." },
	["renaissance.title"] = { fr = "RENAISSANCE", en = "REBIRTH" },
	["renaissance.body"] = { fr = "Multiplicateur permanent : x{multiplier}. Tu sais déjà comment ça finit.", en = "Permanent multiplier: x{multiplier}. You already know how it ends." },
	["renaissance.line.1"] = { fr = "Tu peux y arriver. Tu y es arrivé.", en = "You can make it. You made it." },
	["renaissance.line.2"] = { fr = "Le temps, c'est de l'argent. Tu n'as plus ni l'un ni l'autre.", en = "Time is money. You have neither left." },
	["renaissance.line.3"] = { fr = "Rêve plus grand. Dors moins.", en = "Dream bigger. Sleep less." },
	["exit.prompt"] = { fr = "Sortie de secours", en = "Emergency exit" },
	["exit.action"] = { fr = "Tout vendre", en = "Sell everything" },
	["exit.confirm.title"] = { fr = "Tout vendre ?", en = "Sell everything?" },
	["exit.confirm.body"] = { fr = "Tu repars dans la ruelle avec un multiplicateur x{multiplier}. Rien d'autre.", en = "You go back to the alley with a x{multiplier} multiplier. Nothing else." },
	["exit.confirm.yes"] = { fr = "Je signe", en = "I sign" },
	["exit.confirm.no"] = { fr = "Pas encore", en = "Not yet" },

	-- Prompts physiques
	["prompt.collect"] = { fr = "Collecter", en = "Collect" },
	["prompt.buy"] = { fr = "Acheter", en = "Buy" },
	["prompt.journal"] = { fr = "Lire", en = "Read" },
	["prompt.talk"] = { fr = "Parler", en = "Talk" },
	["prompt.opa"] = { fr = "Terminal OPA", en = "Takeover terminal" },

	-- Boutique Robux (honnête : chaque ligne dit exactement ce qu'elle fait)
	["shop.title"] = { fr = "Boutique", en = "Shop" },
	["shop.honest"] = { fr = "Tout ici s'obtient aussi gratuitement, plus lentement. Aucune offre n'expire.", en = "Everything here can also be earned for free, more slowly. No offer expires." },
	["shop.pass.double_cash.name"] = { fr = "Cash x2", en = "Cash x2" },
	["shop.pass.double_cash.desc"] = { fr = "Double tous tes revenus, pour toujours.", en = "Doubles all your income, forever." },
	["shop.pass.auto_collect.name"] = { fr = "Collecteur automatique", en = "Auto collector" },
	["shop.pass.auto_collect.desc"] = { fr = "Le collecteur se vide tout seul toutes les 10 s, sans employé, sans Vie perdue.", en = "The collector empties itself every 10 s, no employee, no Life lost." },
	["shop.pass.base_skins.name"] = { fr = "Skins de base", en = "Base skins" },
	["shop.pass.base_skins.desc"] = { fr = "Quatre palettes pour ta base, visibles par tous.", en = "Four color palettes for your base, visible to everyone." },
	["shop.pass.fast_renaissance.name"] = { fr = "Renaissance rapide", en = "Fast rebirth" },
	["shop.pass.fast_renaissance.desc"] = { fr = "La porte de secours s'ouvre à tout moment, sans attendre le burnout.", en = "The emergency exit opens any time, no need to wait for burnout." },
	["shop.pack.small"] = { fr = "5 minutes de production", en = "5 minutes of production" },
	["shop.pack.medium"] = { fr = "15 minutes de production", en = "15 minutes of production" },
	["shop.pack.large"] = { fr = "40 minutes de production", en = "40 minutes of production" },
	["shop.pack.note"] = { fr = "Le montant suit ta production actuelle : {amount}.", en = "The amount follows your current production: {amount}." },
	["shop.unavailable"] = { fr = "Bientôt disponible.", en = "Coming soon." },

	-- Réglages
	["settings.music"] = { fr = "Musique", en = "Music" },
	["settings.sfx"] = { fr = "Effets", en = "Effects" },
	["settings.language"] = { fr = "Langue", en = "Language" },

	-- Classement (affiché comme un indice boursier)
	["board.title"] = { fr = "INDICE GRIND CITY", en = "GRIND CITY INDEX" },
	["board.row"] = { fr = "{rank}. {name}  {worth}", en = "{rank}. {name}  {worth}" },
	["board.empty"] = { fr = "Marché fermé.", en = "Market closed." },

	-- PNJ
	["npc.homeless.name"] = { fr = "L'homme au manteau", en = "The man in the coat" },
	["npc.homeless.1"] = { fr = "Un citron, c'est un début. Garde-en un pour toi.", en = "A lemon is a start. Keep one for yourself." },
	["npc.homeless.2"] = { fr = "Une boutique ? Le loyer arrive avant les clients.", en = "A store? Rent comes before customers." },
	["npc.homeless.3"] = { fr = "J'ai eu une usine. La fumée, on s'y habitue. C'est ça le problème.", en = "I had a factory. You get used to the smoke. That's the problem." },
	["npc.homeless.4"] = { fr = "Du haut d'une tour, on ne voit plus les gens. C'est prévu comme ça.", en = "From the top of a tower you can't see people. That's by design." },
	["npc.homeless.5"] = { fr = "Je te reconnais. J'ai signé la même porte. Bienvenue au club.", en = "I know you. I signed the same door. Welcome to the club." },
	["npc.worker.name"] = { fr = "Employé", en = "Employee" },

	-- Publicités : 12 panneaux, un slogan par acte du joueur (l'acte 5 retourne le début)
	["ad.1.1"] = { fr = "Tu peux y arriver.", en = "You can make it." },
	["ad.1.2"] = { fr = "Tu y arrives.", en = "You're making it." },
	["ad.1.3"] = { fr = "Tu y es presque.", en = "You're almost there." },
	["ad.1.4"] = { fr = "Tu y es.", en = "You're there." },
	["ad.1.5"] = { fr = "Tu y es arrivé. Et maintenant ?", en = "You made it. Now what?" },
	["ad.2.1"] = { fr = "Le temps, c'est de l'argent.", en = "Time is money." },
	["ad.2.2"] = { fr = "Chaque seconde compte.", en = "Every second counts." },
	["ad.2.3"] = { fr = "Dors quand tu seras riche.", en = "Sleep when you're rich." },
	["ad.2.4"] = { fr = "Tu es riche. Dors.", en = "You're rich. Sleep." },
	["ad.2.5"] = { fr = "Le temps, c'était de l'argent.", en = "Time was money." },
	["ad.3.1"] = { fr = "Rêve plus grand.", en = "Dream bigger." },
	["ad.3.2"] = { fr = "Rêve plus vite.", en = "Dream faster." },
	["ad.3.3"] = { fr = "Rêve plus haut.", en = "Dream higher." },
	["ad.3.4"] = { fr = "Rêve plus fort.", en = "Dream harder." },
	["ad.3.5"] = { fr = "Rêve.", en = "Dream." },
	["ad.4.1"] = { fr = "Frais et fait maison.", en = "Fresh and homemade." },
	["ad.4.2"] = { fr = "Ouvert 24h/24.", en = "Open 24/7." },
	["ad.4.3"] = { fr = "Produit ici. Vendu partout.", en = "Made here. Sold everywhere." },
	["ad.4.4"] = { fr = "Coté en bourse.", en = "Publicly traded." },
	["ad.4.5"] = { fr = "Fait maison. Quelle maison ?", en = "Homemade. Whose home?" },
	["ad.5.1"] = { fr = "Sois ton propre patron.", en = "Be your own boss." },
	["ad.5.2"] = { fr = "Sois le patron.", en = "Be the boss." },
	["ad.5.3"] = { fr = "Sois le patron de 40 personnes.", en = "Be the boss of 40 people." },
	["ad.5.4"] = { fr = "Sois le patron de 4 000 personnes.", en = "Be the boss of 4,000 people." },
	["ad.5.5"] = { fr = "Ton patron, c'est le cours de l'action.", en = "Your boss is the stock price." },
	["ad.6.1"] = { fr = "La ville t'appartient.", en = "The city is yours." },
	["ad.6.2"] = { fr = "Ce quartier t'appartient.", en = "This block is yours." },
	["ad.6.3"] = { fr = "Cette rue t'appartient.", en = "This street is yours." },
	["ad.6.4"] = { fr = "Cet immeuble t'appartient.", en = "This building is yours." },
	["ad.6.5"] = { fr = "La ville t'appartient. Tu appartiens à la ville.", en = "The city is yours. You belong to the city." },
	["ad.7.1"] = { fr = "Personne ne te fera de cadeau.", en = "Nobody will give you a gift." },
	["ad.7.2"] = { fr = "Ne fais pas de cadeau.", en = "Don't give gifts." },
	["ad.7.3"] = { fr = "Un cadeau est une faiblesse.", en = "A gift is a weakness." },
	["ad.7.4"] = { fr = "Offre-toi un cadeau.", en = "Buy yourself a gift." },
	["ad.7.5"] = { fr = "Personne ne t'a fait de cadeau. Tu non plus.", en = "Nobody gave you a gift. Neither did you." },
	["ad.8.1"] = { fr = "Un jour, tout ça sera à toi.", en = "One day, all this will be yours." },
	["ad.8.2"] = { fr = "Bientôt, tout ça sera à toi.", en = "Soon, all this will be yours." },
	["ad.8.3"] = { fr = "Presque tout ça est à toi.", en = "Almost all this is yours." },
	["ad.8.4"] = { fr = "Tout ça est à toi.", en = "All this is yours." },
	["ad.8.5"] = { fr = "Tout ça est à toi. Et toi, à qui es-tu ?", en = "All this is yours. And whose are you?" },
	["ad.9.1"] = { fr = "Souris, c'est gratuit.", en = "Smile, it's free." },
	["ad.9.2"] = { fr = "Souris aux clients.", en = "Smile at customers." },
	["ad.9.3"] = { fr = "Souris pour la caméra.", en = "Smile for the camera." },
	["ad.9.4"] = { fr = "Souris pour les actionnaires.", en = "Smile for the shareholders." },
	["ad.9.5"] = { fr = "Souris. C'est ce qui reste de gratuit.", en = "Smile. It's what's left for free." },
	["ad.10.1"] = { fr = "Le succès, c'est 99 % de sueur.", en = "Success is 99% sweat." },
	["ad.10.2"] = { fr = "Le succès, c'est 99 % de travail.", en = "Success is 99% work." },
	["ad.10.3"] = { fr = "Le succès, c'est 99 % d'employés.", en = "Success is 99% employees." },
	["ad.10.4"] = { fr = "Le succès, c'est 99 % de marketing.", en = "Success is 99% marketing." },
	["ad.10.5"] = { fr = "Le succès, c'est 99 % de la sueur des autres.", en = "Success is 99% other people's sweat." },
	["ad.11.1"] = { fr = "Investis en toi.", en = "Invest in yourself." },
	["ad.11.2"] = { fr = "Investis dans ta boutique.", en = "Invest in your store." },
	["ad.11.3"] = { fr = "Investis dans les machines.", en = "Invest in machines." },
	["ad.11.4"] = { fr = "Investis dans l'influence.", en = "Invest in influence." },
	["ad.11.5"] = { fr = "Tu as tout investi. Il reste quoi de toi ?", en = "You invested everything. What's left of you?" },
	["ad.12.1"] = { fr = "Demain sera mieux.", en = "Tomorrow will be better." },
	["ad.12.2"] = { fr = "Demain sera plus grand.", en = "Tomorrow will be bigger." },
	["ad.12.3"] = { fr = "Demain sera plus rapide.", en = "Tomorrow will be faster." },
	["ad.12.4"] = { fr = "Demain sera coté.", en = "Tomorrow will be listed." },
	["ad.12.5"] = { fr = "Demain, c'était hier.", en = "Tomorrow was yesterday." },

	-- Journaux (12 collectibles) : la ville acte par acte
	["journal.J01.title"] = { fr = "Le Courrier de la Ruelle : « Un stand, un rêve »", en = "The Alley Courier: 'One stand, one dream'" },
	["journal.J01.body"] = { fr = "Un jeune vendeur de limonade dit vouloir « posséder la rue un jour ». Le propriétaire du mur où il s'adosse n'a pas été contacté.", en = "A young lemonade seller says he wants to 'own the street someday'. The owner of the wall he leans on was not reached for comment." },
	["journal.J02.title"] = { fr = "Petite annonce : chambre 6 m², vue sur benne", en = "Classified: 6 m² room, dumpster view" },
	["journal.J02.body"] = { fr = "Idéal travailleur motivé. Paiement en avance. Pas de visite le soir, les voisins dorment (ils travaillent tôt).", en = "Ideal for a motivated worker. Payment in advance. No visits at night, the neighbors sleep (they start early)." },
	["journal.J03.title"] = { fr = "Météo : pluie jusqu'à nouvel ordre", en = "Weather: rain until further notice" },
	["journal.J03.body"] = { fr = "Les flaques de la 4e rue reflètent désormais douze panneaux publicitaires. Record municipal.", en = "The puddles on 4th street now reflect twelve billboards. A municipal record." },
	["journal.J04.title"] = { fr = "Le Commerçant : « La superette qui ne ferme jamais »", en = "The Merchant: 'The store that never closes'" },
	["journal.J04.body"] = { fr = "Le gérant assure que ses employés « adorent les nuits ». Aucun employé n'était disponible pour confirmer, tous étant en poste.", en = "The manager says his employees 'love the night shift'. No employee was available to confirm, all being on shift." },
	["journal.J05.title"] = { fr = "Avis de loyer : +12 % « pour suivre le quartier »", en = "Rent notice: +12% 'to keep up with the neighborhood'" },
	["journal.J05.body"] = { fr = "Le quartier, interrogé, ne se souvient pas avoir demandé à être suivi.", en = "The neighborhood, when asked, does not recall asking to be kept up with." },
	["journal.J06.title"] = { fr = "Ticket de caisse : 1 café, 1 sandwich, 1 conseil", en = "Receipt: 1 coffee, 1 sandwich, 1 piece of advice" },
	["journal.J06.body"] = { fr = "Au dos, écrit à la main : « Prends une usine. Les gens, ça tombe malade. Les machines, ça s'amortit. »", en = "On the back, handwritten: 'Get a factory. People get sick. Machines depreciate.'" },
	["journal.J07.title"] = { fr = "L'Industriel : « Cadence record, ciel orange »", en = "The Industrialist: 'Record output, orange sky'" },
	["journal.J07.body"] = { fr = "La direction précise que la couleur du ciel « fait partie de l'identité visuelle de la marque ».", en = "Management clarifies that the sky color 'is part of the brand's visual identity'." },
	["journal.J08.title"] = { fr = "Note interne : pauses", en = "Internal memo: breaks" },
	["journal.J08.body"] = { fr = "Les pauses sont désormais comptées en secondes pour « plus de précision ». Le mot « pause » sera retiré du règlement au prochain trimestre.", en = "Breaks are now counted in seconds 'for more precision'. The word 'break' will be removed from the rulebook next quarter." },
	["journal.J09.title"] = { fr = "Fait divers : un ouvrier retrouvé endormi debout", en = "Local news: worker found asleep standing up" },
	["journal.J09.body"] = { fr = "Il a été félicité pour n'avoir pas quitté son poste.", en = "He was congratulated for not leaving his post." },
	["journal.J10.title"] = { fr = "La Tour : « Open space, esprit ouvert »", en = "The Tower: 'Open space, open mind'" },
	["journal.J10.body"] = { fr = "Les bureaux n'ont plus de murs, plus de portes, plus d'heures de fermeture. La direction parle de liberté.", en = "The offices have no more walls, no more doors, no more closing hours. Management calls it freedom." },
	["journal.J11.title"] = { fr = "Résultats trimestriels : la ville respire moins, l'action monte", en = "Quarterly results: the city breathes less, the stock rises" },
	["journal.J11.body"] = { fr = "Les analystes saluent « une gestion exemplaire des externalités ». Le mot n'a pas été défini.", en = "Analysts praise 'exemplary management of externalities'. The word was not defined." },
	["journal.J12.title"] = { fr = "Dernière page : lettre non envoyée", en = "Last page: unsent letter" },
	["journal.J12.body"] = { fr = "« J'ai tout. Je ne me souviens plus de ce que je voulais. Si tu lis ça, garde un citron pour toi. »", en = "'I have everything. I can't remember what I wanted. If you read this, keep a lemon for yourself.'" },
	["journals.title"] = { fr = "Journaux ramassés : {count}/{total}", en = "Journals collected: {count}/{total}" },
	["journals.locked"] = { fr = "Pas encore trouvé.", en = "Not found yet." },
}

Strings.Table = T

local function normalizeLocale(locale: string?): Locale
	if locale and string.sub(locale, 1, 2) == "en" then
		return "en"
	end
	return "fr"
end

Strings.normalizeLocale = normalizeLocale

function Strings.has(key: string): boolean
	return T[key] ~= nil
end

function Strings.get(key: string, locale: string?, params: { [string]: any }?): string
	local entry = T[key]
	if entry == nil then
		return "[" .. key .. "]"
	end
	local text = entry[normalizeLocale(locale)]
	if params then
		text = string.gsub(text, "{(%w+)}", function(name: string): string
			local value = params[name]
			if value == nil then
				return "{" .. name .. "}"
			end
			return tostring(value)
		end)
	end
	return text
end

function Strings.keys(): { string }
	local list = {}
	for key in T do
		table.insert(list, key)
	end
	table.sort(list)
	return list
end

return Strings
