--!strict
-- Jeton visuels de l'interface. Mobile d'abord : tailles en offset pour les zones tactiles,
-- échelle pour le reste. La palette suit l'acte courant (froid -> néon saturé).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.WorldGen.Palette)

local Theme = {}

Theme.Background = Color3.fromRGB(12, 13, 18)
Theme.Panel = Color3.fromRGB(20, 22, 30)
Theme.PanelLight = Color3.fromRGB(30, 33, 44)
Theme.Text = Color3.fromRGB(240, 242, 248)
Theme.TextDim = Color3.fromRGB(150, 156, 172)
Theme.Positive = Color3.fromRGB(60, 210, 120)
Theme.Negative = Color3.fromRGB(235, 80, 80)
Theme.Warning = Color3.fromRGB(245, 180, 60)
Theme.Cash = Color3.fromRGB(245, 205, 80)
Theme.Life = Color3.fromRGB(90, 210, 160)
Theme.LifeLow = Color3.fromRGB(230, 90, 70)

-- Zones tactiles : 44 points minimum (recommandation d'accessibilité tactile)
Theme.TouchTarget = 44
Theme.Corner = UDim.new(0, 10)
Theme.Padding = 12
Theme.FontTitle = Enum.Font.GothamBlack
Theme.FontBody = Enum.Font.GothamMedium
Theme.FontNumber = Enum.Font.GothamBold

function Theme.accent(act: number): Color3
	local rgb = Palette.forAct(act).accent
	return Color3.new(rgb[1], rgb[2], rgb[3])
end

function Theme.corner(parent: Instance, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius and UDim.new(0, radius) or Theme.Corner
	corner.Parent = parent
	return corner
end

function Theme.stroke(parent: Instance, color: Color3, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1
	stroke.Transparency = 0.4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Theme.padding(parent: Instance, amount: number?): UIPadding
	local value = amount or Theme.Padding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, value)
	padding.PaddingBottom = UDim.new(0, value)
	padding.PaddingLeft = UDim.new(0, value)
	padding.PaddingRight = UDim.new(0, value)
	padding.Parent = parent
	return padding
end

function Theme.panel(name: string, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Theme.Panel
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	Theme.corner(frame)
	return frame
end

function Theme.label(name: string, text: string, size: UDim2, position: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.TextColor3 = Theme.Text
	label.Font = Theme.FontBody
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	return label
end

function Theme.button(name: string, text: string, size: UDim2, position: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.TextColor3 = Theme.Text
	button.Font = Theme.FontNumber
	button.TextScaled = true
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	Theme.corner(button)
	Theme.padding(button, 6)
	return button
end

return Theme
