--!strict
-- Panneaux plein écran : boutique Robux, journaux, classement, écran de Renaissance, confirmation de sortie.
-- Tous se ferment au même endroit, tous tiennent sur un écran de téléphone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local Lore = require(ReplicatedStorage.Shared.Config.Lore)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Theme = require(script.Parent.Theme)

local Panels = {}

export type Panel = {
	frame: Frame,
	content: ScrollingFrame,
	title: TextLabel,
	close: TextButton,
}

export type Handle = {
	gui: ScreenGui,
	shop: Panel,
	journals: Panel,
	board: Panel,
	overlay: Frame,
	overlayTitle: TextLabel,
	overlayBody: TextLabel,
	overlayYes: TextButton,
	overlayNo: TextButton,
}

local function makePanel(name: string, titleKey: string, locale: string, parent: Instance): Panel
	local frame = Theme.panel(name, UDim2.fromScale(0.9, 0.82), UDim2.fromScale(0.05, 0.09))
	frame.Visible = false
	frame.BackgroundTransparency = 0.02
	frame.SizeConstraint = Enum.SizeConstraint.RelativeXY
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1.35
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.AspectType = Enum.AspectType.ScaleWithParentSize
	ratio.Parent = frame
	frame.Parent = parent

	local title = Theme.label("Title", Strings.get(titleKey, locale), UDim2.new(1, -120, 0, 34), UDim2.fromOffset(16, 12))
	title.Font = Theme.FontTitle
	title.Parent = frame

	local close = Theme.button("Close", Strings.get("hud.close", locale), UDim2.fromOffset(96, Theme.TouchTarget), UDim2.new(1, -108, 0, 10), Theme.PanelLight)
	close.Parent = frame

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -24, 1, -70)
	content.Position = UDim2.fromOffset(12, 60)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 5
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	return { frame = frame, content = content, title = title, close = close }
end

function Panels.build(locale: string): Handle
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "Panels"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 20
	gui.Enabled = true

	local shop = makePanel("Shop", "shop.title", locale, gui)
	local journals = makePanel("Journals", "hud.journals", locale, gui)
	local board = makePanel("Board", "board.title", locale, gui)

	-- Superposition : burnout, renaissance, confirmation de sortie
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.Parent = gui

	local overlayTitle = Theme.label("Title", "", UDim2.new(0.8, 0, 0, 64), UDim2.fromScale(0.1, 0.3))
	overlayTitle.TextXAlignment = Enum.TextXAlignment.Center
	overlayTitle.Font = Theme.FontTitle
	overlayTitle.TextTransparency = 1
	overlayTitle.Parent = overlay

	local overlayBody = Instance.new("TextLabel")
	overlayBody.Name = "Body"
	overlayBody.Size = UDim2.new(0.7, 0, 0, 96)
	overlayBody.Position = UDim2.fromScale(0.15, 0.45)
	overlayBody.BackgroundTransparency = 1
	overlayBody.TextColor3 = Theme.Text
	overlayBody.Font = Theme.FontBody
	overlayBody.TextSize = 20
	overlayBody.TextWrapped = true
	overlayBody.TextTransparency = 1
	overlayBody.Text = ""
	overlayBody.Parent = overlay

	local overlayYes = Theme.button("Yes", "", UDim2.fromOffset(190, Theme.TouchTarget + 6), UDim2.new(0.5, -200, 0.66, 0), Theme.Negative)
	overlayYes.Visible = false
	overlayYes.Parent = overlay
	local overlayNo = Theme.button("No", "", UDim2.fromOffset(190, Theme.TouchTarget + 6), UDim2.new(0.5, 10, 0.66, 0), Theme.PanelLight)
	overlayNo.Visible = false
	overlayNo.Parent = overlay

	gui.Parent = player:WaitForChild("PlayerGui")

	return {
		gui = gui,
		shop = shop,
		journals = journals,
		board = board,
		overlay = overlay,
		overlayTitle = overlayTitle,
		overlayBody = overlayBody,
		overlayYes = overlayYes,
		overlayNo = overlayNo,
	}
end

local function row(parent: Instance, order: number, height: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Row" .. order
	frame.Size = UDim2.new(1, -8, 0, height)
	frame.BackgroundColor3 = Theme.PanelLight
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	Theme.corner(frame, 8)
	frame.Parent = parent
	return frame
end

-- Boutique Robux : chaque ligne dit exactement ce qu'elle donne, rien n'expire, rien n'est aléatoire.
function Panels.fillShop(panel: Panel, state: { [string]: any }, locale: string, onBuy: (kind: string, key: string) -> ())
	for _, child in panel.content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local honest = Instance.new("TextLabel")
	honest.Name = "Honest"
	honest.Size = UDim2.new(1, -8, 0, 36)
	honest.BackgroundTransparency = 1
	honest.TextColor3 = Theme.TextDim
	honest.Font = Theme.FontBody
	honest.TextSize = 15
	honest.TextWrapped = true
	honest.TextXAlignment = Enum.TextXAlignment.Left
	honest.LayoutOrder = 0
	honest.Text = Strings.get("shop.honest", locale)
	honest.Parent = panel.content

	local order = 1
	local passes: { { [string]: any } } = if type(state.passes) == "table" then state.passes else {}
	for _, entry in passes do
		local pass = Monetization.gamepass(entry.key)
		if pass == nil then
			continue
		end
		local frame = row(panel.content, order, 78)
		order += 1
		local name = Theme.label("Name", Strings.get(pass.nameKey, locale), UDim2.new(1, -130, 0, 24), UDim2.fromOffset(10, 6))
		name.Font = Theme.FontNumber
		name.Parent = frame
		local desc = Instance.new("TextLabel")
		desc.Name = "Desc"
		desc.Size = UDim2.new(1, -130, 0, 38)
		desc.Position = UDim2.fromOffset(10, 32)
		desc.BackgroundTransparency = 1
		desc.TextColor3 = Theme.TextDim
		desc.Font = Theme.FontBody
		desc.TextSize = 14
		desc.TextWrapped = true
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.Text = Strings.get(pass.descriptionKey, locale)
		desc.Parent = frame
		local owned = entry.owned == true
		local available = (entry.id :: number) > 0
		local button = Theme.button("Buy", owned and Strings.get("hud.owned", locale) or (available and (tostring(entry.robux) .. " R$") or Strings.get("shop.unavailable", locale)), UDim2.fromOffset(110, Theme.TouchTarget), UDim2.new(1, -120, 0, 17), owned and Theme.Positive or (available and Theme.Cash or Theme.PanelLight))
		button.TextColor3 = owned and Theme.Text or (available and Color3.new(0.1, 0.1, 0.1) or Theme.TextDim)
		button.Active = not owned and available
		button.Parent = frame
		if not owned and available then
			button.Activated:Connect(function()
				onBuy("pass", entry.key)
			end)
		end
	end

	local products: { { [string]: any } } = if type(state.products) == "table" then state.products else {}
	for _, entry in products do
		local product = Monetization.devProduct(entry.key)
		if product == nil then
			continue
		end
		local frame = row(panel.content, order, 68)
		order += 1
		local name = Theme.label("Name", Strings.get(product.nameKey, locale), UDim2.new(1, -130, 0, 24), UDim2.fromOffset(10, 6))
		name.Font = Theme.FontNumber
		name.Parent = frame
		local amount = Theme.label("Amount", Strings.get("shop.pack.note", locale, { amount = Format.money(entry.amount or 0) }), UDim2.new(1, -130, 0, 24), UDim2.fromOffset(10, 34))
		amount.TextColor3 = Theme.Cash
		amount.TextSize = 15
		amount.TextScaled = false
		amount.Parent = frame
		local available = (entry.id :: number) > 0
		local button = Theme.button("Buy", available and (tostring(entry.robux) .. " R$") or Strings.get("shop.unavailable", locale), UDim2.fromOffset(110, Theme.TouchTarget), UDim2.new(1, -120, 0, 12), available and Theme.Cash or Theme.PanelLight)
		button.TextColor3 = available and Color3.new(0.1, 0.1, 0.1) or Theme.TextDim
		button.Active = available
		button.Parent = frame
		if available then
			button.Activated:Connect(function()
				onBuy("product", entry.key)
			end)
		end
	end
end

function Panels.fillJournals(panel: Panel, owned: { [string]: boolean }, locale: string)
	for _, child in panel.content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local count = 0
	for _ in owned do
		count += 1
	end
	panel.title.Text = Strings.get("journals.title", locale, { count = count, total = #Lore.Journals })
	for index, journal in Lore.Journals do
		local has = owned[journal.id] == true
		local frame = row(panel.content, index, has and 96 or 44)
		local title = Theme.label("Title", has and Strings.get(journal.titleKey, locale) or ("???  (" .. Strings.get("act." .. journal.act .. ".name", locale) .. ")"), UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 6))
		title.Font = Theme.FontNumber
		title.TextColor3 = has and Theme.Text or Theme.TextDim
		title.TextScaled = false
		title.TextSize = 16
		title.TextTruncate = Enum.TextTruncate.AtEnd
		title.Parent = frame
		if has then
			local body = Instance.new("TextLabel")
			body.Name = "Body"
			body.Size = UDim2.new(1, -20, 0, 60)
			body.Position = UDim2.fromOffset(10, 32)
			body.BackgroundTransparency = 1
			body.TextColor3 = Theme.TextDim
			body.Font = Theme.FontBody
			body.TextSize = 14
			body.TextWrapped = true
			body.TextXAlignment = Enum.TextXAlignment.Left
			body.TextYAlignment = Enum.TextYAlignment.Top
			body.Text = Strings.get(journal.bodyKey, locale)
			body.Parent = frame
		end
	end
end

type BoardRow = { userId: number, name: string, worth: number, act: number, renaissances: number }

function Panels.fillBoard(panel: Panel, serverRows: { BoardRow }, globalRows: { BoardRow }, locale: string)
	for _, child in panel.content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	local function section(titleText: string, rows: { BoardRow })
		order += 1
		local header = Instance.new("TextLabel")
		header.Name = "Header" .. order
		header.Size = UDim2.new(1, -8, 0, 26)
		header.BackgroundTransparency = 1
		header.TextColor3 = Theme.TextDim
		header.Font = Theme.FontNumber
		header.TextSize = 15
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.LayoutOrder = order
		header.Text = titleText
		header.Parent = panel.content
		if #rows == 0 then
			order += 1
			local empty = Theme.label("Empty", Strings.get("board.empty", locale), UDim2.new(1, -8, 0, 24), UDim2.new())
			empty.LayoutOrder = order
			empty.TextColor3 = Theme.TextDim
			empty.TextScaled = false
			empty.TextSize = 14
			empty.Parent = panel.content
			return
		end
		for rank, entry in rows do
			order += 1
			local frame = row(panel.content, order, 34)
			local label = Theme.label("Row", Strings.get("board.row", locale, { rank = rank, name = entry.name, worth = Format.money(entry.worth) }), UDim2.new(1, -20, 1, 0), UDim2.fromOffset(10, 0))
			label.TextScaled = false
			label.TextSize = 15
			label.Font = Enum.Font.Code
			label.TextColor3 = rank <= 3 and Theme.Cash or Theme.Text
			label.Parent = frame
		end
	end
	section(Strings.get("board.title", locale), serverRows)
	if #globalRows > 0 then
		section(Strings.get("hud.index", locale) .. " (global)", globalRows)
	end
end

return Panels
