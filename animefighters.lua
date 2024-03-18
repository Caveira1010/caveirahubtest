local OrionLib = loadstring(game:HttpGet(('https://raw.githubusercontent.com/shlexware/Orion/main/source')))()

local Window = OrionLib:MakeWindow({Name = "Title of the library", HidePremium = false, SaveConfig = true, ConfigFolder = "OrionTest"})

local FarmTab = Window:MakeTab({
    Name = "Autofarm",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

local plr = game.Players.LocalPlayer
local WorldCheck = game.workspace.Worlds[plr.World.Value]
local EnemyTable = {}
for i,v in pairs(WorldCheck.Enemies:GetChildren()) do
    if not table.find(EnemyTable, v.Name) then
        table.insert(EnemyTable, v.Name)
    end
end

FarmTab:AddDropdown({
    Name = "Select Enemy",
    Default = EnemyTable,
    Options = EnemyTable,
    Callback = function(Value)
        SelectEnemy = Value
    end    
})

FarmTab:AddToggle({
    Name = "Farm Selected Enemy",
    Default = false,
    Callback = function(t)
        StartFarm = t
    end    
})

task.spawn(function()
    while task.wait() do
        if StartFarm then
            pcall(function()
                for i,v in pairs(workspace.Pets:GetChildren()) do
                    if v.Data.Owner.Value == plr then
                        game:GetService("ReplicatedStorage").Bindable.SendPet:Fire(WorldCheck.Enemies[SelectEnemy], true, false)
                    end
                end
            end)
        end
    end
end)

FarmTab:AddToggle({
    Name = "TP to Enemy",
    Default = false,
    Callback = function(t)
        TPEnemy = t
    end    
})

task.spawn(function()
    while task.wait() do
        if TPEnemy then
            pcall(function()
               plr.Character.HumanoidRootPart.CFrame = WorldCheck.Enemies[SelectEnemy].HumanoidRootPart.CFrame
            end)
        end
    end
end)

FarmTab:AddToggle({
    Name = "Clicker DMG",
    Default = false,
    Callback = function(t)
        ClickerDamage = t
    end    
})

task.spawn(function()
    while task.wait() do
        if ClickerDamage then
            pcall(function()
                coroutine.wrap(function()
                game:GetService("ReplicatedStorage").Remote.ClickerDamage:FireServer()
                end)()
            end)
        end
    end
end)

FarmTab:AddToggle({
    Name = "Auto Collect Yen",
    Default = false,
    Callback = function(t)
        AutoPickYen = t
    end    
})

task.spawn(function()
    while task.wait() do
        if AutoPickYen then
            pcall(function()
                game:GetService("ReplicatedStorage").Remote.Pickup:FireServer("Gem", nil, "Yen")
                for i,v in pairs(game:GetService("Workspace").Effects.Yen:GetChildren()) do
                        v.CFrame = plr.Character.HumanoidRootPart.CFrame
                end
            end)
        end
    end
end)




OrionLib:Init()