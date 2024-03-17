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
local enemyStats = require(RS.ModuleScripts.EnemyStats)
local worldData = require(RS.ModuleScripts.WorldData)
local configValues = require(RS.ModuleScripts.ConfigValues)
local passiveStats = require(RS.ModuleScripts.PassiveStats)
local eggStats = require(RS.ModuleScripts.EggStats)
local enemyDamagedEffect = require(staterPlayerScriptsFolder.LocalPetHandler.EnemyDamagedEffect)


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

function setTargetAll(state)
    if state then
        clone = clone or character:Clone()
        clone.Parent = clone.Parent == nil and WS.Characters or nil
        player.Character = clone
        originalChar.Name = originalChar.Name.."_"
        character = clone

        controlModule:OnCharacterAdded(originalChar)
    elseif clone ~= nil then
        originalChar.Name = clone.Name
        clone.Parent = nil
        player.Character = originalChar
        character = originalChar
        controlModule:OnCharacterAdded(originalChar)
    end



mainTab:AddToggle({
	Name = "auto farm selected",
	Default = false,
	Callback = function(Value)
		autofarm1 = Value
	end    
})


local mobsDropdown = mainTab:AddDropdown({
            Name = "select enemy",
            Default = mobs,
            Options = mobs,
            Callback = function(value)
        selectedMob = value
	end
})

mainTab:AddButton({
	Name = "refresh enemy",
	Callback = function()
        selectedMob = false
        mobs = {}
        mobs = getMobs()
        mainDropdown:Refresh(mobsDropdown,"Updated mobs", mobs)
  	end    
})

mainTab:AddButton({
	Name = "set position",
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







































--script
do
    --auto re-equip pets
    do
        task.spawn(function()
            while not _G.disabled do
                if autoReEquipPets then
                    reEquipPets()
                    task.wait(AUTO_EQUIP_TIME)
                end

                task.wait(1)
            end

            autoReEquipPets = nil
        end)
    end

    --auto meteor farm
    do
        task.spawn(function()
            while not _G.disabled do
                if farmMeteors then
                    if not table.find(IGNORED_METEOR_FARM_WORLDS, player.World.Value) and not KILLING_GIFT then
                        local oldWorld = player.World.Value

                        for _, world in ipairs(WS.Worlds:GetChildren()) do
                            local enemies = world:FindFirstChild("Enemies")
                            local fruitMeteor = nil

                            if enemies then
                               fruitMeteor = enemies:FindFirstChild("FruitMeteor")
                            end

                            if fruitMeteor and not table.find(TEMP_METEOR_FARM_IGNORE, world.Name) then
                                saveFarmAllState()

                                KILLING_METEOR = true
                                teleportTo(world.Name)

                                task.wait(1)

                                local fruitMeteorHRP = fruitMeteor:FindFirstChild("HumanoidRootPart")
                                local count = 1

                                while fruitMeteorHRP == nil
                                and not table.find(IGNORED_WORLDS, player.World.Value)
                                and farmMeteors
                                and count <= MAX_TIMES_TO_CHECK_FOR_METEOR
                                and not _G.disabled do
                                    for _, spawn in ipairs(world.EnemySpawners:GetChildren()) do
                                        if fruitMeteorHRP then
                                            break
                                        end

                                        character.HumanoidRootPart.CFrame = spawn.CFrame
                                        fruitMeteorHRP = fruitMeteor:FindFirstChild("HumanoidRootPart")
                                    end

                                    count += 1
                                    task.wait(0.1)
                                end

                                if fruitMeteorHRP then
                                    character.HumanoidRootPart.CFrame = fruitMeteorHRP.CFrame
                                    movePetsToPlayer()
                                    task.wait()

                                    repeat
                                        if fruitMeteor:FindFirstChild("Attackers") then
                                            BINDABLE.SendPet:Fire(fruitMeteor, true)
                                        end
                                        task.wait()
                                    until _G.disabled
                                    or enemies:FindFirstChild("FruitMeteor") == nil
                                    or fruitMeteor:FindFirstChild("Attackers") == nil
                                    or table.find(IGNORED_WORLDS, player.World.Value)
                                    or not farmMeteors

                                    retreat()

                                    if oldWorld ~= "Titan" then --will get tp'd back by auto tp to defense
                                        tp(currentWorld, savedPos)
                                    end
                                else
                                    --glitched meteor spawn or something
                                    table.insert(TEMP_METEOR_FARM_IGNORE, world.Name)

                                    task.delay(300, function()
                                        local index = table.find(TEMP_METEOR_FARM_IGNORE, world.Name)

                                        if index then
                                            table.remove(TEMP_METEOR_FARM_IGNORE, index)
                                        end
                                    end)

                                    if oldWorld ~= "Titan" then --will get tp'd back by auto tp to defense
                                        tp(currentWorld, savedPos)
                                    end
                                end

                                KILLING_METEOR = false
                            end
                        end
                    end
                end

                task.wait(1)
            end

            farmMeteors = nil
        end)
    end

    --util
    do
        --auto ult skip
        task.spawn(function()
            while not _G.disabled do
                if autoUltSkip then
                    for _, pet in ipairs(player.Pets:GetChildren()) do
                        task.spawn(function()
                            REMOTE.PetAttack:FireServer(pet.Value)
                            REMOTE.PetAbility:FireServer(pet.Value)
                        end)
                    end
                end

                task.wait(0.3)
            end

            autoUltSkip = nil
        end)

        --damage
        task.spawn(function()
            local conn
            conn = RunS.RenderStepped:Connect(function()
                if _G.disabled then
                    conn:Disconnect()
                    conn = nil
                    autoDamage = nil
                    return
                end

                if autoDamage and not _G.disabled then
                    REMOTE.ClickerDamage:FireServer()
                    REMOTE.ClickerDamage:FireServer()
                end
            end)
        end)

        --coin/drops
        task.spawn(function()
            while not _G.disabled do
                if autoCollect then
                    for _, v in ipairs(WS.Effects:GetDescendants()) do
                        if v.Name == "Base" then
                            v.CFrame = character.HumanoidRootPart.CFrame
                        end
                    end
                end

                task.wait()
            end

            autoCollect = nil
        end)
    end

    --hatching/levelling
    do
        --auto summon
        task.spawn(function()
            local conn
            conn = RunS.RenderStepped:Connect(function()
                if _G.disabled then
                    conn:Disconnect()
                    conn = nil
                    autoSummon = nil
                    selectedEggAutoSummon = nil
                    return
                end

                if autoSummon and selectedEggAutoSummon ~= nil and not table.find(IGNORED_WORLDS, player.World.Value) then
                    task.spawn(function()
                        if selectedEggAutoSummon then
                            local egg = WS.Worlds:FindFirstChild(selectedEggAutoSummon, true)

                            if egg then
                                REMOTE.OpenEgg:InvokeServer(egg, MAX_SUMMON)
                            end
                        end
                    end)
                end
            end)
        end)

        --max summon
        task.spawn(function()
            while not _G.disabled do
                if autoMaxOpen and selectedEggMaxOpen then
                    REMOTE.AttemptMultiOpen:FireServer(selectedEggMaxOpen)
                end

                task.wait(1)
            end

            autoMaxOpen = nil
            selectedEggMaxOpen = nil
        end)

        --auto fuse
        task.spawn(function()
            while not _G.disabled do
                if autoFuse and selectedFuse then
                    local petToFuse
                    local petsToFeed = getFuseablePets()
                    local pets = getPets()
                    local isMaxLevel = false

                    for _, pet in pairs(pets) do
                        if string.match(selectedFuse, tostring(pet.UID)) then
                            if pet.Level >= configValues.MaxLevel then
                                isMaxLevel = true
                            end

                            petToFuse = pet.UID
                        end
                    end

                    if isMaxLevel then
                        local pet = getNewPetToFuse(petToFuse)

                        if pet then
                            local text = getPetTextFormat(pet)
                            petToFuse = pet.UID
                            selectedFuse = text
                            fighterFuseDropDown.Search.TextBox.Text = text
                        else
                            petToFuse = nil
                            selectedFuse = nil
                            fighterFuseDropDown.Search.TextBox.Text = ""
                        end
                    end

                    if petsToFeed and petToFuse then
                        REMOTE.FeedPets:FireServer(petsToFeed, petToFuse)
                    end

                    task.wait(2)

                    table.clear(petsToFeed)
                    table.clear(pets)
                    petsToFeed = nil
                    pets = nil
                    petToFuse = nil
                    isMaxLevel = nil
                elseif autoFuse and not selectedFuse then
                    GUI:Notify("Error", "Select fighter to fuse")
                    task.wait(3)
                end

                task.wait()
            end

            autoFuse = nil
            selectedFuse = nil
        end)
    end

    --autofarms
    do
        --autofarm v1
        task.spawn(function()
            while not _G.disabled do
                if autofarm1 and not farmAllMobs and selectedMob and not table.find(IGNORED_WORLDS, player.World.Value) then
                    local cWorld = player.World.Value
                    local target = getTarget(selectedMob, cWorld)
                    local enemySpawns = WS.Worlds[cWorld].EnemySpawners
                    local enemyModels = WS.Worlds[cWorld].Enemies:GetChildren()

                    if target ~= nil and target:FindFirstChild("Attackers") then
                        local enemySpawn

                        for _, spawn in ipairs(enemySpawns:GetChildren()) do
                            if spawn.CurrentEnemy.Value == target then
                                enemySpawn = spawn
                                break
                            end
                        end

                        if enemySpawn ~= nil then
                            character.HumanoidRootPart.CFrame = target.HumanoidRootPart.CFrame

                            repeat
                                if target ~= nil and target:FindFirstChild("Attackers") and table.find(enemyModels, target) then
                                    BINDABLE.SendPet:Fire(target, true)
                                end

                                target = enemySpawn.CurrentEnemy.Value
                                task.wait()
                            until _G.disabled
                            or player.World.Value ~= cWorld
                            or target == nil
                            or target:FindFirstChild("Attackers") == nil
                            or table.find(enemyModels, target) == nil
                            or not autofarm1
                            or table.find(IGNORED_WORLDS, player.World.Value)

                            retreat()
                        end
                    end

                    table.clear(enemyModels)
                    ememyModels = nil
                elseif autofarm1 and not selectedMob then
                    GUI:Notify("Error", "No mob selected")
                    task.wait(5)
                elseif autofarm1 and farmAllMobs then
                    GUI:Notify("Error", "Can't select both farms")
                    task.wait(5)
                end

                task.wait()
            end

            autofarm1 = nil
            selectedMob = nil
        end)

        --farm all mob
        task.spawn(function()
            while not _G.disabled do
                if farmAllMobs and not autofarm1 and not table.find(IGNORED_WORLDS, player.World.Value) then
                    local cWorld = player.World.Value
                    local enemySpawns = WS.Worlds[cWorld].EnemySpawners
                    local enemyModels = WS.Worlds[cWorld].Enemies:GetChildren()

                    for _, target in ipairs(enemyModels) do
                        if not farmAllMobs then
                            break
                        end

                        if target:FindFirstChild("Attackers") then
                            local enemySpawn

                            for _, spawn in ipairs(enemySpawns:GetChildren()) do
                                if spawn.CurrentEnemy.Value == target then
                                    enemySpawn = spawn
                                    break
                                end
                            end

                            if enemySpawn ~= nil then
                                character.HumanoidRootPart.CFrame = target.HumanoidRootPart.CFrame
                                movePetsToPlayer()

                                repeat
                                    if target ~= nil and target:FindFirstChild("Attackers") and table.find(enemyModels, target) then
                                        BINDABLE.SendPet:Fire(target, true)
                                    end
                                    target = enemySpawn.CurrentEnemy.Value
                                    task.wait()
                                until _G.disabled
                                or player.World.Value ~= cWorld
                                or target == nil
                                or target:FindFirstChild("Attackers") == nil
                                or table.find(enemyModels, target) == nil
                                or not farmAllMobs
                                or table.find(IGNORED_WORLDS, player.World.Value)

                                retreat()
                            end
                        end
                    end

                    table.clear(enemyModels)
                    ememyModels = nil
                elseif farmAllMobs and autofarm1 then
                    GUI:Notify("Error", "Can only select one")
                    task.wait(5)
                end

                task.wait()
            end

            farmAllMobs = nil
        end)
    end

    --quest
    do
        --autoAcceptQuest
        task.spawn(function()
            while not _G.disabled do
                if autoQuest and not table.find(IGNORED_WORLDS, player.World.Value) then
                    local NPC = WS.Worlds[player.World.Value][player.World.Value]
                    REMOTE.StartQuest:FireServer(NPC)
                    REMOTE.FinishQuest:FireServer(NPC)
                    REMOTE.FinishQuestline:FireServer(NPC)
                end
                task.wait()
            end
            autoQuest = nil
        end)

        --autoQuest
        task.spawn(function()
            local objectives = PlayerGui.MainGui.Quest.Objectives

            while not _G.disabled do
                if autoQuest and objectives:FindFirstChild("QuestText") and not table.find(IGNORED_WORLDS, player.World.Value) then
                    for _, obj in ipairs(objectives:GetChildren()) do
                        if obj.Name == "QuestText" and obj.TextColor3 ~= Color3.fromRGB(0, 242, 38) then
                            local world = WS.Worlds[player.World.Value]
                            local enemySpawns = world.EnemySpawners
                            local enemyModels = world.Enemies:GetChildren()

                            for _, enemy in ipairs(enemyModels) do
                                if enemy:FindFirstChild("HumanoidRootPart") and enemy:FindFirstChild("Health") and enemy.Health.Value > 0 then
                                    local found = string.match(obj.Text, enemy.DisplayName.Value)

                                    if found then
                                        local enemySpawn

                                        for _, spawn in ipairs(enemySpawns:GetChildren()) do
                                            if spawn.CurrentEnemy.Value == enemy then
                                                enemySpawn = spawn
                                                break
                                            end
                                        end

                                        if enemySpawn and enemy ~= nil and enemy:FindFirstChild("Attackers") then
                                            character.HumanoidRootPart.CFrame = enemy.HumanoidRootPart.CFrame
                                            movePetsToPlayer()
                                            task.wait()

                                            repeat
                                                if enemy ~= nil and enemy:FindFirstChild("Attackers") and table.find(enemyModels, enemy) then
                                                    BINDABLE.SendPet:Fire(enemy, true)
                                                end

                                                enemy = enemySpawn.CurrentEnemy.Value
                                                task.wait()
                                            until _G.disabled
                                            or player.World.Value ~= world.Name
                                            or enemy == nil
                                            or enemy:FindFirstChild("Attackers") == nil
                                            or table.find(enemyModels, enemy) == nil
                                            or not autoQuest
                                            or table.find(IGNORED_WORLDS, player.World.Value)
                                        end

                                        retreat()
                                    end
                                end
                            end

                            table.clear(enemyModels)
                            ememyModels = nil
                        end
                    end
                end
                task.wait()
            end
            autoQuest = nil
            objectives = nil
        end)
    end

    --trial
    do
        --trial farm
        task.spawn(function()
            while not _G.disabled do
                if towerFarm and player.World.Value == "Tower" then
                    if TRIAL_TARGET.Strongest or TRIAL_TARGET.Weakest then
                        task.wait(WAIT_BEFORE_GETTING_ENEMIES)
                    end

                    if towerTime.Text ~= "00:00" and player.World.Value == "Tower" then
                        local enemies = WS.Worlds.Tower.Enemies
                        local tab = enemies:GetChildren()
                        local floorNumber = tonumber(floorNumberText.Text)

                        if #tab > 0 then
                            table.sort(tab, function(enemy1, enemy2)
                                local result = false
                                local health1 = enemy1:FindFirstChild("Health") and enemy1.Health.Value or nil
                                local health2 = enemy2:FindFirstChild("Health") and enemy2.Health.Value or nil

                                if health1 and health2 then
                                    if TRIAL_TARGET.Weakest then
                                        result = health1 < health2
                                    elseif TRIAL_TARGET.Strongest then
                                        result = health1 > health2
                                    end
                                end

                                return result
                            end)

                            for _, enemy in ipairs(tab) do
                                local shouldSkip = false

                                if CURRENT_TRIAL == "Hard"
                                   and enemy.Name == "Chest"
                                   and ignoreChest
                                   and floorNumber >= chestIgnoreRoom then

                                    shouldSkip = true
                                end

                                local expression = shouldSkip or not enemy:IsDescendantOf(workspace) or player.World.Value ~= "Tower"

                                if not expression then
                                    pcall(function()
                                        handleAutoTrial(enemies, enemy)
                                    end)
                                end
                            end
                        end

                        table.clear(tab)
                        tab = nil

                        local newlyEquippedPets = getEquippedPets()
                        local areAllGold = true

                        for _, pet in pairs(newlyEquippedPets) do
                            if pet.Passive and pet.Passive ~= "Gold" then
                                areAllGold = false
                                break
                            end
                        end

                        if areAllGold then
                            equipTeam(originalPetsTab)
                        end

                        table.clear(newlyEquippedPets)
                        newlyEquippedPets = nil
                    end
                end

                task.wait()
            end

            towerFarm = nil
        end)

        --auto teleport to trial
        task.spawn(function()
            while not _G.disabled do
                if not table.find(IGNORED_WORLDS, player.World.Value) then
                    local shouldStart = false

                    if easyTrial and easyTrialTime.Text == "00:01" then
                        shouldStart = true
                        CURRENT_TRIAL = "Easy"
                    elseif mediumTrial and mediumTrialTime.Text == "00:01" then
                        shouldStart = true
                        CURRENT_TRIAL = "Medium"
                    elseif hardTrial and hardTrialTime.Text == "00:01" then
                        shouldStart = true
                        CURRENT_TRIAL = "Hard"
                                shouldStart = true
                        CURRENT_TRIAL = "Ultimate"
                    elseif ultimateTrial and ultimateTrialTime.Text == "00:01" then
                        shouldStart = true
                        CURRENT_TRIAL = "Ultimate"
                    end

                    if shouldStart then
                        saveFarmAllState()
                        REMOTE.AttemptTravel:InvokeServer("Tower")

                        --Backup incase all pets get stuck on gold
                        originalEquippedPets = getEquippedPets()
                        table.clear(originalPetsTab)

                        for _, pet in pairs(originalEquippedPets) do
                            table.insert(originalPetsTab, pet.UID)
                        end

                        character.HumanoidRootPart.CFrame = WS.Worlds.Tower.Spawns.SpawnLocation.CFrame + Vector3.new(0,5,0)
                        table.clear(sentDebounce) --in case you tp out of trial before the script does
                    end
                end

                task.wait()
            end

            easyTrial = nil
            mediumTrial = nil
            hardTrial = nil
            ultimateTrial = nil
        end)

        --return from trial
        task.spawn(function()
            local debounce = false

            while not _G.disabled do
                if autoTeleportBack and player.World.Value == "Tower" then
                    if (towerTime.Text == "00:01")
                        or (CURRENT_TRIAL == "Hard" and stopTrial and tonumber(floorNumberText.Text) == roomToStopAt)
                        or (tonumber(floorNumberText.Text) == MAX_ROOM) then
                        pcall(function()
                            if not debounce then
                                debounce = true

                                towerTime.Text = "00:00"
                                floorNumberText.Text = "0"
                                CURRENT_TRIAL = ""

                                table.clear(sentDebounce)
                                tp(currentWorld, savedPos)
                                task.wait(1)

                                debounce = false
                            end
                        end)
                    end
                end

                task.wait()
            end

            autoTeleportBack = nil
        end)

        --auto button press
        task.spawn(function()
            local debounce = false

            while not _G.disabled do
                if autoButtonPress and player.World.Value == "Tower" then
                    for _, instance in ipairs(WS.Worlds.Tower.Map:GetChildren()) do
                        if not debounce and instance.Name == "RestRoom" then
                            for _, obj in ipairs(instance:GetChildren()) do
                                if obj:FindFirstChild("ProximityPrompt") or obj:FindFirstChild("Activation") then
                                    debounce = true
                                    character.HumanoidRootPart.CFrame = obj.CFrame + Vector3.new(0, 0, 5)
                                    task.wait()

                                    pcall(function()
                                        fireproximityprompt(obj.ProximityPrompt)
                                    end)

                                    task.wait(1)
                                    debounce = false
                                end
                            end
                        end
                    end
                end

                task.wait()
            end

            autoButtonPress = nil
        end)

        --disable return ui
        task.spawn(function()
            while not _G.disabled do
                if disableReturn then
                    player.PlayerGui.MainGui.TowerLose.Visible = false
                end

                task.wait()
            end
            disableReturn = nil
        end)
    end

    --raid
    do
        --autoRaid
        task.spawn(function()
            while not _G.disabled do
                if autoRaid and player.World.Value == "Raid" then
                    local raidData = WS.Worlds.Raid.RaidData
                    local enemies = WS.Worlds.Raid.Enemies

                    for _, enemy in ipairs(enemies:GetChildren()) do
                        if raidData.Enemies.Value ~= 0 and enemy.Name ~= raidData.BossId.Value then
                            pcall(function()
                                character.HumanoidRootPart.CFrame = enemy.HumanoidRootPart.CFrame

                                movePetsToPlayer()

                                repeat
                                    if enemy:FindFirstChild("Attackers") then
                                        BINDABLE.SendPet:Fire(enemy, true)
                                    end

                                    task.wait()
                                until _G.disabled
                                or enemy:FindFirstChild("HumanoidRootPart") == nil
                                or enemy:FindFirstChild("Health") == nil
                                or enemy:FindFirstChild("Attackers") == nil
                                or player.World.Value ~= "Raid"
                                or not autoRaid
                                or raidData.Enemies.Value == 0
                                or enemy.Health.Value <= 0

                                retreat()
                            end)
                        elseif raidData.Forcefield.Value == false and raidData.Enemies.Value == 0 and enemy.Name == raidData.BossId.Value then
                            pcall(function()
                                character.HumanoidRootPart.CFrame = enemy.HumanoidRootPart.CFrame

                                movePetsToPlayer()

                                repeat
                                    if enemy:FindFirstChild("Attackers") then
                                        BINDABLE.SendPet:Fire(enemy, true)
                                    end

                                    task.wait()
                                until _G.disabled
                                or enemy:FindFirstChild("HumanoidRootPart") == nil
                                or enemy:FindFirstChild("Health") == nil
                                or enemy:FindFirstChild("Attackers") == nil
                                or player.World.Value ~= "Raid"
                                or not autoRaid
                                or raidData.Forcefield.Value == true
                                or raidData.Enemies.Value > 0
                                or enemy.Health.Value <= 0

                                retreat()
                            end)
                        end
                    end
                end

                task.wait()
            end

            autoRaid = nil
        end)

        --tpraid
        task.spawn(function() --Prioritizes raid over defense and trials
            while not _G.disabled do
                if raid15 or raid45 then
                    local currentRaidMap = WS.Worlds.Raid.Map:FindFirstChildOfClass("Model")
                    if currentRaidMap then
                        local worldName = WS.Worlds.Raid.RaidData.CurrentWorld.Value

                        if raidWorlds[worldName] == true then
                            local min = os.date("%M")

                            if (raid15 and min == "14") or (raid45 and min == "44") then
                                for _, v in pairs(getconnections(yesButton.Activated)) do
                                    v:Fire()

                                    saveFarmAllState()

                                    repeat
                                        task.wait()
                                        min = os.date("%M")
                                    until min == "15" or min == "45" or _G.disabled or not raidWorlds[worldName]
                                end
                            else
                                repeat
                                    task.wait()
                                    min = os.date("%M")
                                until min == "14" or min == "44" or _G.disabled or not raidWorlds[worldName]
                            end
                        end
                    end
                end

                task.wait()
            end

            raid15 = nil
            raid45 = nil
        end)

        --return from raid
        task.spawn(function()
            while not _G.disabled do
                if raidTPback then
                    if RAID_RESULT.Visible then
                        RAID_RESULT.Visible = false
                        tp(currWorld, raidCharPos)
                    end
                end

                task.wait()
            end

            raidTPback = nil
        end)
    end

    --defense mode
    do
        --auto defense
        task.spawn(function()
            local enemies = WS.Worlds.Titan.Enemies
            while not _G.disabled do
                if autoDefense and player.World.Value == "Titan" then
                    local tab = enemies:GetChildren()
                    for _, enemy in ipairs(tab) do
                        pcall(function()
                            character.HumanoidRootPart.CFrame = enemy.HumanoidRootPart.CFrame

                            movePetsToPlayer()
                            local ok
                            repeat
                                ok, _ = pcall(function()
                                    BINDABLE.SendPet:Fire(enemy, true)
                                end)
                                task.wait()
                            until _G.disabled
                            or not ok
                            or enemy.Health.Value <= 0
                            or enemy:FindFirstChild("HumanoidRootPart") == nil
                            or not autoDefense
                            or player.World.Value ~= "Titan"

                            retreat()
                        end)
                    end
                end

                task.wait()
            end

            autoDefense = nil
        end)

        --auto start defense mode
        task.spawn(function()
            while not _G.disabled do
                if autoStartDefense and selectedDefenseWorld then
                    local items = data:GetData("Items")
                    if items then
                        if (items.TitanSummon ~= nil and items.TitanSummon > 0) then --Defense token
                            local trigger = WS.Worlds[selectedDefenseWorld].TitanSummon:FindFirstChild("Trigger")

                            if trigger then
                                REMOTE.SummonTitan:FireServer(trigger)
                            else
                                GUI:Notify("Error", "You need to be in this world")
                            end
                        end
                    else
                        warn(string.format("No items found [%s]", NAME))
                    end
                end

                task.wait(3)
            end

            autoStartDefense = nil
        end)

        --auto tp to defense mode
        task.spawn(function()
            while not _G.disabled do
                if teleportToDefenseMode
                and not table.find(IGNORED_WORLDS, player.World.Value)
                and not KILLING_METEOR
                and not KILLING_GIFT then
                    if selectedDefenseWorld then
                        REMOTE.AttemptTravel:InvokeServer("Titan")
                        task.wait()
                        tpToCurrentDefense()
                    else
                        GUI:Notify("Error", "No world selected")
                    end
                end

                task.wait()
            end

            teleportToDefenseMode = nil
            selectedDefenseWorld = nil
        end)

        --auto return from defense
        task.spawn(function()
            while not _G.disabled do
                if tpFromDefense and DEFENSE_RESULT.Visible then
                    DEFENSE_RESULT.Visible = false
                    tp(currWorld, defenseCharPos)
                end
                task.wait()
            end
            tpFromDefense = nil
        end)
    end
end








OrionLib:Init()
