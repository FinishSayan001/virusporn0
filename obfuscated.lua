-- Brainrot Hunter - Script Autônomo (SEM DEPENDÊNCIA DE PYTHON)
-- Verifica brainrots de 10M+ e teleporta automaticamente entre servidores
-- Usa método HOPPER IMBATÍVEL 2025 (TeleportToPlaceInstance com JobId vazio/forçado)

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ==================== CONFIGURAÇÕES ====================
local PLACE_ID = 109983668079237
local MIN_BRAINROT_VALUE = 10000000  -- Valor mínimo: 10M por segundo (10.000.000)
local MAX_CHECK_ATTEMPTS = 2  -- Máximo de tentativas para verificar brainrots por Job ID (2 vezes)
local SCAN_DELAY = 10  -- Delay de 10 segundos entre scans no mesmo servidor

-- WebSocket para receber Job IDs do servidor Python
local WEBSOCKET_URL = "ws://127.0.0.1:51950"

-- Webhooks Discord por faixa de valor
local WEBHOOK_10M_50M = "https://discord.com/api/webhooks/1443349332341424178/iC3OxfQrlEPATQKOSNm3AfEGp5p6Qof2PSwZIDLWY37tUuGtuCKbHQMxuTcJKdM55JLP"  -- 10M até 50M
local WEBHOOK_50M_100M = "https://discord.com/api/webhooks/1450011220471185430/-HFRWnwatVq35pEIB4Gk7DbSGbUO4OXJWW393N6rOgYfkzmUh7XmsPQCVK7VPOew6Iir"  -- 50M até 100M
local WEBHOOK_100M_400M = "https://discord.com/api/webhooks/1444397954994802829/WJ6WVjMrCgEzXRNXY2LQGctIp5FlchQFYjPUGv95q97Pimcfn-ZG4AB9MDF4MDZU3obK"  -- 100M até 400M
local WEBHOOK_400M_PLUS = "https://discord.com/api/webhooks/1444398054554992892/QJ2_IRq6Zjlb4Gh3Tex6nLC2x-KXZ8uHZSc9HHgsV0Gj1p_EF6tO6nPjkyOm4vuJmqJd"  -- 400M+
local WEBHOOK_HIGHLIGHTS = "https://discord.com/api/webhooks/1444398376626950174/5wJWYMtjNwLPC_JW7Eyz8Rbq_uXppJ40Q7KioVVCO54bc4Et7hjS98cvM5Uwc6h5jxAM"  -- Highlights (100M+ ou especiais)

-- Brainrots especiais que sempre devem aparecer em highlights (mesmo abaixo de 100M)
local SPECIAL_BRAINROTS = {
    "Nuclearo Dinossauro",
    "La Spooky Grande",
    "Lavadorito Spinito",
    "Ketupat Kepat",
    "Tang Tang Keletang",
    "Spooky And Pumpky",
    "Los Spaghetti",
    "Spaghetti Tualetti",
    "Garama and Madundung",
    "Ketchuru and Musturu",
    "Lavadorito Spinito",
    "La Supreme Combinasion",
    "Tictac Sahur",
    "Eviledon",
    "Los Primos",
    "Tralaledon",
    "Chipso and Queso",
    "Los Hotspotsitos"
}

-- URL da imagem do thumbnail
local THUMBNAIL_IMAGE_URL = "https://cdn.discordapp.com/attachments/1444466019832692757/1444466050279149698/image0-removebg-preview.png?ex=692ccf57&is=692b7dd7&hm=bdc710323f0fd1948e81a1a345c8fc914e492081f161fab70eee86e68a44ec90&"

-- Variáveis globais
local jobIdAttempts = {}  -- Tabela para rastrear tentativas por Job ID
local isHunting = false  -- Flag para controlar o loop de caça
local websocketConnection = nil  -- Conexão WebSocket
local isWebSocketConnected = false  -- Status da conexão WebSocket
local pendingJobIdRequest = nil  -- Callback para requisição pendente de Job ID

-- ==================== FUNÇÕES DE EXTRAÇÃO DE VALOR ====================

-- Função para extrair valor de texto (compatível com Wave)
local function extractValueFromText(text)
    if not text or text == "" then
        return 0
    end
    
    -- Padrões para valores por segundo (PRIORIDADE ALTA)
    local bPerSecondMatch = text:match("%$([0-9%.]+)B/s")
    if bPerSecondMatch then
        return tonumber(bPerSecondMatch) * 1000000000
    end
    
    local kPerSecondMatch = text:match("%$([0-9%.]+)K/s")
    if kPerSecondMatch then
        return tonumber(kPerSecondMatch) * 1000
    end
    
    local mPerSecondMatch = text:match("%$([0-9%.]+)M/s")
    if mPerSecondMatch then
        return tonumber(mPerSecondMatch) * 1000000
    end
    
    local perSecondMatch = text:match("%$([0-9%.]+)/s")
    if perSecondMatch then
        return tonumber(perSecondMatch)
    end
    
    -- Padrões para valores totais (PRIORIDADE BAIXA)
    local bMatch = text:match("%$([0-9%.]+)B")
    if bMatch then
        return tonumber(bMatch) * 1000000000
    end
    
    local kMatch = text:match("%$([0-9%.]+)K")
    if kMatch then
        return tonumber(kMatch) * 1000
    end
    
    local mMatch = text:match("%$([0-9%.]+)M")
    if mMatch then
        return tonumber(mMatch) * 1000000
    end
    
    local dollarMatch = text:match("%$([0-9%.]+)")
    if dollarMatch then
        return tonumber(dollarMatch)
    end
    
    return 0
end

-- Função para encontrar valor do brainrot (compatível com Wave)
local function findBrainrotValue(parentModel, rarityParent)
    local highestValue = 0
    local valueSource = "N/A"
    local perSecondValue = 0
    local perSecondSource = "N/A"
    
    -- Buscar em TODOS os descendentes do parentModel
    for _, descendant in pairs(parentModel:GetDescendants()) do
        if descendant:IsA("IntValue") or descendant:IsA("NumberValue") or descendant:IsA("StringValue") then
            local propValue = tonumber(descendant.Value) or 0
            if propValue > highestValue then
                highestValue = propValue
                valueSource = descendant.Name .. " (parentModel)"
            end
        elseif descendant:IsA("TextLabel") then
            local text = descendant.Text
            local extractedValue = extractValueFromText(text)
            if extractedValue > 0 then
                -- Verificar se é valor por segundo (contém /s)
                if text:find("/s") then
                    if extractedValue > perSecondValue then
                        perSecondValue = extractedValue
                        perSecondSource = descendant.Name .. " (TextLabel - parentModel)"
                    end
                else
                    -- Valor total
                    if extractedValue > highestValue then
                        highestValue = extractedValue
                        valueSource = descendant.Name .. " (TextLabel - parentModel)"
                    end
                end
            end
        end
    end
    
    -- Buscar em TODOS os descendentes do rarityParent
    if rarityParent then
        for _, descendant in pairs(rarityParent:GetDescendants()) do
            if descendant:IsA("IntValue") or descendant:IsA("NumberValue") or descendant:IsA("StringValue") then
                local propValue = tonumber(descendant.Value) or 0
                if propValue > highestValue then
                    highestValue = propValue
                    valueSource = descendant.Name .. " (rarityParent)"
                end
            elseif descendant:IsA("TextLabel") then
                local text = descendant.Text
                local extractedValue = extractValueFromText(text)
                if extractedValue > 0 then
                    -- Verificar se é valor por segundo (contém /s)
                    if text:find("/s") then
                        if extractedValue > perSecondValue then
                            perSecondValue = extractedValue
                            perSecondSource = descendant.Name .. " (TextLabel - rarityParent)"
                        end
                    else
                        -- Valor total
                        if extractedValue > highestValue then
                            highestValue = extractedValue
                            valueSource = descendant.Name .. " (TextLabel - rarityParent)"
                        end
                    end
                end
            end
        end
    end
    
    -- Buscar por propriedades específicas de valor
    local valueProps = {"PerSecond", "Rate", "Value", "Money", "Price", "Worth", "BrainrotPerSecond", "BrainrotRate", "PerSecondValue", "MoneyPerSecond", "RateValue", "Brainrot", "BrainrotValue", "BrainrotWorth", "BrainrotMoney", "BrainrotPrice"}
    
    -- Buscar no parentModel
    for _, propName in pairs(valueProps) do
        for _, descendant in pairs(parentModel:GetDescendants()) do
            if descendant.Name == propName and (descendant:IsA("IntValue") or descendant:IsA("NumberValue") or descendant:IsA("StringValue")) then
                local propValue = tonumber(descendant.Value) or 0
                if propValue > highestValue then
                    highestValue = propValue
                    valueSource = propName .. " (parentModel)"
                end
            end
        end
    end
    
    -- Buscar no rarityParent
    if rarityParent then
        for _, propName in pairs(valueProps) do
            for _, descendant in pairs(rarityParent:GetDescendants()) do
                if descendant.Name == propName and (descendant:IsA("IntValue") or descendant:IsA("NumberValue") or descendant:IsA("StringValue")) then
                    local propValue = tonumber(descendant.Value) or 0
                    if propValue > highestValue then
                        highestValue = propValue
                        valueSource = propName .. " (rarityParent)"
                    end
                end
            end
        end
    end
    
    -- Priorizar valor por segundo sobre valor total
    local finalValue = perSecondValue > 0 and perSecondValue or highestValue
    local finalSource = perSecondValue > 0 and perSecondSource or valueSource
    
    return finalValue, finalSource
end

-- Função para verificar se o brainrot está em estado de fusing
local function isBrainrotFusing(parentModel, rarityParent)
    -- Verificar se há indicadores de fusing no modelo
    for _, descendant in pairs(parentModel:GetDescendants()) do
        if descendant:IsA("TextLabel") then
            local text = descendant.Text
            if text then
                text = text:lower()
                if text:find("fusing") or text:find("fusion") or text:find("fus") or text:find("merging") or text:find("combining") or text:find("processing") then
                    return true, text
                end
            end
        end
    end
    
    -- Verificar no rarityParent também
    if rarityParent then
        for _, descendant in pairs(rarityParent:GetDescendants()) do
            if descendant:IsA("TextLabel") then
                local text = descendant.Text
                if text then
                    text = text:lower()
                    if text:find("fusing") or text:find("fusion") or text:find("fus") or text:find("merging") or text:find("combining") or text:find("processing") then
                        return true, text
                    end
                end
            end
        end
    end
    
    -- Verificar se há banners de fusing próximos
    local workspace = game:GetService("Workspace")
    local parentPosition = parentModel:FindFirstChild("HumanoidRootPart")
    if parentPosition then
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("TextLabel") and obj.Text then
                local text = obj.Text:lower()
                if text:find("fusing") or text:find("fusion") then
                    local objPosition = obj.Parent:FindFirstChild("HumanoidRootPart")
                    if objPosition and obj.Parent:IsA("BasePart") then
                        local distance = (parentPosition.Position - objPosition.Position).Magnitude
                        if distance < 50 then
                            return true, text
                        end
                    end
                end
            end
        end
    end
    
    return false, nil
end

-- ==================== FUNÇÃO DE VERIFICAÇÃO DE BRAINROTS ====================

-- Cache do Synchronizer para evitar múltiplos requires
local SynchronizerCache = nil

-- Função para obter o Synchronizer (com cache)
local function getSynchronizer()
    if SynchronizerCache then
        return SynchronizerCache
    end
    
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local success, Synchronizer = pcall(function()
        local Packages = ReplicatedStorage:WaitForChild("Packages", 10)
        if not Packages then
            return nil
        end
        local SynchronizerModule = Packages:WaitForChild("Synchronizer", 10)
        if not SynchronizerModule then
            return nil
        end
        return require(SynchronizerModule)
    end)
    
    if success and Synchronizer then
        SynchronizerCache = Synchronizer
        return Synchronizer
    end
    
    return nil
end

-- Função para obter o dono real do plot usando Synchronizer
local function getPlotOwner(plot)
    if not plot then
        return "Unknown"
    end
    
    -- PRIMARY METHOD: Use Synchronizer to get owner (most reliable)
    local Synchronizer = getSynchronizer()
    
    if Synchronizer then
        local success, channel = pcall(function()
            return Synchronizer:Get(plot.Name)
        end)
        
        if success and channel then
            local success2, owner = pcall(function()
                return channel:Get("Owner")
            end)
            
            if success2 and owner then
                -- Check different owner types
                if typeof(owner) == "Instance" and owner:IsA("Player") then
                    return owner.Name
                elseif typeof(owner) == "table" and owner.Name then
                    return owner.Name
                elseif typeof(owner) == "table" and owner.UserId then
                    -- Try to find player by UserId
                    local Players = game:GetService("Players")
                    local player = Players:GetPlayerByUserId(owner.UserId)
                    if player then
                        return player.Name
                    end
                    -- Se não encontrar o player, tentar usar o Name se disponível
                    if owner.Name then
                        return owner.Name
                    end
                end
            end
        end
    end
    
    -- FALLBACK METHOD: Check PlotSign.YourBase (if it's the local player's base)
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yourBase = sign:FindFirstChild("YourBase")
        if yourBase and yourBase:IsA("BillboardGui") and yourBase.Enabled then
            return LocalPlayer.Name
        end
    end
    
    return "Unknown"
end

-- Função para verificar brainrots no servidor atual (baseada no ESP)
local function checkBrainrotsInServer()
    local brainrotCount = 0
    local valuableBrainrots = {}
    local allBrainrots = {}
    
    -- Configurações de raridade (mesmo do ESP)
    local RaritySettings = {
        ["Legendary"] = true,
        ["Mythic"] = true,
        ["Brainrot God"] = true,
        ["Secret"] = true
    }
    
    -- Procurar em todos os plots (bases dos jogadores)
    local plots = workspace:FindFirstChild("Plots")
    if plots then
        for _, plot in pairs(plots:GetChildren()) do
            -- Obter o dono do plot uma vez por plot
            local plotOwner = getPlotOwner(plot)
            
            for _, child in pairs(plot:GetDescendants()) do
                if child.Name == "Rarity" and child:IsA("TextLabel") and RaritySettings[child.Text] then
                    local parentModel = child.Parent.Parent
                    local displayName = child.Parent.DisplayName.Text
                    
                    brainrotCount = brainrotCount + 1
                    
                    -- Ignorar Lucky Block
                    if displayName:lower():find("lucky") or displayName:lower():find("block") then
                        continue -- Pular Lucky Block
                    end
                    
                    -- Ignorar Coffin Tung Tung Tung Sahur
                    if displayName:lower():find("coffin tung tung tung sahur") then
                        continue -- Pular Coffin Tung Tung Tung Sahur
                    end
                    
                    -- Verificar se o brainrot está em estado de fusing
                    local isFusing, fusingText = isBrainrotFusing(parentModel, child.Parent)
                    if isFusing then
                        continue -- Pular este brainrot
                    end
                    
                    -- Encontrar valor do brainrot
                    local value, valueSource = findBrainrotValue(parentModel, child.Parent)
                    
                    if value > 0 then
                        -- Adicionar à lista de todos os brainrots
                        table.insert(allBrainrots, {
                            name = displayName,
                            rarity = child.Text,
                            value = value,
                            source = valueSource,
                            owner = plotOwner
                        })
                        
                        -- Verificar se é valioso o suficiente (10M+)
                        if value >= MIN_BRAINROT_VALUE then
                            table.insert(valuableBrainrots, {
                                name = displayName,
                                rarity = child.Text,
                                value = value,
                                source = valueSource,
                                owner = plotOwner
                            })
                        end
                    end
                end
            end
        end
    end
    
    -- Ordenar brainrots por valor (maior para menor)
    table.sort(allBrainrots, function(a, b) return a.value > b.value end)
    
    print("🧠 === BRAINROTS RAROS ENCONTRADOS ===")
    
    if #allBrainrots > 0 then
        for i, brainrot in ipairs(allBrainrots) do
            local valueText
            if brainrot.value >= 1000000000 then
                valueText = string.format("%.1fB/s", brainrot.value / 1000000000)
            elseif brainrot.value >= 1000000 then
                valueText = string.format("%.1fM/s", brainrot.value / 1000000)
            else
                valueText = string.format("%.1fK/s", brainrot.value / 1000)
            end
            
            print(string.format("🏆 #%d - %s (%s) - %s", 
                i, brainrot.name, brainrot.rarity, valueText))
        end
    else
        print("❌ Nenhum brainrot raro encontrado")
    end
    
    print("=====================================")
    
    if #valuableBrainrots > 0 then
        for _, br in ipairs(valuableBrainrots) do
            local valueText
            if br.value >= 1000000000 then
                valueText = string.format("%.1fB/s", br.value / 1000000000)
            elseif br.value >= 1000000 then
                valueText = string.format("%.1fM/s", br.value / 1000000)
            else
                valueText = string.format("%.1fK/s", br.value / 1000)
            end
            print("✅ BRAINROT VALIOSO:", br.name, "-", valueText)
        end
        return valuableBrainrots
    else
        print("❌ Nenhum brainrot de 10M+ encontrado")
        return nil
    end
end

-- ==================== FUNÇÕES DE WEBSOCKET ====================

-- Função para conectar ao WebSocket do servidor Python
local function connectToWebSocket()
    if isWebSocketConnected then
        return true
    end
    
    -- Verificar se WebSocket está disponível
    if not WebSocket then
        warn("❌ WebSocket não está disponível neste executor!")
        warn("💡 Use um executor que suporte WebSocket (Synapse X, etc.)")
        return false
    end
    
    print("🔌 Conectando ao servidor WebSocket...")
    
    local success, ws = pcall(function()
        return WebSocket.connect(WEBSOCKET_URL)
    end)
    
    if not success or not ws then
        warn("❌ Falha ao conectar ao WebSocket. Tentando novamente em 5 segundos...")
        task.wait(5)
        return false
    end
    
    websocketConnection = ws
    isWebSocketConnected = true
    print("✅ Conectado ao servidor WebSocket!")
    
    -- Handler para receber mensagens
    ws.OnMessage:Connect(function(message)
        local success, data = pcall(function()
            return HttpService:JSONDecode(message)
        end)
        
        if success and data then
            if data.type == "job_id" and data.job_id then
                -- Job ID recebido - chamar callback se houver
                if pendingJobIdRequest then
                    pendingJobIdRequest(data.job_id)
                    pendingJobIdRequest = nil
                end
            elseif data.type == "no_job_id" then
                print("⚠️ Servidor não tem Job IDs disponíveis no momento")
                if pendingJobIdRequest then
                    pendingJobIdRequest(nil)
                    pendingJobIdRequest = nil
                end
            end
        end
    end)
    
    -- Handler para desconexão
    ws.OnClose:Connect(function()
        print("⚠️ WebSocket desconectado. Tentando reconectar...")
        isWebSocketConnected = false
        websocketConnection = nil
        
        -- Tentar reconectar em thread separada para não bloquear
        task.spawn(function()
            task.wait(3)
            connectToWebSocket()
        end)
    end)
    
    return true
end

-- Função para solicitar um Job ID do servidor Python
local function requestJobId()
    -- Verificar conexão e tentar reconectar se necessário
    if not isWebSocketConnected or not websocketConnection then
        warn("❌ WebSocket não conectado. Tentando reconectar...")
        connectToWebSocket()
        
        -- Aguardar um pouco para reconexão
        local reconnectAttempts = 0
        while not isWebSocketConnected and reconnectAttempts < 10 do
            reconnectAttempts = reconnectAttempts + 1
            task.wait(0.5)
        end
        
        if not isWebSocketConnected then
            warn("❌ Não foi possível reconectar ao WebSocket")
            return nil
        end
    end
    
    local jobIdReceived = nil
    local requestCompleted = false
    
    -- Criar callback para receber o Job ID
    pendingJobIdRequest = function(jobId)
        jobIdReceived = jobId
        requestCompleted = true
    end
    
    -- Enviar requisição ao servidor
    local requestMessage = HttpService:JSONEncode({
        type = "request_job_id"
    })
    
    local success = false
    -- Tentar diferentes métodos de envio (compatibilidade com diferentes executores)
    if websocketConnection and websocketConnection.Send then
        success = pcall(function()
            websocketConnection:Send(requestMessage)
        end)
    elseif websocketConnection and websocketConnection.send then
        success = pcall(function()
            websocketConnection:send(requestMessage)
        end)
    end
    
    if not success then
        warn("❌ Falha ao enviar requisição de Job ID. Verificando conexão...")
        isWebSocketConnected = false
        websocketConnection = nil
        pendingJobIdRequest = nil
        return nil
    end
    
    -- Aguardar resposta (máximo 10 segundos para dar mais tempo)
    local waitAttempts = 0
    local maxWaitAttempts = 100  -- 10 segundos (100 * 0.1s)
    
    while not requestCompleted and waitAttempts < maxWaitAttempts do
        waitAttempts = waitAttempts + 1
        task.wait(0.1)
        
        -- Verificar se conexão ainda está ativa
        if not isWebSocketConnected then
            warn("❌ Conexão perdida durante espera")
            pendingJobIdRequest = nil
            return nil
        end
        
        if waitAttempts % 20 == 0 then  -- A cada 2 segundos
            print(string.format("⏳ Aguardando Job ID do servidor... (Tentativa %d/%d)", waitAttempts, maxWaitAttempts))
        end
    end
    
    -- Limpar callback
    pendingJobIdRequest = nil
    
    if not requestCompleted then
        warn("❌ Timeout ao aguardar Job ID do servidor")
        return nil
    end
    
    return jobIdReceived
end

-- ==================== FUNÇÃO DE HOP (USANDO JOB IDS DO SERVIDOR) ====================

-- Função para teleportar usando Job ID recebido do servidor Python
local function hopToNewServer()
    local attemptCount = 0
    
    -- Loop infinito tentando teleportar (sem verificações)
    while true do
        attemptCount = attemptCount + 1
        
        -- Solicitar Job ID do servidor
        local targetJobId = requestJobId()
        
        if targetJobId then
            print(string.format("[%s] Tentando teleportar para Job ID: %s... (Tentativa %d)", LocalPlayer.Name, targetJobId:sub(1, 20) .. "...", attemptCount))
            
            -- Tentar teleportar (sem verificar sucesso - quando funcionar, o Roblox reinicia)
            pcall(function()
                TeleportService:TeleportToPlaceInstance(PLACE_ID, targetJobId, LocalPlayer)
            end)
        else
            print(string.format("⚠️ Não foi possível obter Job ID (Tentativa %d). Tentando novamente...", attemptCount))
        end
        
        -- Aguardar 1 segundo antes da próxima tentativa
        task.wait(1)
    end
end

-- ==================== FUNÇÃO DE NOTIFICAÇÃO DISCORD ====================

-- Função para determinar qual webhook usar baseado no valor máximo
local function getWebhookForValue(maxValue)
    if maxValue >= 400000000 then  -- 400M+
        return WEBHOOK_400M_PLUS
    elseif maxValue >= 100000000 then  -- 100M até 400M
        return WEBHOOK_100M_400M
    elseif maxValue >= 50000000 then  -- 50M até 100M
        return WEBHOOK_50M_100M
    else  -- 10M até 50M
        return WEBHOOK_10M_50M
    end
end

-- Função para verificar se algum brainrot está na lista de especiais
local function isSpecialBrainrot(brainrots)
    for _, br in ipairs(brainrots) do
        local name = br.name or ""
        for _, special in ipairs(SPECIAL_BRAINROTS) do
            if name == special then
                return true
            end
        end
    end
    return false
end

-- Função para verificar se deve enviar para highlights
local function shouldSendToHighlights(brainrots)
    for _, br in ipairs(brainrots) do
        local value = br.value or 0
        -- Se está acima de 100M OU é especial
        if value >= 100000000 then
            return true
        end
    end
    -- Verificar se é especial
    return isSpecialBrainrot(brainrots)
end

-- Função para formatar valor completo com vírgulas
local function formatValueFull(value)
    if value >= 1000000000 then
        return string.format("$%.0fB/s", value / 1000000000)
    elseif value >= 1000000 then
        -- Formatar com vírgulas para milhões
        local millions = value / 1000000
        return string.format("$%.0fM/s", millions)
    elseif value >= 1000 then
        return string.format("$%.0fK/s", value / 1000)
    else
        return string.format("$%.0f/s", value)
    end
end

-- Função para formatar valor compacto
local function formatValueCompact(value)
    if value >= 1000000000 then
        return string.format("$%.1fB/s", value / 1000000000)
    elseif value >= 1000000 then
        return string.format("$%.1fM/s", value / 1000000)
    elseif value >= 1000 then
        return string.format("$%.1fK/s", value / 1000)
    else
        return string.format("$%.0f/s", value)
    end
end

-- ==================== COMPARTILHAMENTO COM OUTROS SCRIPTS LUA ====================

-- Função auxiliar para obter ambiente compartilhado (compatibilidade com diferentes executores)
local function getSharedEnv()
    -- Tentar getgenv primeiro (mais comum)
    if getgenv then
        return getgenv()
    end
    -- Fallback para shared
    if shared then
        return shared
    end
    -- Último recurso: criar uma tabela global
    if _G then
        if not _G.BrainrotHunterShared then
            _G.BrainrotHunterShared = {}
        end
        return _G.BrainrotHunterShared
    end
    return nil
end

-- Inicializar estrutura compartilhada para comunicação com outros scripts
local sharedEnv = getSharedEnv()
if sharedEnv then
    if not sharedEnv.BrainrotHunter then
        sharedEnv.BrainrotHunter = {
            brainrots = {},      -- Lista de todos os brainrots encontrados (10M+)
            lastUpdate = 0,       -- Timestamp da última atualização
            jobId = "",           -- JobId do servidor onde foram encontrados
            version = 1           -- Versão da estrutura (para compatibilidade futura)
        }
        print("✅ Estrutura compartilhada BrainrotHunter inicializada!")
    end
else
    warn("❌ Não foi possível criar ambiente compartilhado! (getgenv/shared/_G não disponíveis)")
end

-- Função para compartilhar brainrots com outros scripts Lua injetados
local function shareBrainrotsToLua(brainrots, jobId)
    if not brainrots or #brainrots == 0 then
        return
    end
    
    local sharedEnv = getSharedEnv()
    if not sharedEnv then
        warn("❌ Não foi possível compartilhar brainrots - ambiente compartilhado não disponível!")
        return
    end
    
    -- Preparar dados para compartilhamento
    local sharedData = {
        brainrots = {},
        lastUpdate = tick(),
        jobId = jobId or game.JobId,
        version = 1
    }
    
    -- Converter brainrots para formato compartilhado
    for _, br in ipairs(brainrots) do
        table.insert(sharedData.brainrots, {
            name = br.name,
            rarity = br.rarity,
            value = br.value,
            valueFormatted = formatValueFull(br.value),
            valueFormattedCompact = formatValueCompact(br.value),
            source = br.source or "unknown",
            owner = br.owner or "Unknown"
        })
    end
    
    -- Atualizar estrutura compartilhada (múltiplos métodos para garantir)
    sharedEnv.BrainrotHunter = sharedData
    
    -- Também tentar shared diretamente (para compatibilidade)
    if shared then
        shared.BrainrotHunter = sharedData
    end
    
    -- E getgenv se disponível
    if getgenv then
        getgenv().BrainrotHunter = sharedData
    end
    
    print(string.format("📤 %d brainrot(s) compartilhado(s) com outros scripts Lua!", #brainrots))
    print(string.format("📊 Dados compartilhados - JobId: %s, lastUpdate: %.2f", sharedData.jobId, sharedData.lastUpdate))
    print(string.format("🔍 Verificação: sharedEnv existe? %s, shared existe? %s, getgenv existe? %s", 
        tostring(sharedEnv ~= nil), tostring(shared ~= nil), tostring(getgenv ~= nil)))
end

-- Função para separar brainrots por faixa de valor
local function separateBrainrotsByRange(brainrots)
    local range10M_50M = {}  -- 10M até 50M (exclusivo)
    local range50M_100M = {}  -- 50M até 100M (exclusivo)
    local range100M_400M = {}  -- 100M até 400M (exclusivo)
    local range400M_Plus = {}  -- 400M+
    
    for _, br in ipairs(brainrots) do
        if br.value >= 400000000 then
            table.insert(range400M_Plus, br)
        elseif br.value >= 100000000 then
            table.insert(range100M_400M, br)
        elseif br.value >= 50000000 then
            table.insert(range50M_100M, br)
        else
            table.insert(range10M_50M, br)
        end
    end
    
    return range10M_50M, range50M_100M, range100M_400M, range400M_Plus
end

-- Função para enviar notificação Discord via webhook
local function sendDiscordNotification(brainrots, jobId, webhookUrl)
    if not webhookUrl or webhookUrl == "" then
        print("⚠️ Webhook não configurado, pulando notificação Discord")
        return
    end
    
    -- Obter o dono da base do primeiro brainrot (todos devem ser do mesmo plot)
    local baseOwner = "Unknown"
    if brainrots and #brainrots > 0 and brainrots[1].owner then
        baseOwner = brainrots[1].owner
    end
    
    local playerCount = #Players:GetPlayers()
    local maxPlayers = Players.MaxPlayers or 8
    
    -- Ordenar brainrots por valor (maior para menor) para pegar o mais valioso no título
    local sortedBrainrots = {}
    for _, br in ipairs(brainrots) do
        table.insert(sortedBrainrots, br)
    end
    table.sort(sortedBrainrots, function(a, b) return a.value > b.value end)
    
    -- Título com o brainrot mais valioso
    local topBrainrot = sortedBrainrots[1]
    local topValueFull = formatValueFull(topBrainrot.value)
    local title = topBrainrot.name .. " (" .. topValueFull .. ")"
    
    -- Criar lista de brainrots formatada como "1x Nome ($valor/s)"
    local brainrotList = ""
    for _, br in ipairs(sortedBrainrots) do
        local valueText = formatValueFull(br.value)
        brainrotList = brainrotList .. string.format("1x %s (%s)\n", br.name, valueText)
    end
    
    local description = "🔥 **Brainrots**\n" .. brainrotList
    
    -- Verificar se deve enviar para highlights
    local shouldHighlight = shouldSendToHighlights(sortedBrainrots)
    local isSpecial = isSpecialBrainrot(sortedBrainrots)
    local topValue = topBrainrot.value
    
    -- Se deve enviar highlights, enviar formato simplificado primeiro
    if shouldHighlight then
        -- Formato simplificado para highlights (sem Job ID, comando TP, etc.)
        local function getTimeString()
            local success, timeStr = pcall(function()
                return os.date("%H:%M")
            end)
            if success and timeStr then
                return timeStr
            else
                -- Fallback: usar tick() se os.date não estiver disponível
                local tickTime = tick()
                local hours = math.floor((tickTime % 86400) / 3600)
                local minutes = math.floor((tickTime % 3600) / 60)
                return string.format("%02d:%02d", hours, minutes)
            end
        end
        local now = getTimeString()
        local embedHighlights = {
            title = title,
            description = description,
            color = 3447003,  -- Azul
            thumbnail = {url = THUMBNAIL_IMAGE_URL},
            footer = {text = "Orcaledon-Highlights 🔒 • Hoje às " .. now}
        }
        
        local payloadHighlights = {embeds = {embedHighlights}}
        
        task.spawn(function()
            local success, response = pcall(function()
                return request({
                    Url = WEBHOOK_HIGHLIGHTS,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = HttpService:JSONEncode(payloadHighlights)
                })
            end)
            
            if success and response and response.StatusCode == 204 then
                print("✅ Notificação Highlights enviada!")
            else
                warn("⚠️ Falha ao enviar Highlights")
            end
        end)
        
        -- Se for 100M+ OU especial, também enviar formato completo para webhook normal
        if topValue >= 100000000 or isSpecial then
            -- Formato completo para webhook normal
            local robloxLink = string.format("roblox://placeId=%d&gameInstanceId=%s", PLACE_ID, jobId)
            local teleportCommand = string.format("game:GetService(\"TeleportService\"):TeleportToPlaceInstance(%d,\"%s\",game.Players.LocalPlayer)", PLACE_ID, jobId)
            
            local embedNormal = {
                title = title,
                description = description,
                color = 3447003,  -- Azul
                thumbnail = {url = THUMBNAIL_IMAGE_URL},
                fields = {
                    {
                        name = "🆔 Server ID",
                        value = "```" .. jobId .. "```",
                        inline = false
                    },
                    {
                        name = "👑 Dono da Base",
                        value = baseOwner,
                        inline = true
                    },
                    {
                        name = "👥 Players no Servidor",
                        value = string.format("%d/%d", playerCount, maxPlayers),
                        inline = true
                    },
                    {
                        name = "🔗 Link",
                        value = "```" .. robloxLink .. "```",
                        inline = false
                    }
                },
                footer = {text = "Orcaledon • Notify"}
            }
            
            local payloadNormal = {embeds = {embedNormal}}
            
            task.spawn(function()
                local success, response = pcall(function()
                    return request({
                        Url = webhookUrl,
                        Method = "POST",
                        Headers = {["Content-Type"] = "application/json"},
                        Body = HttpService:JSONEncode(payloadNormal)
                    })
                end)
                
                if success and response and response.StatusCode == 204 then
                    print("✅ Notificação Discord (canal normal) enviada!")
                else
                    local errorMsg = response and response.StatusMessage or "Erro desconhecido"
                    warn("⚠️ Falha ao enviar notificação Discord:", errorMsg)
                end
            end)
        end
    else
        -- Formato completo (com Job ID, comando TP, etc.) - apenas para webhook normal
        local robloxLink = string.format("roblox://placeId=%d&gameInstanceId=%s", PLACE_ID, jobId)
        local teleportCommand = string.format("game:GetService(\"TeleportService\"):TeleportToPlaceInstance(%d,\"%s\",game.Players.LocalPlayer)", PLACE_ID, jobId)
        
        local embed = {
            title = title,
            description = description,
            color = 3447003,  -- Azul
            thumbnail = {url = THUMBNAIL_IMAGE_URL},
            fields = {
                {
                    name = "🆔 Server ID",
                    value = "```" .. jobId .. "```",
                    inline = false
                },
                {
                    name = "👑 Dono da Base",
                    value = baseOwner,
                    inline = true
                },
                {
                    name = "👥 Players no Servidor",
                    value = string.format("%d/%d", playerCount, maxPlayers),
                    inline = true
                },
                {
                    name = "🔗 Link",
                    value = "```" .. robloxLink .. "```",
                    inline = false
                },
                {
                    name = "⚡ Comando Teleporte",
                    value = "```lua\n" .. teleportCommand .. "\n```",
                    inline = false
                }
            },
            footer = {text = "Orcaledon • Notify"}
        }
        
        local payload = {embeds = {embed}}
        
        task.spawn(function()
            local success, response = pcall(function()
                return request({
                    Url = webhookUrl,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = HttpService:JSONEncode(payload)
                })
            end)
            
            if success and response and response.StatusCode == 204 then
                print("✅ Notificação Discord enviada com sucesso!")
            else
                local errorMsg = response and response.StatusMessage or "Erro desconhecido"
                warn("⚠️ Falha ao enviar notificação Discord:", errorMsg)
            end
        end)
    end
end


-- ==================== LOOP PRINCIPAL DE CAÇA ====================

-- Função para fazer scan e verificar brainrots
local function performScan(scanNumber)
    local jobId = game.JobId
    print("🔍 Verificando brainrots do servidor atual...")
    
    -- Aguardar carregamento mínimo
    task.wait(0.2)
    
    -- Verificar brainrots no servidor atual
    local valuableBrainrots = checkBrainrotsInServer()
    
    -- Se encontrar brainrots valiosos, enviar notificação de todos
    if valuableBrainrots and #valuableBrainrots > 0 then
        print(string.format("✅ %d BRAINROT(S) ENCONTRADO(S)! Separando por faixa de valor...", #valuableBrainrots))
        
        -- Compartilhar brainrots com outros scripts Lua injetados
        shareBrainrotsToLua(valuableBrainrots, jobId)
        
        -- Separar brainrots por faixa de valor
        local range10M_50M, range50M_100M, range100M_400M, range400M_Plus = separateBrainrotsByRange(valuableBrainrots)
        
        -- Enviar notificações para cada faixa
        if #range10M_50M > 0 then
            print(string.format("📤 Enviando %d brainrot(s) para canal 10M-50M...", #range10M_50M))
            sendDiscordNotification(range10M_50M, jobId, WEBHOOK_10M_50M)
        end
        
        if #range50M_100M > 0 then
            print(string.format("📤 Enviando %d brainrot(s) para canal 50M-100M...", #range50M_100M))
            sendDiscordNotification(range50M_100M, jobId, WEBHOOK_50M_100M)
        end
        
        if #range100M_400M > 0 then
            print(string.format("📤 Enviando %d brainrot(s) para canal 100M-400M...", #range100M_400M))
            sendDiscordNotification(range100M_400M, jobId, WEBHOOK_100M_400M)
        end
        
        if #range400M_Plus > 0 then
            print(string.format("📤 Enviando %d brainrot(s) para canal 400M+...", #range400M_Plus))
            sendDiscordNotification(range400M_Plus, jobId, WEBHOOK_400M_PLUS)
        end
        
        print("✅ Todas as notificações enviadas!")
    else
        print("❌ Nenhum brainrot de 10M+ encontrado neste scan.")
    end
end

-- Função principal de caça - faz apenas 1 scan e depois tenta teleportar
local function huntCycle()
    if isHunting then
        return
    end
    
    isHunting = true
    
    -- Fazer apenas 1 scan
    performScan(1)
    
    print("🔄 Scan completo. Preparando para trocar de servidor...")
    
    isHunting = false
end

-- Loop principal autônomo
local function mainLoop()
    print("🚀 Iniciando loop principal de caça...")
    print(string.format("✅ Brainrot Hunter ATIVADO → %s", LocalPlayer.Name))
    
    while true do
        -- Executar ciclo de caça (faz apenas 1 scan)
        huntCycle()
        
        -- Aguardar 5 segundos para dar tempo das notificações serem enviadas
        print("⏳ Aguardando 5 segundos para garantir que notificações foram enviadas...")
        task.wait(5)
        
        -- Fazer hop para novo servidor (loop infinito tentando teleportar)
        print("🔄 Iniciando tentativas de teleporte rápido...")
        hopToNewServer()
        -- Nota: Esta linha nunca será executada pois hopToNewServer() fica em loop infinito
        -- Quando o teleporte funcionar, o Roblox reinicia e o script é desenjetado
    end
end

-- ==================== INICIALIZAÇÃO ====================

print("🔍 Script injetado! Verificando compatibilidade...")

-- Verificar se request() está disponível
if not request then
    print("❌ ERRO: Função request() não está disponível!")
    print("💡 Este script requer um executor que suporte request() (Wave, Synapse X, etc.)")
    return
end

print("✅ Função request() disponível!")

-- Verificar se WebSocket está disponível
if not WebSocket then
    warn("❌ ERRO: WebSocket não está disponível neste executor!")
    warn("💡 Este script requer um executor que suporte WebSocket (Synapse X, etc.)")
    warn("❌ O script não pode funcionar sem WebSocket!")
    return
else
    print("✅ WebSocket disponível!")
end

-- Verificar se estamos no jogo correto
if game.PlaceId ~= PLACE_ID then
    print("❌ ERRO: Você não está no jogo 'Steal a Brainrot'!")
    print("🎮 PlaceId atual:", game.PlaceId)
    print("🎯 PlaceId esperado:", PLACE_ID)
    print("💡 Entre no jogo 'Steal a Brainrot' antes de executar este script!")
    return
end

print("✅ Jogo correto detectado: Steal a Brainrot")
print("🚀 Brainrot Hunter Autônomo carregado!")
print("🔄 Método: Job IDs via WebSocket (servidor Python)")
print("⏳ Aguardando 10 segundos para o jogo carregar completamente antes de iniciar...")

-- Aguardar 10 segundos após injeção para dar tempo do jogo carregar
task.wait(10)

print("✅ Jogo carregado!")

-- Conectar ao WebSocket se disponível
if WebSocket then
    print("🔌 Conectando ao servidor WebSocket...")
    
    -- Conectar ao WebSocket em thread separada
    task.spawn(function()
        while true do
            if not isWebSocketConnected then
                connectToWebSocket()
            end
            task.wait(5)  -- Verificar conexão a cada 5 segundos
        end
    end)
    
    -- Aguardar conexão WebSocket
    local connectionAttempts = 0
    while not isWebSocketConnected and connectionAttempts < 10 do
        connectionAttempts = connectionAttempts + 1
        task.wait(1)
    end
    
    if isWebSocketConnected then
        print("✅ WebSocket conectado! Iniciando caça...")
    else
        warn("❌ Não foi possível conectar ao WebSocket após 10 tentativas.")
        warn("💡 Certifique-se de que o servidor Python (notifyGG.py) está rodando!")
        warn("❌ O script não pode funcionar sem conexão WebSocket!")
        return
    end
else
    warn("❌ WebSocket não disponível. O script não pode funcionar!")
    return
end

print("🚀 Iniciando caça...")
mainLoop()
