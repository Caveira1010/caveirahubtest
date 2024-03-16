local HS = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local P = game:GetService("Players")
local VU = game:GetService("VirtualUser")
local VIM = game:GetService("VirtualInputManager")
local RunS = game:GetService("RunService")
local TS = game:GetService("TweenService")

local player = P.LocalPlayer
local originalCameraZoomDistance = player.CameraMaxZoomDistance
local character = player.Character
local staterPlayerScriptsFolder = player.PlayerScripts.StarterPlayerScriptsFolder

local REMOTE = RS.Remote
local BINDABLE = RS.Bindable


local MAX_SUMMON = 20
local MAX_EQUIPPED = 9
local MAX_ROOM = 50
local KILLING_METEOR = false
local KILLING_GIFT = false
local MAX_TIMES_TO_CHECK_FOR_METEOR = 30
local WAIT_BEFORE_GETTING_ENEMIES = 1
local NUM_BOSS_ATTACKERS = 24
local HP_TO_SWAP_AT = 1e17
local HP_THRESH_HOLD = 1e16
local AUTO_EQUIP_TIME = 300
local CURRENT_TRIAL = ""

local statCalc = require(RS.ModuleScripts.StatCalc)
local numToString = require(RS.ModuleScripts.NumToString)
local petStats = require(RS.ModuleScripts.PetStats)
local store = require(RS.ModuleScripts.LocalSulleyStore)
local enemyStats = require(RS.ModuleScripts.EnemyStats)
local worldData = require(RS.ModuleScripts.WorldData)
local configValues = require(RS.ModuleScripts.ConfigValues)
local passiveStats = require(RS.ModuleScripts.PassiveStats)
local eggStats = require(RS.ModuleScripts.EggStats)
local enemyDamagedEffect = require(staterPlayerScriptsFolder.LocalPetHandler.EnemyDamagedEffect)

local data = store.GetStoreProxy("GameData")
local IGNORED_RARITIES = {"Secret", "Raid", "Divine"}
local IGNORED_WORLDS = {"Raid", "Tower", "Titan", "Christmas"}
local IGNORED_METEOR_FARM_WORLDS = {"Tower", "Raid"}
local TEMP_METEOR_FARM_IGNORE = {}
local mobs = {}
local eggData = {}
local sentDebounce = {}
local raidWorlds = {}
local petsToFuse = {}
local TRIAL_TARGET = {
    Weakest = false,
    Strongest = false,
}
local originalEquippedPets
local originalPetsTab = {}
local eggDisplayNameToNameLookUp = {}
local passivesToKeep = {}
local defenseWorlds = {}
local damagedEffectFunctions = {
    [true] = function()
        return true
    end,
    [false] = enemyDamagedEffect.DoEffect,
}

local PASSIVE_FORMAT = "%s (%s)"
local FIGHTER_FORMAT = "Pet ID: %s | Display Name: %s"
local PET_TEXT_FORMAT = "%s (%s) | UID: %s | Level %s"
local selectedFuse
local selectedMob
local selectedDefenseWorld

local towerFarm
local stopTrial
local roomToStopAt = 1
local chestIgnoreRoom = 1
local goldSwap
local easyTrial
local mediumTrial
local hardTrial
local ultimateTrial

local autoDamage
local autoCollect
local autoUltSkip
local reEquippingPets = false
local equippingTeam = false

local bsec1
local farmAllToggle

local hidePets
local fighterFuseDropDown
local PlayerGui = player.PlayerGui
local DEFENSE_RESULT = PlayerGui.TitanGui.DefenseResult
local RAID_RESULT = PlayerGui.RaidGui.RaidResults

local playerPos = character.HumanoidRootPart.CFrame
local WORLD = player.World.Value

--To reference the countdown in trial
REMOTE.AttemptTravel:InvokeServer("Tower")
character.HumanoidRootPart.CFrame = WS.Worlds.Tower.Spawns.SpawnLocation.CFrame
WS.Worlds.Tower.Water.CanCollide = true

REMOTE.AttemptTravel:InvokeServer(WORLD)
character.HumanoidRootPart.CFrame = playerPos

local easyTrialTime = WS.Worlds.Tower.Door1.Countdown.SurfaceGui.Background.Time
local mediumTrialTime = WS.Worlds.Tower.Door2.Countdown.SurfaceGui.Background.Time
local hardTrialTime = WS.Worlds.Tower.Door3.Countdown.SurfaceGui.Background.Time
local ultimateTrialTime = WS.Worlds.Tower.Door4.Countdown.SurfaceGui.Background.Time

local towerTime = PlayerGui.MainGui.TowerTimer.Main.Time
local yesButton = PlayerGui.MainGui.RaidTransport.Main.Yes
local floorNumberText = PlayerGui.MainGui.TowerTimer.CurrentFloor.Value


--functions
do
    function antiAFK()
        player.Idled:Connect(function()
            VU:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
            task.wait(1)
            VU:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
        end)

        warn("ANTI-AFK: ON")
    end

    function getPets()
        return data:GetData("Pets")
    end

    function getPetWithUID(uid)
        local pets = getPets()
        for _, pet in pairs(pets) do
            if pet.UID == uid then
                return pet
            end
        end
    end

    function getEquippedPets()
        local equipped = {}
        for _, obj in ipairs(player.Pets:GetChildren()) do
            local pet = obj.Value
            local petTable = getPetWithUID(pet.Data.UID.Value)
            if petTable then
                table.insert(equipped, petTable)
            end
        end

        return equipped
    end

    function getEquippedPetsDict()
        local equipped = {}
        for _, obj in ipairs(player.Pets:GetChildren()) do
            local pet = obj.Value
            equipped[pet.Data.UID.Value] = true
        end

        return equipped
    end

    function getFuseablePets()
        local pets = getPets()
        local fuseable = {}
        local equippedPets = getEquippedPetsDict()

        for _, pet in pairs(pets) do
            local id = pet.PetId
            local canFuse = false
            local expression = pet.Passive and (pet.Passive == "Luck3" or passivesToKeep[pet.Passive])

            if not expression then
                if not equippedPets[pet.UID] then
                    local rarity = petStats[id].Rarity

                    if id ~= "VIP" and rarity ~= "Secret" and rarity ~= "Divine" and rarity ~= "Special" then
                        if not table.find(IGNORED_RARITIES, rarity) then
                            canFuse = true                        
                        elseif rarity == "Raid" and not pet.Shiny then
                            canFuse = true
                        end
                    end

                    if canFuse then
                        table.insert(fuseable, pet.UID)
                    end
                end
            end
        end

        return fuseable
    end

    function getMobs()
        for _, enemy in ipairs(WS.Worlds[player.World.Value].Enemies:GetChildren()) do
            if not table.find(mobs, enemy.DisplayName.Value) then
                table.insert(mobs, enemy.DisplayName.Value)
            end
        end

        return mobs
    end

    function getEggStats()
        for eggName, info in pairs(eggStats) do
            if info.Currency ~= "Robux" and not info.Hidden then
                local eggModel = WS.Worlds:FindFirstChild(eggName, true)
                local s = string.format("%s (%s)", info.DisplayName, eggName)
                table.insert(eggData, s)
                eggDisplayNameToNameLookUp[s] = eggName
            end
        end

        return eggData
    end

    function getPetTextFormat(pet)
        local displayName = petStats[pet.PetId].DisplayName or player.Name --VIP character
        return string.format(PET_TEXT_FORMAT, pet.CustomName, displayName, pet.UID, pet.Level)
    end

    function getPetsToFuseInto()
        table.clear(petsToFuse)

        local pets = getPets()

        for _, pet in pairs(pets) do
            table.insert(petsToFuse, getPetTextFormat(pet))
        end

        return petsToFuse
    end

    function getAllPetsFormatted()
        local tab = {}

        for petId, info in pairs(petStats) do
            local displayName = info.DisplayName or player.Name
            table.insert(tab, string.format(FIGHTER_FORMAT, petId, displayName))
        end

        return tab
    end

    function teleportTo(world)
        local response = REMOTE.AttemptTravel:InvokeServer(world)

        if response then
            setTargetAll(false)
            task.wait(0.1)
            --Stop character from falling through the floor
            character.HumanoidRootPart.CFrame = WS.Worlds[world].Spawns.SpawnLocation.CFrame + Vector3.new(0, 15, 0)
        end
    end

    function getTarget(name, world)
        if not table.find(IGNORED_WORLDS, world) then
            local enemies = WS.Worlds[world].Enemies
            for _, enemy in ipairs(enemies:GetChildren()) do
                if enemy:FindFirstChild("DisplayName") and enemy.DisplayName.Value == name and enemy:FindFirstChild("HumanoidRootPart") then
                    return enemy
                end
            end
        end
    end

    function initHiddenUnitsFolder()
        if not RS:FindFirstChild("HIDDEN_UNITS") then
            local folder = Instance.new("Folder")
            folder.Name = "HIDDEN_UNITS"
            folder.Parent = RS
        end

        P.PlayerRemoving:Connect(function(plr)
            for _, pet in ipairs(RS.HIDDEN_UNITS:GetChildren()) do
                local data = pet:FindFirstChild("Data")
                if data and data:FindFirstChild("Owner") then
                    if data.Owner.Value == plr then
                        pet:Destroy()
                    end
                end
            end
        end)
    end

    function onCharacterAdded(char)
        character = char
    end

    function unequipPets()
        local uids = {}

        for _, pet in ipairs(player.Pets:GetChildren()) do
            local UID = pet.Value.Data.UID.Value
            table.insert(uids, UID)
            REMOTE.ManagePet:FireServer(UID, "equip")
        end

        return uids
    end

    function equipPets(uids)
        for i, uid in ipairs(uids) do
            REMOTE.ManagePet:FireServer(uid, "Equip", i)
        end
    end

    function reEquipPets()
        while equippingTeam do
            task.wait()
        end

        reEquippingPets = true
        local uids = unequipPets()
        task.wait()
        equipPets(uids)
        reEquippingPets = false
    end

    function setPetSpeed(speed)
        for _, tab in pairs(passiveStats) do
            if tab.Effects then
                tab.Effects.Speed = speed
            end
        end

        reEquipPets()
    end

    function init()
        getMobs()
        getPetsToFuseInto()
        getEggStats()
        initHiddenUnitsFolder()
        antiAFK()

        player.CharacterAdded:Connect(onCharacterAdded)
        warn("Init completed")
    end

    --tween
    function toTarget(pos, targetPos, targetCFrame)
        local info = TweenInfo.new((targetPos - pos).Magnitude / tweenS, Enum.EasingStyle.Linear)
        return TS:Create(character.HumanoidRootPart, info, {CFrame = targetCFrame})
    end

    --retreat
    function retreat()
        VIM:SendKeyEvent(true,"R",false,game)
    end

    function movePetsToPlayer()
        for _, pet in ipairs(player.Pets:GetChildren()) do
            local targetPart = pet.Value:FindFirstChild("TargetPart")
            local humanoidRootPart = pet.Value:FindFirstChild("HumanoidRootPart")

            if targetPart and humanoidRootPart then
                targetPart.CFrame = character.HumanoidRootPart.CFrame
                humanoidRootPart.CFrame = character.HumanoidRootPart.CFrame
            end
        end
    end

    function movePetsToPos(cframe)
        for _, pet in ipairs(player.Pets:GetChildren()) do
            local targetPart = pet.Value:FindFirstChild("TargetPart")
            local humanoidRootPart = pet.Value:FindFirstChild("HumanoidRootPart")

            if targetPart and humanoidRootPart then
                targetPart.CFrame = cframe
                humanoidRootPart.CFrame = cframe
            end
        end
    end

    function sendPet(enemy)
        if sentDebounce[enemy] then return end
        sentDebounce[enemy] = true

        local currWorld = player.World.Value
        local AMOUNT_TO_MOVE_BACK = 10
        local charPos = player.Character.HumanoidRootPart.CFrame
        local x = 0
        local petTab = {}
        local models = {}

        for _, objValue in ipairs(player.Pets:GetChildren()) do
            local p = objValue.Value
            local pet = getPetWithUID(p.Data.UID.Value)
            table.insert(petTab, pet)
        end

        table.sort(petTab, function(pet1, pet2)
            return pet1.Level > pet2.Level
        end)

        for _, pet in pairs(petTab) do
            for _, objValue in ipairs(player.Pets:GetChildren()) do
                model = objValue.Value

                if model.Data.UID.Value == pet.UID then
                    table.insert(models, model)
                    break
                end
            end
        end

        for _, model in ipairs(models) do
            local cframe = charPos + Vector3.new(x, 0, 0)
            local targetPart = model:FindFirstChild("TargetPart")
            local hrp = model:FindFirstChild("HumanoidRootPart")

            if targetPart and hrp then
                targetPart.CFrame = cframe
                hrp.CFrame = cframe
                x -= AMOUNT_TO_MOVE_BACK
            end
        end

        table.clear(petTab)
        table.clear(models)
        petTab = nil
        models = nil

        repeat
            if enemy:FindFirstChild("Attackers") and enemy:FindFirstChild("AnimationController") then
                BINDABLE.SendPet:Fire(enemy, true)
            end

            task.wait()
        until _G.disabled
        or enemy:FindFirstChild("Attackers") == nil
        or not enemy:IsDescendantOf(workspace)
        or enemy:FindFirstChild("AnimationController") == nil
        or enemy:FindFirstChild("Health") == nil
        or player.World.Value ~= currWorld
        or enemy.Health.Value <= 0
        or (not towerFarm)

        sentDebounce[enemy] = nil
    end

    function equipTeam(teamTab)
        equippingTeam = false
        task.wait(1)
        unequipPets()
        task.wait(1)
        equipPets(teamTab)
        equippingTeam = false
    end

    function handleAutoTrial(enemies, enemy)
        if player.World.Value ~= "Tower" then return end

        character.HumanoidRootPart.CFrame = enemy.HumanoidRootPart.CFrame

        movePetsToPlayer()
        task.wait()

        local maxHealth = enemy:FindFirstChild("MaxHealth") and enemy.MaxHealth.Value
        local health = enemy:FindFirstChild("Health") and enemy.Health
        local hpToSwapAt = hpThreshold or HP_THRESH_HOLD
        local uids
        local conn
        local debounce = false
        local IS_CHEST = string.find(string.lower(enemy.Name), "chest") ~= nil
        local IS_BOSS = enemyStats[enemy.Name]["Boss"] == true or (enemy:FindFirstChild("Attackers") and #(enemy.Attackers:GetChildren()) == NUM_BOSS_ATTACKERS)

        if goldSwap and IS_BOSS and not IS_CHEST and health ~= nil and maxHealth ~= nil and maxHealth >= HP_TO_SWAP_AT then
            conn = health:GetPropertyChangedSignal("Value"):Connect(function()
                local hp = health.Value

                if not debounce and hp <= hpToSwapAt then
                    debounce = true

                    while reEquippingPets do --so it equips the right pets
                        task.wait()
                    end

                    local goldUnits = {}
                    local toEquip = {}
                    local pets = getPets()
                    local equippedPets = getEquippedPets()

                    table.sort(equippedPets, function(pet1, pet2)
                        return pet1.Level > pet2.Level
                    end)

                    uids = unequipPets()

                    for _, pet in pairs(pets) do
                        if pet.Passive and pet.Passive == "Gold" then
                            table.insert(goldUnits, pet)
                        end
                    end

                    table.sort(goldUnits, function(pet1, pet2)
                        return pet1.Level > pet2.Level
                    end)

                    for _, pet in pairs(goldUnits) do
                        table.insert(toEquip, pet.UID)
                    end

                    equipPets(toEquip)

                    local areSpacesLeft = #toEquip < MAX_EQUIPPED

                    if areSpacesLeft then
                        local spacesLeft = math.abs(MAX_EQUIPPED - #toEquip)

                        for i = 1, spacesLeft do
                            local index = (MAX_EQUIPPED - i) + 1
                            --have to do this here since equipPets would start the index from 1
                            REMOTE.ManagePet:FireServer(equippedPets[i].UID, "Equip", index)
                        end
                    end

                    table.clear(toEquip)
                    table.clear(pets)
                    table.clear(equippedPets)
                    table.clear(goldUnits)

                    toEquip = nil
                    pets = nil
                    equippedPets = nil
                    goldUnits = nil
                end
            end)
        end

        repeat
            if enemy:FindFirstChild("Attackers") and enemy:FindFirstChild("AnimationController") then
                sendPet(enemy)
            end

            task.wait()
        until _G.disabled
        or player.World.Value ~= "Tower"
        or enemy:FindFirstChild("HumanoidRootPart") == nil
        or enemy:FindFirstChild("AnimationController") == nil
        or enemy:FindFirstChild("Attackers") == nil
        or (not towerFarm)
        or #(enemies:GetChildren()) == 0
        or not enemy:IsDescendantOf(workspace)

        retreat()

        if conn ~= nil then
            conn:Disconnect()
            conn = nil
        end

        if uids ~= nil then
            equipTeam(uids)
            table.clear(uids)
            uids = nil
        end
    end

    function getNewPetToFuse(currentMaxUID)
        local pets = getPets()
        local currentSelectedPet = getPetWithUID(currentMaxUID)
        local incubatorData = data:GetData("IncubatorData")
        local incubatorUnits = {}

        for _, tab in pairs(incubatorData) do
            incubatorUnits[tab.UID] = true
        end

        if currentSelectedPet then
            local nextHighestLevel = -math.huge
            local nextHighestPet

            for _, pet in pairs(pets) do
                if pet.UID ~= currentMaxUID
                    and pet.Level < configValues.MaxLevel
                    and pet.Level > nextHighestLevel
                    and not incubatorUnits[pet.UID] then

                    nextHighestLevel = pet.Level
                    nextHighestPet = pet
                end
            end

            return nextHighestPet
        end

        table.clear(incubatorUnits)
        incubatorUnits = nil
    end

    function tp(world, pos)
        if world ~= nil then
            player.World.Value = world
            REMOTE.AttemptTravel:InvokeServer(world)
            character.HumanoidRootPart.CFrame = pos

            if oldFarmAllState then
                setTargetAll(true)
                oldFarmAllState = nil
            end
        end
    end

    function saveFarmAllState()
        if farmAllMobs then
            oldFarmAllState = farmAllMobs
            setTargetAll(false)
        end
    end

    function tpToCurrentDefense()
        local spawn = WS.Worlds.Titan.Spawns:FindFirstChild("Spawn")

        if spawn then
            saveFarmAllState()
            character.HumanoidRootPart.CFrame = spawn.CFrame + Vector3.new(0, 5, 0)
        end
    end

    function getPassives(passiveType)
        local tab = {}

        for passive, info in pairs(passiveStats) do
            info.__key = passive

            if not info.Hidden then
                if passiveType then
                    if info.Effects and info.Effects[passiveType] ~= nil then
                        local s = string.format(PASSIVE_FORMAT, info.DisplayName, passive)
                        table.insert(tab, s)
                    end
                else
                    table.insert(tab, info)
                end
            end
        end

        if not passiveType then
            table.sort(tab, function(a, b)
                return a.DisplayName < b.DisplayName
            end)
        end

        return tab
    end
end






local OrionLib = loadstring(game:HttpGet(('https://raw.githubusercontent.com/shlexware/Orion/main/source')))()
local Window = OrionLib:MakeWindow({Name = "Title of the library", HidePremium = false, SaveConfig = true, ConfigFolder = "OrionTest"})



local mainTab = Window:MakeTab({
	Name = "autofarm",
	Icon = "rbxassetid://4483345998",
	PremiumOnly = false
})


mainTab:AddToggle({
	Name = "auto farm selected",
	Default = false,
	Callback = function(Value)
		autofarm1 = Value
	end    
})

mainTab:AddToggle({
	Name = "select enemy",
	Default = false,
	Callback = function(value)
        selectedMob = value
	end    
})

mainTab:AddButton({
	Name = "refresh enemy",
	Callback = function()
        selectedMob = defalt
        mobs = {}
        mobs = getMobs()
        mainDropdown:Refresh(mobsDropdown,"Updated mobs", mobs)
  	end    
})

mainTab:AddButton({
	Name = "Button!",
	Callback = function()
        savedPos = character.HumanoidRootPart.CFrame
        currentWorld = player.World.Value
        OrionLib:MakeNotification({
            Name = "Spawn Set",
            Content = "Location saved.",
            Image = "rbxassetid://4483345998",
            Time = 5
        })
  	end    
})



mainTab:AddToggle({
	Name = "auto farm all",
	Default = false,
	Callback = function(value)
        farmAllMobs = value
        setTargetAll(value)
	end    
})



mainTab:AddToggle({
	Name = "autoclick",
	Default = false,
	Callback = function(value)
		autoDamage = value
	end    
})


mainTab:AddToggle({
	Name = "auto collect",
	Default = false,
	Callback = function(value)
		autoCollect = value
	end    
})



--get selected mob since this library is glitchy
mobsDropdown.Search.TextBox:GetPropertyChangedSignal("Text"):Connect(function()
    selectedMob = mobsDropdown.Search.TextBox.Text
end)
end

OrionLib:Init()