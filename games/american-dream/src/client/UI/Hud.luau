--!strict
-- HUD : cash, jauge de Vie silencieuse, collecteur, acte, marché, boutons d'ouverture.
-- Construit une seule fois, mis à jour par UIController. Aucun calcul de jeu ici.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Theme = require(script.Parent.Theme)

local Hud = {}

export type Handle = {
	gui: ScreenGui,
	cash: TextLabel,
	stored: TextLabel,
	collect: TextButton,
	act: TextLabel,
	multiplier: TextLabel,
	lifeBar: Frame,
	lifeFill: Frame,
	market: TextLabel,
	shopButton: TextButton,
	journalsButton: TextButton,
	boardButton: TextButton,
	notifications: Frame,
	nextHint: TextLabel,
}

function Hud.build(locale: string): Handle
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10

	-- Cash en haut à gauche
	local cashPanel = Theme.panel("Cash", UDim2.fromOffset(210, 62), UDim2.fromOffset(12, 12))
	cashPanel.Parent = gui
	local cashLabel = Theme.label("Value", "0", UDim2.new(1, -16, 0, 34), UDim2.fromOffset(8, 4))
	cashLabel.TextColor3 = Theme.Cash
	cashLabel.Font = Theme.FontTitle
	cashLabel.Parent = cashPanel
	local storedLabel = Theme.label("Stored", "", UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 38))
	storedLabel.TextColor3 = Theme.TextDim
	storedLabel.TextScaled = true
	storedLabel.Parent = cashPanel

	-- Multiplicateur, collé au panneau de cash
	local multiplier = Theme.label("Multiplier", "", UDim2.fromOffset(74, 28), UDim2.fromOffset(228, 12))
	multiplier.TextColor3 = Theme.Positive
	multiplier.Font = Theme.FontNumber
	multiplier.TextXAlignment = Enum.TextXAlignment.Left
	multiplier.Parent = gui

	-- Acte courant sous le cash
	local actLabel = Theme.label("Act", "", UDim2.fromOffset(260, 22), UDim2.fromOffset(14, 80))
	actLabel.TextColor3 = Theme.TextDim
	actLabel.Parent = gui

	-- Jauge de Vie en haut à droite, sans libellé : elle n'est jamais expliquée au début
	local lifeBar = Instance.new("Frame")
	lifeBar.Name = "Life"
	lifeBar.Size = UDim2.fromOffset(150, 8)
	lifeBar.Position = UDim2.new(1, -162, 0, 18)
	lifeBar.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
	lifeBar.BorderSizePixel = 0
	Theme.corner(lifeBar, 4)
	lifeBar.Parent = gui
	local lifeFill = Instance.new("Frame")
	lifeFill.Name = "Fill"
	lifeFill.Size = UDim2.fromScale(1, 1)
	lifeFill.BackgroundColor3 = Theme.Life
	lifeFill.BorderSizePixel = 0
	Theme.corner(lifeFill, 4)
	lifeFill.Parent = lifeBar

	-- Bandeau de marché centré en haut
	local market = Theme.label("Market", "", UDim2.fromOffset(320, 26), UDim2.new(0.5, -160, 0, 14))
	market.TextXAlignment = Enum.TextXAlignment.Center
	market.Font = Theme.FontNumber
	market.TextTransparency = 1
	market.Parent = gui

	-- Collecte : gros bouton tactile en bas à droite
	local collect = Theme.button("Collect", Strings.get("hud.collect", locale), UDim2.fromOffset(168, 58), UDim2.new(1, -180, 1, -76), Theme.Positive)
	collect.Parent = gui

	-- Colonne de boutons en bas à gauche
	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.Size = UDim2.fromOffset(132, 3 * (Theme.TouchTarget + 8))
	buttons.Position = UDim2.new(0, 12, 1, -(3 * (Theme.TouchTarget + 8)) - 12)
	buttons.BackgroundTransparency = 1
	buttons.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = buttons

	local function sideButton(name: string, key: string, order: number): TextButton
		local button = Theme.button(name, Strings.get(key, locale), UDim2.new(1, 0, 0, Theme.TouchTarget), UDim2.new(), Theme.PanelLight)
		button.LayoutOrder = order
		button.Parent = buttons
		return button
	end
	local shopButton = sideButton("Shop", "hud.shop", 1)
	local journalsButton = sideButton("Journals", "hud.journals", 2)
	local boardButton = sideButton("Board", "hud.index", 3)

	-- Indice du prochain achat, juste au-dessus du bouton de collecte
	local nextHint = Theme.label("NextHint", "", UDim2.fromOffset(320, 20), UDim2.new(1, -332, 1, -100))
	nextHint.TextXAlignment = Enum.TextXAlignment.Right
	nextHint.TextColor3 = Theme.TextDim
	nextHint.Parent = gui

	-- Pile de notifications à droite, au-dessus du bouton de collecte
	local notifications = Instance.new("Frame")
	notifications.Name = "Notifications"
	notifications.Size = UDim2.fromOffset(300, 200)
	notifications.Position = UDim2.new(1, -312, 0.5, -100)
	notifications.BackgroundTransparency = 1
	notifications.Parent = gui
	local notifLayout = Instance.new("UIListLayout")
	notifLayout.Padding = UDim.new(0, 6)
	notifLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	notifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
	notifLayout.Parent = notifications

	gui.Parent = player:WaitForChild("PlayerGui")

	return {
		gui = gui,
		cash = cashLabel,
		stored = storedLabel,
		collect = collect,
		act = actLabel,
		multiplier = multiplier,
		lifeBar = lifeBar,
		lifeFill = lifeFill,
		market = market,
		shopButton = shopButton,
		journalsButton = journalsButton,
		boardButton = boardButton,
		notifications = notifications,
		nextHint = nextHint,
	}
end

function Hud.setCash(handle: Handle, cash: number)
	handle.cash.Text = Format.money(cash)
end

function Hud.setStored(handle: Handle, stored: number, cap: number, locale: string)
	if stored < 1 then
		handle.stored.Text = ""
		handle.collect.BackgroundColor3 = Theme.PanelLight
		return
	end
	handle.stored.Text = Strings.get("hud.stored", locale, { amount = Format.money(stored) })
	local full = cap > 0 and stored >= cap * 0.98
	handle.collect.BackgroundColor3 = full and Theme.Warning or Theme.Positive
end

function Hud.setAct(handle: Handle, act: number, locale: string)
	handle.act.Text = Strings.get("hud.act", locale, { act = act, name = Strings.get(Economy.tier(act).nameKey, locale) })
	handle.act.TextColor3 = Theme.accent(act)
end

function Hud.setMultiplier(handle: Handle, multiplier: number)
	if math.abs(multiplier - 1) < 0.001 then
		handle.multiplier.Text = ""
		return
	end
	handle.multiplier.Text = string.format("x%.2f", multiplier):gsub("%.?0+$", "")
	handle.multiplier.TextColor3 = multiplier >= 1 and Theme.Positive or Theme.Negative
end

function Hud.setLife(handle: Handle, life: number)
	local ratio = math.clamp(life / Economy.Life.max, 0, 1)
	handle.lifeFill.Size = UDim2.fromScale(ratio, 1)
	handle.lifeFill.BackgroundColor3 = ratio < Economy.Life.exhaustedThreshold and Theme.LifeLow or Theme.Life
end

return Hud
