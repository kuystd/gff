-- Services
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local running = false
local loopEnabled = false
local autoDepositEnabled = true -- เปิดใช้งานระบบฝากเงินอัตโนมัติ
local depositThreshold = 1000   -- จำนวนเงินขั้นต่ำที่จะฝาก
local points = {}
local currentPointIndex = 1

-- Settings
local walkSpeed = 16
local promptDelay = 0.3
local customHoldTime = 0.5
local overrideHoldDuration = false
local fileName = "AutoWalk_Config.json"

-- Load Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "ระบบเดินออโต้ + บันทึกตั้งค่า (Save System)",
    LoadingTitle = "สคริปต์เดินออโต้",
    LoadingSubtitle = "รองรับการบันทึกและโหลดจุดพิกัด (Config)",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "AutoWalkConfig",
        FileName = "Settings"
    },
    Discord = { Enabled = false },
    KeySystem = false
})

--========================
-- Helper Functions
--========================

-- ฟังก์ชันดึงจำนวนเงินสดจาก UI บนหน้าจอ และ leaderstats
local function getPlayerCash()
    local cashValue = 0

    -- 1. ค้นหาจาก UI บนหน้าจอ (PlayerGui)
    local playerGui = player:FindFirstChild("PlayerGui")
    if playerGui then
        for _, gui in ipairs(playerGui:GetDescendants()) do
            if gui:IsA("TextLabel") or gui:IsA("TextBox") then
                local text = gui.Text
                -- ถ้าข้อความมีสัญลักษณ์ $ หรือคำว่า cash/money
                if text:find("%$") or text:lower():find("cash") or text:lower():find("money") then
                    local cleanNum = text:gsub("[^%d]", "") -- ดึงเอาเฉพาะตัวเลข
                    local num = tonumber(cleanNum)
                    if num and num > cashValue then
                        cashValue = num
                    end
                end
            end
        end
    end

    -- 2. ค้นหาจาก leaderstats หรือโฟลเดอร์ในตัวละครเพิ่มเติม (กรณีเผื่อไว้)
    local stats = player:FindFirstChild("leaderstats") or player:FindFirstChild("Data") or player:FindFirstChild("stats")
    if stats then
        for _, child in ipairs(stats:GetChildren()) do
            local name = child.Name:lower()
            if name:find("cash") or name:find("money") or name:find("dollar") or name:find("wallet") then
                local num = tonumber(child.Value)
                if num and num > cashValue then
                    cashValue = num
                end
            end
        end
    end

    return cashValue
end

-- ฟังก์ชันยิงสั่งฝากเงิน
local function depositMoney(amount)
    local success, err = pcall(function()
        local atmFolder = ReplicatedStorage:WaitForChild("ATM", 5)
        if atmFolder then
            local cashTransaction = atmFolder:WaitForChild("CashTransaction", 5)
            if cashTransaction then
                local args = { amount, "Deposit" }
                cashTransaction:FireServer(unpack(args))
                
                Rayfield:Notify({
                    Title = "ฝากเงินสำเร็จ 💰", 
                    Content = string.format("ฝากเงินจำนวน %d เรียบร้อยแล้ว!", amount), 
                    Duration = 2.5
                })
            end
        end
    end)

    if not success then
        warn("ไม่สามารถฝากเงินได้: ", err)
    end
end

-- ฟังก์ชันตรวจเช็คเงินแล้วฝากทันที
local function checkAndDeposit()
    if not autoDepositEnabled then return end
    
    local currentCash = getPlayerCash()
    if currentCash >= depositThreshold then
        updateStatus(string.format("เงินครบ %d (มี %d) -> กำลังฝากเงิน...", depositThreshold, currentCash))
        depositMoney(depositThreshold)
        task.wait(1)
    end
end

local function applyWalkSpeed(humanoid)
    if humanoid then
        humanoid.WalkSpeed = walkSpeed
    end
end

local function equipSlot(slotNumber)
    if not slotNumber or slotNumber < 1 or slotNumber > 9 then return end
    
    local character = player.Character
    local backpack = player:FindFirstChild("Backpack")
    if not character or not backpack then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local items = backpack:GetChildren()
    if items[slotNumber] and items[slotNumber]:IsA("Tool") then
        humanoid:EquipTool(items[slotNumber])
    end
end

local function walkTo(position)
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root then return false end

    applyWalkSpeed(humanoid)

    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true
    })

    local success, err = pcall(function()
        path:ComputeAsync(root.Position, position)
    end)

    if not success or path.Status ~= Enum.PathStatus.Success then
        return false
    end

    for _, waypoint in ipairs(path:GetWaypoints()) do
        if not running then return false end

        applyWalkSpeed(humanoid)

        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
        end

        humanoid:MoveTo(waypoint.Position)

        local reached = humanoid.MoveToFinished:Wait()
        if not reached then
            return false
        end
    end

    humanoid:MoveTo(root.Position)
    return true
end

local function findAndTriggerPrompt(position)
    local nearest = nil
    local nearestDistance = 12

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            local parent = obj.Parent
            if parent and parent:IsA("BasePart") then
                local distance = (parent.Position - position).Magnitude
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearest = obj
                end
            end
        end
    end

    if nearest then
        task.wait(promptDelay)

        local holdTime = overrideHoldDuration and customHoldTime or (nearest.HoldDuration > 0 and (nearest.HoldDuration + 0.1) or 0.1)

        if fireproximityprompt then
            fireproximityprompt(nearest)
        else
            nearest:InputHoldBegin()
            task.wait(holdTime)
            nearest:InputHoldEnd()
        end
        return nearest
    end

    return nil
end

--========================
-- Background Money Checker (เช็คเงินตลอดเวลา)
--========================

task.spawn(function()
    while true do
        task.wait(1) -- เช็คเงินทุกๆ 1 วินาที
        if running and autoDepositEnabled then
            local cash = getPlayerCash()
            if cash >= depositThreshold then
                depositMoney(depositThreshold)
                task.wait(2) -- หน่วงเวลาป้องกันการยิงซ้ำซ้อน
            end
        end
    end
end)

--========================
-- Save / Load Functions
--========================

local function saveConfig()
    if not writefile then
        Rayfield:Notify({Title = "ผิดพลาด", Content = "ตัวรันของคุณไม่รองรับการบันทึกไฟล์ (writefile)", Duration = 3})
        return
    end

    local saveData = {
        walkSpeed = walkSpeed,
        promptDelay = promptDelay,
        customHoldTime = customHoldTime,
        overrideHoldDuration = overrideHoldDuration,
        autoDepositEnabled = autoDepositEnabled,
        depositThreshold = depositThreshold,
        pointsList = {}
    }

    for _, p in ipairs(points) do
        table.insert(saveData.pointsList, {
            x = p.position.X,
            y = p.position.Y,
            z = p.position.Z,
            waitTime = p.waitTime,
            slot = p.slot
        })
    end

    local json = HttpService:JSONEncode(saveData)
    writefile(fileName, json)

    Rayfield:Notify({
        Title = "บันทึกสำเร็จ", 
        Content = string.format("บันทึกจุดพิกัด %d จุดลงไฟล์เรียบร้อยแล้ว!", #points), 
        Duration = 3
    })
end

local function loadConfig()
    if not readfile or not isfile or not isfile(fileName) then
        Rayfield:Notify({Title = "แจ้งเตือน", Content = "ไม่พบไฟล์บันทึกตั้งค่าที่เคยเซฟไว้", Duration = 3})
        return
    end

    local success, result = pcall(function()
        local json = readfile(fileName)
        return HttpService:JSONDecode(json)
    end)

    if success and result then
        walkSpeed = result.walkSpeed or walkSpeed
        promptDelay = result.promptDelay or promptDelay
        customHoldTime = result.customHoldTime or customHoldTime
        overrideHoldDuration = result.overrideHoldDuration or overrideHoldDuration
        depositThreshold = result.depositThreshold or depositThreshold
        if result.autoDepositEnabled ~= nil then
            autoDepositEnabled = result.autoDepositEnabled
        end
        
        points = {}
        if result.pointsList then
            for _, p in ipairs(result.pointsList) do
                table.insert(points, {
                    position = Vector3.new(p.x, p.y, p.z),
                    waitTime = p.waitTime or 3,
                    slot = p.slot or 0
                })
            end
        end

        updateStatus("โหลดข้อมูลตั้งค่าสำเร็จ")
        Rayfield:Notify({
            Title = "โหลดสำเร็จ", 
            Content = string.format("โหลดจุดพิกัดเรียบร้อยแล้ว (%d จุด)", #points), 
            Duration = 3
        })
    else
        Rayfield:Notify({Title = "ผิดพลาด", Content = "ไม่สามารถอ่านไฟล์ตั้งค่าได้", Duration = 3})
    end
end

--========================
-- Main Loop Execution
--========================

local function startWorking()
    if #points == 0 then return end
    
    task.spawn(function()
        local loopCount = 1

        while running do
            for i = currentPointIndex, #points do
                if not running then break end
                
                currentPointIndex = i
                local point = points[i]

                local loopInfo = loopEnabled and string.format(" (รอบที่ %d)", loopCount) or ""
                updateStatus("กำลังเดินไปจุดที่ " .. i .. loopInfo)
                
                local success = walkTo(point.position)

                if success and running then
                    updateStatus("ถึงจุดที่ " .. i .. " - กำลังกดปุ่ม E...")
                    
                    -- 1. กดปุ่ม E ก่อน
                    local prompt = findAndTriggerPrompt(point.position)
                    if prompt then
                        Rayfield:Notify({
                            Title = "พบปุ่มกด", 
                            Content = "กดปุ่ม: " .. prompt.Parent.Name, 
                            Duration = 1.5
                        })
                    end

                    task.wait(0.2)

                    -- 2. สลับไปถือไอเทมตามช่องทีหลัง
                    if point.slot and point.slot > 0 then
                        equipSlot(point.slot)
                        updateStatus("สลับไปถือไอเทมช่องที่ " .. point.slot)
                    end

                    -- 3. ตรวจสอบเงินทันทีหลังกดปุ่มและถือของเสร็จ
                    checkAndDeposit()

                    task.wait(point.waitTime)
                elseif not success and running then
                    updateStatus("เดินไปจุดที่ " .. i .. " ไม่สำเร็จ (ข้ามจุด)")
                    task.wait(1)
                end
            end

            if not loopEnabled or not running then
                break
            end

            currentPointIndex = 1
            loopCount = loopCount + 1
            task.wait(0.5)
        end

        if not running then
            updateStatus("หยุดการทำงานแล้ว")
        end
    end)
end

-- Respawn Handler
local function onCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid", 10)
    if hum then
        applyWalkSpeed(hum)
        
        if running and #points > 0 then
            task.wait(2)
            Rayfield:Notify({
                Title = "เกิดใหม่สำเร็จ", 
                Content = "กำลังทำงานต่อจากจุดที่ " .. currentPointIndex, 
                Duration = 3
            })
            startWorking()
        end

        hum.Died:Connect(function()
            if running then
                updateStatus("ตัวละครตาย - รอเกิดใหม่เพื่อทำงานต่อ...")
            end
        end)
    end
end

if player.Character then
    onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

--========================
-- UI Elements
--========================

local MainTab = Window:CreateTab("หน้าหลัก", 4483362458)
local ConfigTab = Window:CreateTab("ตั้งค่าตัวละคร/การกด", 4483362458)
local SettingsTab = Window:CreateTab("จุดพิกัด", 4483362458)
local SaveTab = Window:CreateTab("บันทึกตั้งค่า", 4483362458)

local tempX, tempY, tempZ = 0, 0, 0
local tempWait = 3
local selectedSlot = 0

MainTab:CreateSection("ควบคุมการทำงาน")

local StatusParagraph = MainTab:CreateParagraph({
    Title = "สถานะระบบ", 
    Content = "สถานะ: พร้อมทำงาน | จุดทั้งหมด: 0 จุด | วนซ้ำ: ปิด"
})

function updateStatus(msg)
    local loopText = loopEnabled and "เปิด" or "ปิด"
    StatusParagraph:Set({
        Title = "สถานะระบบ",
        Content = string.format("สถานะ: %s | จุดทั้งหมด: %d จุด | วนซ้ำ: %s", msg, #points, loopText)
    })
end

MainTab:CreateToggle({
    Name = "🔁 เดินวนซ้ำไม่จำกัด (Loop Infinity)",
    CurrentValue = false,
    Flag = "LoopToggle",
    Callback = function(Value)
        loopEnabled = Value
        updateStatus(running and "กำลังทำงาน..." or "พร้อมทำงาน")
    end,
})

MainTab:CreateToggle({
    Name = "💰 ฝากเงินอัตโนมัติเมื่อเงินครบกำหนด",
    CurrentValue = true,
    Flag = "AutoDepositToggle",
    Callback = function(Value)
        autoDepositEnabled = Value
    end,
})

MainTab:CreateInput({
    Name = "💵 กำหนดจำนวนเงินขั้นต่ำที่ต้องการฝาก",
    PlaceholderText = "1000",
    RemoveTextOnFocus = false,
    Callback = function(Text)
        depositThreshold = tonumber(Text) or 1000
    end,
})

MainTab:CreateButton({
    Name = "▶ เริ่มทำงาน (START)",
    Callback = function()
        if running then
            Rayfield:Notify({Title = "แจ้งเตือน", Content = "ระบบกำลังทำงานอยู่แล้ว!", Duration = 3})
            return
        end

        if #points == 0 then
            Rayfield:Notify({Title = "แจ้งเตือน", Content = "กรุณาเพิ่มจุดพิกัดอย่างน้อย 1 จุด!", Duration = 3})
            return
        end

        running = true
        currentPointIndex = 1
        startWorking()
    end,
})

MainTab:CreateButton({
    Name = "■ หยุดทำงาน (STOP)",
    Callback = function()
        running = false
        updateStatus("หยุดการทำงานแล้ว")
    end,
})

-- Config Tab
ConfigTab:CreateSection("ตั้งค่าความเร็วตัวละคร")

ConfigTab:CreateSlider({
    Name = "⚡ ความเร็วในการเดิน (WalkSpeed)",
    Range = {16, 200},
    Increment = 1,
    Suffix = " WalkSpeed",
    CurrentValue = 16,
    Flag = "WalkSpeedSlider",
    Callback = function(Value)
        walkSpeed = Value
        local char = player.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.WalkSpeed = walkSpeed
            end
        end
    end,
})

ConfigTab:CreateSection("ตั้งค่าการกดปุ่ม (ProximityPrompt)")

ConfigTab:CreateInput({
    Name = "⏱️ ระยะเวลารอก่อนกดปุ่ม (วินาที)",
    PlaceholderText = "0.3",
    RemoveTextOnFocus = false,
    Callback = function(Text)
        promptDelay = tonumber(Text) or 0.3
    end,
})

ConfigTab:CreateToggle({
    Name = "⚙️ ใช้เวลากดค้างแบบกำหนดเอง",
    CurrentValue = false,
    Flag = "OverrideHoldToggle",
    Callback = function(Value)
        overrideHoldDuration = Value
    end,
})

ConfigTab:CreateSlider({
    Name = "⏳ ระยะเวลากดปุ่มค้าง (Hold Duration)",
    Range = {0.1, 5},
    Increment = 0.1,
    Suffix = " วินาที",
    CurrentValue = 0.5,
    Flag = "HoldDurationSlider",
    Callback = function(Value)
        customHoldTime = Value
    end,
})

-- Points Management Tab
SettingsTab:CreateSection("📁 หมวดหมู่ที่ 1: เลือกช่องไอเทม (หลังกด E เสร็จ)")

SettingsTab:CreateDropdown({
    Name = "🎒 เลือกช่องไอเทมที่ต้องการถือ",
    Options = {
        "ไม่กดถือช่องไหน", 
        "ช่องที่ 1", 
        "ช่องที่ 2", 
        "ช่องที่ 3", 
        "ช่องที่ 4", 
        "ช่องที่ 5", 
        "ช่องที่ 6", 
        "ช่องที่ 7", 
        "ช่องที่ 8", 
        "ช่องที่ 9"
    },
    CurrentOption = {"ไม่กดถือช่องไหน"},
    MultipleOptions = false,
    Flag = "SlotDropdown",
    Callback = function(Option)
        local choice = Option[1]
        if choice == "ไม่กดถือช่องไหน" then
            selectedSlot = 0
        else
            local num = tonumber(choice:match("%d+"))
            selectedSlot = num or 0
        end
    end,
})

SettingsTab:CreateSection("📁 หมวดหมู่ที่ 2: เพิ่มจุดพิกัดแบบด่วน")

SettingsTab:CreateButton({
    Name = "➕ บันทึกจุดจากตำแหน่งที่ยืนอยู่ทันที",
    Callback = function()
        local character = player.Character
        if character and character:FindFirstChild("HumanoidRootPart") then
            local pos = character.HumanoidRootPart.Position
            local x = math.floor(pos.X * 10) / 10
            local y = math.floor(pos.Y * 10) / 10
            local z = math.floor(pos.Z * 10) / 10

            table.insert(points, {
                position = Vector3.new(x, y, z),
                waitTime = tempWait,
                slot = selectedSlot
            })

            local slotText = selectedSlot > 0 and string.format(" -> ถือช่อง %d", selectedSlot) or ""
            updateStatus("บันทึกจุดพิกัดใหม่แล้ว")
            Rayfield:Notify({
                Title = "บันทึกพิกัดสำเร็จ", 
                Content = string.format("จุดที่ %d: (%.1f, %.1f, %.1f) [กด E%s]", #points, x, y, z, slotText), 
                Duration = 3
            })
        end
    end,
})

SettingsTab:CreateSection("📁 หมวดหมู่ที่ 3: กำหนดและแก้ไขพิกัดเอง")

SettingsTab:CreateButton({
    Name = "📍 ดึงพิกัดปัจจุบันใส่ช่องด้านล่าง",
    Callback = function()
        local character = player.Character
        if character and character:FindFirstChild("HumanoidRootPart") then
            local pos = character.HumanoidRootPart.Position
            tempX = math.floor(pos.X * 10) / 10
            tempY = math.floor(pos.Y * 10) / 10
            tempZ = math.floor(pos.Z * 10) / 10
            
            Rayfield:Notify({
                Title = "ดึงพิกัดสำเร็จ", 
                Content = string.format("X: %.1f, Y: %.1f, Z: %.1f", tempX, tempY, tempZ), 
                Duration = 3
            })
        end
    end,
})

SettingsTab:CreateInput({
    Name = "พิกัด X",
    PlaceholderText = "กรอก X",
    RemoveTextOnFocus = false,
    Callback = function(Text)
        tempX = tonumber(Text) or tempX
    end,
})

SettingsTab:CreateInput({
    Name = "พิกัด Y",
    PlaceholderText = "กรอก Y",
    RemoveTextOnFocus = false,
    Callback = function(Text)
        tempY = tonumber(Text) or tempY
    end,
})

SettingsTab:CreateInput({
    Name = "พิกัด Z",
    PlaceholderText = "กรอก Z",
    RemoveTextOnFocus = false,
    Callback = function(Text)
        tempZ = tonumber(Text) or tempZ
    end,
})

SettingsTab:CreateInput({
    Name = "เวลารอหลังถึงจุด (วินาที)",
    PlaceholderText = "3",
    RemoveTextOnFocus = false,
    Callback = function(Text)
        tempWait = tonumber(Text) or 3
    end,
})

SettingsTab:CreateButton({
    Name = "+ บันทึกจุดพิกัดจากช่องกรอก",
    Callback = function()
        if not tempX or not tempY or not tempZ then return end

        table.insert(points, {
            position = Vector3.new(tempX, tempY, tempZ),
            waitTime = tempWait,
            slot = selectedSlot
        })

        updateStatus("เพิ่มจุดพิกัดแล้ว")
        Rayfield:Notify({
       
