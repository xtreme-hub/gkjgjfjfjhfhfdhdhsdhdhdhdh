--entrenched

getgenv().SilentAim = true
getgenv().Fov = 150
getgenv().ShowFov = true
getgenv().Prediction = true
getgenv().BulletSpeed = 2000
getgenv().PredictionMultiplier = 1.0
getgenv().AutoAdjustPrediction = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local ShootEvent = ReplicatedStorage.ServerEvents.Shoot
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 2
FOVCircle.Filled = false
FOVCircle.NumSides = 128
FOVCircle.Radius = getgenv().Fov
FOVCircle.Color = Color3.fromRGB(255, 255, 255)
FOVCircle.Visible = getgenv().ShowFov

local CurrentTarget = nil
local TargetVelocity = {}
local VelocityHistory = {}

local function GetNil(Name, DebugId)
    for _, Object in getnilinstances() do
        if Object.Name == Name and Object:GetDebugId() == DebugId then
            return Object
        end
    end
end

local function GetClosestTarget()
    local Closest, Dist = nil, getgenv().Fov
    local MousePos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    for _, Player in pairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer and Player.Character and Player.Team ~= LocalPlayer.Team then
            local Head = Player.Character:FindFirstChild("Head")
            local Humanoid = Player.Character:FindFirstChildOfClass("Humanoid")
            local RootPart = Player.Character:FindFirstChild("HumanoidRootPart")
            if Head and Humanoid.Health > 0 and RootPart then
                local ScreenPos, OnScreen = Camera:WorldToViewportPoint(Head.Position)
                if OnScreen then
                    local Distance = (Vector2.new(ScreenPos.X, ScreenPos.Y) - MousePos).Magnitude
                    if Distance < Dist then
                        Closest = {Head = Head, RootPart = RootPart, Player = Player}
                        Dist = Distance
                    end
                end
            end
        end
    end
    return Closest
end

local function GetAverageVelocity(Player)
    if not VelocityHistory[Player] then
        return Vector3.new(0, 0, 0)
    end
    
    local sum = Vector3.new(0, 0, 0)
    local count = 0
    
    for _, vel in pairs(VelocityHistory[Player]) do
        sum = sum + vel
        count = count + 1
    end
    
    if count == 0 then
        return Vector3.new(0, 0, 0)
    end
    
    return sum / count
end

RunService.Heartbeat:Connect(function()
    for _, Player in pairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer and Player.Character then
            local RootPart = Player.Character:FindFirstChild("HumanoidRootPart")
            if RootPart then
                TargetVelocity[Player] = RootPart.Velocity
                
                if not VelocityHistory[Player] then
                    VelocityHistory[Player] = {}
                end
                
                table.insert(VelocityHistory[Player], RootPart.Velocity)
                
                if #VelocityHistory[Player] > 5 then
                    table.remove(VelocityHistory[Player], 1)
                end
            end
        end
    end
end)

RunService.RenderStepped:Connect(function()
    CurrentTarget = getgenv().SilentAim and GetClosestTarget() or nil
    if getgenv().ShowFov then
        FOVCircle.Visible = true
        FOVCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        FOVCircle.Radius = getgenv().Fov
        FOVCircle.Color = CurrentTarget and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 255)
    else
        FOVCircle.Visible = false
    end
end)

local function PredictPosition(TargetHead, TargetPlayer, velocity)
    if not getgenv().Prediction or not velocity then
        return TargetHead.Position
    end
    
    local Origin = Camera.CFrame.Position
    local Distance = (TargetHead.Position - Origin).Magnitude
    local BulletSpeed = getgenv().BulletSpeed
    
    local avgVelocity = GetAverageVelocity(TargetPlayer)
    local finalVelocity = velocity
    
    if avgVelocity.Magnitude > 0 then
        finalVelocity = (velocity * 0.3) + (avgVelocity * 0.7)
    end
    
    local TravelTime = Distance / BulletSpeed
    
    local predictionMultiplier = getgenv().PredictionMultiplier
    
    if getgenv().AutoAdjustPrediction then
        if Distance > 300 then
            predictionMultiplier = predictionMultiplier * (1 + (Distance - 300) / 1000)
        end
        
        if finalVelocity.Magnitude > 50 then
            predictionMultiplier = predictionMultiplier * 1.1
        end
    end
    
    local predictedPosition = TargetHead.Position + (finalVelocity * TravelTime * predictionMultiplier)
    
    local directionToTarget = (predictedPosition - Origin).Unit
    local adjustedDistance = Distance
    local finalPosition = Origin + (directionToTarget * adjustedDistance)
    
    local offset = predictedPosition - TargetHead.Position
    finalPosition = TargetHead.Position + offset
    
    return finalPosition
end

local mtHook
mtHook = hookmetamethod(game, "__namecall", function(Self, ...)
    if rawequal(Self, ShootEvent) and getnamecallmethod() == "FireServer" and getgenv().SilentAim and CurrentTarget then
        local Args = table.pack(...)
        local velocity = TargetVelocity[CurrentTarget.Player]
        local PredictedPos = PredictPosition(CurrentTarget.Head, CurrentTarget.Player, velocity)
        Args[1].rayHitBoxObject = CurrentTarget.Head
        Args[2] = PredictedPos
        return mtHook(Self, table.unpack(Args, 1, Args.n))
    end
    return mtHook(Self, ...)
end)

local OldFireServera
OldFireServer = hookfunction(ShootEvent.FireServer, function(Self, ...)
    if rawequal(Self, ShootEvent) and getgenv().SilentAim and CurrentTarget then
        local Args = table.pack(...)
        local velocity = TargetVelocity[CurrentTarget.Player]
        local PredictedPos = PredictPosition(CurrentTarget.Head, CurrentTarget.Player, velocity)
        Args[1].rayHitBoxObject = CurrentTarget.Head
        Args[2] = PredictedPos
        return OldFireServer(Self, table.unpack(Args, 1, Args.n))
    end
    return OldFireServer(Self, ...)
end)
