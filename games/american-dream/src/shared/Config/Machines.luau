--!strict
-- Identifiants de manifest des machines et objets de chaque acte. Même table que forge/assetforge/manifest :
-- le générateur de manifest la lit pour rester cohérent. Chaque id absent du registre = greybox.

export type ActMachines = {
	dropper: string,
	upgrader: string,
	collector: string,
	conveyor: string,
	product: string,
	employee: string,
	decor: { string },
	productColor: { number },
}

local Machines = {}

Machines.Acts = {
	[1] = { dropper = "MSH_A1_DROP_LemonadeStand", upgrader = "MSH_A1_UPG_RustyJuicer", collector = "MSH_A1_COLL_CoinJar", conveyor = "MSH_A1_CONV_PlankTrestle", product = "MSH_GP_PRD_Lemon", employee = "CHAR_Vendor", decor = { "MSH_A1_DECO_Crate", "MSH_A1_DECO_Pallet" }, productColor = { 0.95, 0.85, 0.2 } },
	[2] = { dropper = "MSH_A2_DROP_VendingMachine", upgrader = "MSH_A2_UPG_CoffeeMachine", collector = "MSH_A2_COLL_CashRegister", conveyor = "MSH_A2_CONV_CheckoutBelt", product = "MSH_GP_PRD_Can", employee = "CHAR_Clerk", decor = { "MSH_A2_DECO_NeonOpen", "MSH_A2_DECO_SecurityCamera" }, productColor = { 0.8, 0.2, 0.2 } },
	[3] = { dropper = "MSH_A3_DROP_HydraulicPress", upgrader = "MSH_A3_UPG_RobotArm", collector = "MSH_A3_COLL_Palletizer", conveyor = "MSH_A3_CONV_RollerBelt", product = "MSH_GP_PRD_Crate", employee = "CHAR_Worker", decor = { "MSH_A3_DECO_SafetySign", "MSH_A3_DECO_Chimney" }, productColor = { 0.6, 0.45, 0.3 } },
	[4] = { dropper = "MSH_A4_DROP_ServerRack", upgrader = "MSH_A4_UPG_TradingScreen", collector = "MSH_A4_COLL_ExecutiveDesk", conveyor = "MSH_A4_CONV_PneumaticTube", product = "MSH_GP_PRD_DataIngot", employee = "CHAR_OfficeWorker", decor = { "MSH_A4_DECO_PlasticPlant", "MSH_A4_DECO_AbstractSculpture" }, productColor = { 0.3, 0.8, 0.95 } },
	[5] = { dropper = "MSH_A5_DROP_MoneyPrinter", upgrader = "MSH_A5_UPG_SatelliteDish", collector = "MSH_A5_COLL_Vault", conveyor = "MSH_A5_CONV_GoldRail", product = "MSH_GP_PRD_Briefcase", employee = "CHAR_Executive", decor = { "MSH_A5_DECO_MarbleStatue", "MSH_A5_DECO_TrophyCabinet" }, productColor = { 0.95, 0.8, 0.3 } },
} :: { [number]: ActMachines }

Machines.Gameplay = {
	button = "MSH_GP_ButtonBase",
	plotBorder = "MSH_GP_PlotBorder",
	lifeTotem = "MSH_GP_LifeTotem",
	exitDoor = "MSH_GP_ExitDoor",
	ticker = "MSH_GP_StockTicker",
	opaTerminal = "MSH_A4_UPG_TradingScreen",
}

function Machines.forAct(act: number): ActMachines
	return Machines.Acts[math.clamp(act, 1, 5)]
end

return Machines
