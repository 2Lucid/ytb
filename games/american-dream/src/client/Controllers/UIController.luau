--!strict
-- Colle entre les remotes serveur et l'interface. N'effectue aucun calcul de jeu : il affiche ce que
-- le serveur envoie et renvoie des intentions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Types = require(ReplicatedStorage.Shared.Types)
local Hud = require(script.Parent.Parent.UI.Hud)
local Panels = require(script.Parent.Parent.UI.Panels)
local Theme = require(script.Parent.Parent.UI.Theme)

type HudSnapshot = Types.HudSnapshot

local UIController = {}

local player = Players.LocalPlayer
local locale: string = Strings.DEFAULT_LOCALE
local hud: Hud.Handle
local panels: Panels.Handle
local snapshot: HudSnapshot = { cash = 0, life = Economy.Life.max, act = 1, renaissances = 0, multiplier = 1, stored = 0, storedCap = 0 }
local journalsOwned: { [string]: boolean } = {}
local shopState: { [string]: any } = {}
local notificationCount = 0

local function notify(key: string, params: { [string]: any }?, color: Color3?)
	notificationCount += 1
	local order = notificationCount
	local frame = Instance.new("TextLabel")
	frame.Name = "Notif" .. order
	frame.Size = UDim2.new(1, 0, 0, 34)
	frame.BackgroundColor3 = Theme.Panel
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.TextColor3 = color or Theme.Text
	frame.Font = Theme.FontBody
	frame.TextSize = 15
	frame.TextXAlignment = Enum.TextXAlignment.Right
	frame.TextTruncate = Enum.TextTruncate.AtEnd
	frame.LayoutOrder = order
	frame.Text = "  " .. Strings.get(key, locale, params) .. "  "
	Theme.corner(frame, 6)
	frame.Parent = hud.notifications
	task.delay(4, function()
		local fade = TweenService:Create(frame, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		frame:Destroy()
	end)
	-- garde au plus 5 notifications
	local children = {}
	for _, child in hud.notifications:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(children, child)
		end
	end
	table.sort(children, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = 1, #children - 5 do
		children[index]:Destroy()
	end
end

local function updateNextHint()
	local hint = ""
	local remotePlot = player:GetAttribute("OwnedItems")
	if type(remotePlot) == "string" then
		hint = remotePlot
	end
	hud.nextHint.Text = hint
end

local function applySnapshot(next: HudSnapshot)
	local previousAct = snapshot.act
	snapshot = next
	Hud.setCash(hud, next.cash)
	Hud.setStored(hud, next.stored, next.storedCap, locale)
	Hud.setLife(hud, next.life)
	Hud.setMultiplier(hud, next.multiplier)
	if next.act ~= previousAct then
		Hud.setAct(hud, next.act, locale)
	end
	updateNextHint()
end

local function closeAllPanels()
	panels.shop.frame.Visible = false
	panels.journals.frame.Visible = false
	panels.board.frame.Visible = false
end

local function togglePanel(panel: Panels.Panel, onOpen: (() -> ())?)
	local willOpen = not panel.frame.Visible
	closeAllPanels()
	panel.frame.Visible = willOpen
	if willOpen and onOpen then
		onOpen()
	end
end

local function showOverlay(titleKey: string, bodyText: string, yesKey: string?, noKey: string?, onYes: (() -> ())?)
	panels.overlay.Visible = true
	panels.overlayTitle.Text = Strings.get(titleKey, locale)
	panels.overlayBody.Text = bodyText
	panels.overlayYes.Visible = yesKey ~= nil
	panels.overlayNo.Visible = noKey ~= nil
	if yesKey then
		panels.overlayYes.Text = Strings.get(yesKey, locale)
	end
	if noKey then
		panels.overlayNo.Text = Strings.get(noKey, locale)
	end
	TweenService:Create(panels.overlay, TweenInfo.new(0.5), { BackgroundTransparency = 0.25 }):Play()
	TweenService:Create(panels.overlayTitle, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
	TweenService:Create(panels.overlayBody, TweenInfo.new(0.8), { TextTransparency = 0 }):Play()
	UIController.overlayCallback = onYes
end

local function hideOverlay()
	UIController.overlayCallback = nil
	panels.overlayYes.Visible = false
	panels.overlayNo.Visible = false
	local fadeBg = TweenService:Create(panels.overlay, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
	TweenService:Create(panels.overlayTitle, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	TweenService:Create(panels.overlayBody, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	fadeBg:Play()
	fadeBg.Completed:Once(function()
		panels.overlay.Visible = false
	end)
end

UIController.overlayCallback = nil :: (() -> ())?

local function onLifeEvent(kind: string, payload: { [string]: any })
	if kind == "burnout" then
		closeAllPanels()
		local bodyKey = payload.bonus and "burnout.body" or "burnout.no_bonus"
		showOverlay("burnout.title", Strings.get(bodyKey, locale))
	elseif kind == "renaissance" then
		local body = Strings.get("renaissance.body", locale, { multiplier = string.format("%.2f", payload.multiplier or 1):gsub("%.?0+$", "") })
		local line = payload.lineKey and Strings.get(payload.lineKey, locale) or ""
		showOverlay("renaissance.title", line .. "\n\n" .. body)
		task.delay(6, hideOverlay)
	elseif kind == "exit_prompt" then
		local body = Strings.get("exit.confirm.body", locale, { multiplier = string.format("%.2f", payload.multiplier or 1):gsub("%.?0+$", "") })
		showOverlay("exit.confirm.title", body, "exit.confirm.yes", "exit.confirm.no", function()
			Remotes.getEvent("ExitDoor"):FireServer(true)
		end)
	elseif kind == "exhausted" then
		notify("notify.life.exhausted", nil, Theme.Negative)
	end
end

local function onMarketChanged(payload: { [string]: any })
	local kind = payload.kind
	if kind == "boom" or kind == "crash" then
		hud.market.Text = Strings.get(kind == "boom" and "hud.market.boom" or "hud.market.crash", locale, { seconds = math.floor(payload.endsIn or 0) })
		hud.market.TextColor3 = kind == "boom" and Theme.Positive or Theme.Negative
		TweenService:Create(hud.market, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	else
		TweenService:Create(hud.market, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
	end
end

local function onLoreEvent(kind: string, payload: { [string]: any })
	if kind == "owned" then
		journalsOwned = payload.journals or {}
	elseif kind == "journal" then
		if payload.already ~= true then
			journalsOwned[payload.id] = true
		end
		Panels.fillJournals(panels.journals, journalsOwned, locale)
		if not panels.journals.frame.Visible then
			togglePanel(panels.journals)
		end
	elseif kind == "npc" then
		notify(payload.key, nil, Theme.Cash)
	end
end

local function onOpaEvent(kind: string, payload: { [string]: any })
	if kind == "attacked" then
		showOverlay("opa.title", Strings.get("notify.opa.attacked", locale, { name = payload.attacker or "?" }), "opa.buyback", "exit.confirm.no", function()
			Remotes.getEvent("OpaBuyback"):FireServer()
		end)
		panels.overlayYes.Text = Strings.get("opa.buyback", locale, { cost = Format.money(payload.buyback or 0) })
		task.delay(10, function()
			if panels.overlay.Visible and panels.overlayYes.Visible then
				hideOverlay()
			end
		end)
	elseif kind == "open" then
		local candidates = payload.candidates or {}
		if #candidates == 0 then
			notify("opa.reason.target_act")
			return
		end
		local target = candidates[1]
		showOverlay("opa.title", Strings.get("opa.attack", locale, { cost = Format.money(target.cost or 0) }) .. "\n" .. target.name, "exit.confirm.yes", "exit.confirm.no", function()
			Remotes.getEvent("OpaAttack"):FireServer(target.userId)
		end)
	elseif kind == "ended" then
		hideOverlay()
	end
end

function UIController.Init()
	local data = player:GetAttribute("Locale")
	locale = Strings.normalizeLocale(type(data) == "string" and data or nil)
	hud = Hud.build(locale)
	panels = Panels.build(locale)
	Hud.setAct(hud, 1, locale)
end

function UIController.Start()
	hud.collect.Activated:Connect(function()
		Remotes.getEvent("Collect"):FireServer()
	end)
	hud.shopButton.Activated:Connect(function()
		togglePanel(panels.shop, function()
			Panels.fillShop(panels.shop, shopState, locale, function(kind: string, key: string)
				Remotes.getEvent("PromptPurchase"):FireServer(kind, key)
			end)
			Remotes.getEvent("ClientEvent"):FireServer("shop_open", 1)
		end)
	end)
	hud.journalsButton.Activated:Connect(function()
		togglePanel(panels.journals, function()
			Panels.fillJournals(panels.journals, journalsOwned, locale)
		end)
	end)
	hud.boardButton.Activated:Connect(function()
		togglePanel(panels.board)
	end)
	for _, panel in { panels.shop, panels.journals, panels.board } do
		panel.close.Activated:Connect(closeAllPanels)
	end
	panels.overlayYes.Activated:Connect(function()
		local callback = UIController.overlayCallback
		hideOverlay()
		if callback then
			callback()
		end
	end)
	panels.overlayNo.Activated:Connect(hideOverlay)

	Remotes.getEvent("HudUpdate").OnClientEvent:Connect(function(next: HudSnapshot)
		applySnapshot(next)
	end)
	Remotes.getEvent("Notify").OnClientEvent:Connect(function(key: string, params: { [string]: any }?)
		notify(key, params)
	end)
	Remotes.getEvent("MarketChanged").OnClientEvent:Connect(onMarketChanged)
	Remotes.getEvent("LeaderboardChanged").OnClientEvent:Connect(function(payload: { [string]: any })
		Panels.fillBoard(panels.board, payload.server or {}, payload.global or {}, locale)
	end)
	Remotes.getEvent("LifeEvent").OnClientEvent:Connect(onLifeEvent)
	Remotes.getEvent("LoreEvent").OnClientEvent:Connect(onLoreEvent)
	Remotes.getEvent("OpaEvent").OnClientEvent:Connect(onOpaEvent)
	Remotes.getEvent("ShopState").OnClientEvent:Connect(function(state: { [string]: any })
		shopState = state
		if panels.shop.frame.Visible then
			Panels.fillShop(panels.shop, shopState, locale, function(kind: string, key: string)
				Remotes.getEvent("PromptPurchase"):FireServer(kind, key)
			end)
		end
	end)
	Remotes.getEvent("RequestState"):FireServer()
	-- rafraîchit le compte à rebours du marché
	task.spawn(function()
		while true do
			task.wait(1)
			if hud.market.TextTransparency < 0.5 then
				local current = string.match(hud.market.Text, "(%d+)s")
				local seconds = tonumber(current)
				if seconds and seconds > 0 then
					hud.market.Text = string.gsub(hud.market.Text, "%d+s", tostring(seconds - 1) .. "s", 1)
				end
			end
		end
	end)
end

function UIController.snapshot(): HudSnapshot
	return snapshot
end

function UIController.locale(): string
	return locale
end

return UIController
