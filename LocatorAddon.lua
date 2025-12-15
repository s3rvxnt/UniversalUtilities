local PlayerList = game:GetService("CoreGui"):WaitForChild("PlayerList")

local function Modification1(child)
    local Container = PlayerList:WaitForChild("Children"):WaitForChild("OffsetFrame"):WaitForChild("PlayerScrollList"):WaitForChild("SizeOffsetFrame"):WaitForChild("ScrollingFrameContainer")
    local ActualList = Container:WaitForChild("ScrollingFrameClippingFrame"):WaitForChild("ScrollingFrame"):WaitForChild("OffsetUndoFrame")
    local DropDown = child
    local LocateButton = DropDown.InnerFrame.InspectButton:Clone()
    LocateButton.Parent = DropDown.InnerFrame
    if not LocateButton:FindFirstChild('Divider') then
        LocateButton.Image = ""
        LocateButton.BackgroundTransparency = 0.3
        local Divider = Instance.new("Frame")
        Divider.Name = "divider"
        Divider.Parent = LocateButton
        Divider.AnchorPoint = Vector2.new(0,1)
        Divider.BackgroundColor3 = Color3.new(208/255,217/255,251/255)
        Divider.BackgroundTransparency = 0.84
        Divider.BorderSizePixel = 0
        Divider.Position = UDim2.new(0,0,1,0)
        Divider.Size = UDim2.new(1,0,0,1)
        Divider.ZIndex = 3
    end
    local Player = DropDown.InnerFrame:WaitForChild("PlayerHeader"):WaitForChild("Background"):WaitForChild("TextContainerFrame"):WaitForChild("PlayerName").Text:sub(2)
    DropDown.InnerFrame.PlayerHeader.LayoutOrder = -1
    LocateButton.LayoutOrder = 0
    LocateButton.Name = "LocateButton"
    LocateButton.HoverBackground.Icon:Destroy()
    local ImageIcon = Instance.new("ImageLabel")
    ImageIcon.Name = "Icon"
    ImageIcon.Size = UDim2.new(0,36,0,36)
    ImageIcon.Image = "rbxassetid://129354637755552"
    ImageIcon.ImageRectOffset = Vector2.new(0,0)
    ImageIcon.ImageRectSize = Vector2.new(0,0)
    ImageIcon.Parent = LocateButton.HoverBackground
    ImageIcon.BackgroundTransparency = 1
    if game:GetService("CoreGui"):FindFirstChild(Player.."Locate") then
        LocateButton.HoverBackground.Icon.Image =  "rbxassetid://93890392372456"
        LocateButton.HoverBackground:WaitForChild("Text").Text = "Untrack Player"
    else
        LocateButton.HoverBackground.Icon.Image = "rbxassetid://129354637755552"
        LocateButton.HoverBackground:WaitForChild("Text").Text = "Track Player"
    end
    local HoverEnterListener = LocateButton.MouseEnter:Connect(function()
        LocateButton.HoverBackground.BackgroundColor3 = Color3.new(208,217,251)
        LocateButton.HoverBackground.BackgroundTransparency = 0.92
    end)
    local HoverLeaveListener = LocateButton.MouseLeave:Connect(function()
        LocateButton.HoverBackground.BackgroundTransparency = 1
    end)
    local HoldListener = LocateButton.MouseButton1Down:Connect(function()
        LocateButton.HoverBackground.BackgroundTransparency = 0.88
    end)
    local ActionListener = LocateButton.Activated:Connect(function()
        if LocateButton.HoverBackground:WaitForChild("Text").Text == "Track Player" then
            LocateButton.HoverBackground:WaitForChild("Text").Text = "Untrack Player"
            ImageIcon.Image =  "rbxassetid://93890392372456"
            local Player = DropDown.InnerFrame.PlayerHeader.Background.TextContainerFrame.PlayerName.Text:sub(2)
            local Character = game:GetService("Players")[Player].Character or game:GetService("Players")[Player].CharacterAdded:Wait()
            local Highlight = Instance.new("Highlight")
            Highlight.Name = Player.."Locate"
            Highlight.Parent = game:GetService("CoreGui")
            Highlight.Adornee = Character
            Highlight.FillColor = game:GetService("Players")[Player].TeamColor.Color
            Highlight.FillTransparency = 0
            for _, Bodypart in Character:GetChildren() do
                if Bodypart:IsA("MeshPart") then
                    local IntegrityBox = Instance.new('BoxHandleAdornment')
                    IntegrityBox.Parent = Highlight
                    IntegrityBox.Name = Bodypart.Name
                    IntegrityBox.Adornee = Bodypart
                    IntegrityBox.AlwaysOnTop = true
                    IntegrityBox.ZIndex = 10
                    IntegrityBox.Size = Bodypart.Size
                    IntegrityBox.Color3 = game:GetService("Players")[Player].TeamColor.Color
                end
            end
            local player = game:GetService("Players")[Player]
            local currentTeam = player.Team
            task.spawn(function()
                repeat task.wait()
                    pcall(function()
                        if game:GetService("Players"):FindFirstChild(Player) then
                            local Magnitude = (Character.PrimaryPart.Position-game:GetService("Workspace").CurrentCamera.CFrame.Position).Magnitude
                            Highlight.FillTransparency = (1 - math.clamp(Magnitude/100,0,1)) * 0.9
                            Highlight.OutlineTransparency = math.clamp(Magnitude/100,0,1) * 0.5
                            if Highlight.FillColor ~= player.TeamColor.Color then
                                Highlight.FillColor = player.TeamColor.Color
                            end
                            for _, HighlightPart in Highlight:GetChildren() do
                                if HighlightPart:IsA("BoxHandleAdornment") then
                                    HighlightPart.Transparency = 1 - math.clamp(Magnitude/300,0,1)
                                    HighlightPart.Color3 = player.TeamColor.Color
                                    if HighlightPart.Color3 ~= player.TeamColor.Color then
                                        HighlightPart.Color3 = player.TeamColor.Color
                                    end
                                    if HighlightPart.Size ~= Character:WaitForChild(HighlightPart.Name).Size then
                                        HighlightPart.Size = Character:WaitForChild(HighlightPart.Name).Size
                                    end
                                end
                            end
                            if player.Team ~= currentTeam then
                                currentTeam = player.Team
                                local NamePlate = ActualList:WaitForChild("TeamList_"..currentTeam.Name):WaitForChild("PlayerEntry_"..player.UserId, true):WaitForChild("PlayerEntryContentFrame"):WaitForChild("OverlayFrame"):WaitForChild("NameFrame")
                                local LocatorIcon = Instance.new("ImageLabel")
                                LocatorIcon.Parent = NamePlate
                                LocatorIcon.Name = "LocatorIcon"
                                LocatorIcon.LayoutOrder = 0
                                LocatorIcon.Size = UDim2.new(0,16,0,16)
                                LocatorIcon.BackgroundTransparency = 1
                                LocatorIcon.Image = "rbxassetid://83346450342441"
                                LocatorIcon.ImageRectOffset = Vector2.new(0, 0)
                                LocatorIcon.ImageRectSize = Vector2.new(0, 0)
                                if NamePlate.PlayerIcon:IsA("ImageLabel") then
                                    NamePlate.PlayerIcon.Visible = false
                                end
                            end
                        else
                            Highlight:Destroy()
                        end
                    end)
                until Highlight.Parent == nil
            end)
            local CharacterAddedListener = game:GetService("Players")[Player].CharacterAdded:Connect(function()
                Character = player.Character or player.CharacterAdded:Wait()
                Highlight.Adornee = Character
                for _, HighlightPart in Highlight:GetChildren() do
                    if HighlightPart:IsA("BoxHandleAdornment") then
                        HighlightPart.Adornee = Character:WaitForChild(HighlightPart.Name)
                    end
                end
                Highlight:FindFirstChildOfClass("BillboardGui").Adornee = Character:WaitForChild("Head")
            end)
            local BillboardGui = Instance.new("BillboardGui")
            local TextLabel = Instance.new("TextLabel")
            BillboardGui.Adornee = Character:WaitForChild("Head")
            BillboardGui.Name = Player
            BillboardGui.Parent = Highlight
            BillboardGui.Size = UDim2.new(0, 100, 0, 150)
            BillboardGui.StudsOffset = Vector3.new(0, 1, 0)
            BillboardGui.AlwaysOnTop = true
            TextLabel.Parent = BillboardGui
            TextLabel.BackgroundTransparency = 1
            TextLabel.Position = UDim2.new(0, 0, 0, -50)
            TextLabel.Size = UDim2.new(0, 100, 0, 100)
            TextLabel.Font = Enum.Font.SourceSansSemibold
            TextLabel.TextSize = 20
            TextLabel.TextColor3 = Color3.new(1, 1, 1)
            TextLabel.TextStrokeTransparency = 0
            TextLabel.TextYAlignment = Enum.TextYAlignment.Bottom
            TextLabel.Text = Player
            TextLabel.ZIndex = 10
            local NamePlate = ActualList:FindFirstChild("PlayerEntry_"..player.UserId, true):WaitForChild("PlayerEntryContentFrame"):WaitForChild("OverlayFrame"):WaitForChild("NameFrame")
            local LocatorIcon = Instance.new("ImageLabel")
            LocatorIcon.Parent = NamePlate
            LocatorIcon.Name = "LocatorIcon"
            LocatorIcon.LayoutOrder = 0
            LocatorIcon.Size = UDim2.new(0,16,0,16)
            LocatorIcon.BackgroundTransparency = 1
            LocatorIcon.Image = "rbxassetid://83346450342441"
            LocatorIcon.ImageRectOffset = Vector2.new(0, 0)
            LocatorIcon.ImageRectSize = Vector2.new(0, 0)
            if NamePlate.PlayerIcon:IsA("ImageLabel") then
                NamePlate.PlayerIcon.Visible = false
            end
            game:GetService("RunService").Heartbeat:Wait()
            Highlight.AncestryChanged:Once(function()
                CharacterAddedListener:Disconnect()
            end)
        else
            ImageIcon.Image = "rbxassetid://129354637755552"
            local Player = DropDown.InnerFrame.PlayerHeader.Background.TextContainerFrame.PlayerName.Text:sub(2)
            game:GetService("CoreGui"):FindFirstChild(Player.."Locate"):Destroy()
            local player = game:GetService("Players")[Player]
            for _,teamlist in ActualList:GetChildren() do
                if teamlist:IsA("Frame") then
                    for _,PlayerEntry in teamlist:GetChildren() do
                        if string.find(PlayerEntry.Name,"PlayerEntry") then
                            if tostring(player.UserId) == string.gsub(PlayerEntry.Name,"PlayerEntry_","") then
                                local NamePlate = PlayerEntry:WaitForChild("PlayerEntryContentFrame"):WaitForChild("OverlayFrame"):WaitForChild("NameFrame")
                                NamePlate.LocatorIcon:Destroy()
                                NamePlate.PlayerIcon.Visible = true
                            end
                        end
                    end
                end
            end
            LocateButton.HoverBackground:WaitForChild("Text").Text = "Track Player"
        end
    end)
    if DropDown.Size == UDim2.new(0,304,0,304) then
        DropDown.Size = UDim2.new(0,304,0,360)
    elseif DropDown.Size == UDim2.new(0,304,0,136) then
        DropDown.Size = UDim2.new(0,304,0,192)
    end
    local SelectionChangedListener = DropDown.InnerFrame.PlayerHeader.Background.TextContainerFrame.PlayerName:GetPropertyChangedSignal('Text'):Connect(function()
        local Player = DropDown.InnerFrame.PlayerHeader.Background.TextContainerFrame.PlayerName.Text:sub(2)
        if game:GetService("CoreGui"):FindFirstChild(Player.."Locate") then
            LocateButton.HoverBackground:WaitForChild("Text").Text = "Untrack Player"
            LocateButton.HoverBackground.Icon.Image =  "rbxassetid://93890392372456"
        else
            LocateButton.HoverBackground:WaitForChild("Text").Text = "Track Player"
            LocateButton.HoverBackground.Icon.Image = "rbxassetid://129354637755552"
        end
    end)
    local SizeChangedListener = DropDown:GetPropertyChangedSignal("Size"):Connect(function()
        if DropDown.Size == UDim2.new(0,304,0,304) then
            DropDown.Size = UDim2.new(0,304,0,360)
        elseif DropDown.Size == UDim2.new(0,304,0,136) then
            DropDown.Size = UDim2.new(0,304,0,192)
        end
    end)
    game:GetService("RunService").Heartbeat:Wait()
    DropDown.AncestryChanged:Once(function()
        SelectionChangedListener:Disconnect()
        ActionListener:Disconnect()
        HoverLeaveListener:Disconnect()
        HoverEnterListener:Disconnect()
        HoldListener:Disconnect()
        SizeChangedListener:Disconnect()
    end)
end

local function Modification2()
    local Container = PlayerList:WaitForChild("Children"):WaitForChild("OffsetFrame"):WaitForChild("PlayerScrollList"):WaitForChild("SizeOffsetFrame"):WaitForChild("ScrollingFrameContainer")
    local ActualList = Container:WaitForChild("ScrollingFrameClippingFrame"):WaitForChild("ScrollingFrame"):WaitForChild("OffsetUndoFrame")
    for _,teamlist in ActualList:GetChildren() do
        if teamlist:IsA("Frame") then
            for _,PlayerEntry in teamlist:GetChildren() do
                if PlayerEntry.Name:sub(1,11) == "PlayerEntry" then
                    local NamePlate = PlayerEntry:WaitForChild("PlayerEntryContentFrame"):WaitForChild("OverlayFrame"):WaitForChild("NameFrame")
                    local PlayerId = string.gsub(PlayerEntry.Name,"PlayerEntry_","")
                    local player = game:GetService("Players"):GetPlayerByUserId(PlayerId)
                    local PlayerName = player and player.Name
                    if game:GetService("CoreGui"):FindFirstChild(PlayerName.."Locate") then
                        local LocatorIcon = Instance.new("ImageLabel")
                        LocatorIcon.Parent = NamePlate
                        LocatorIcon.Name = "LocatorIcon"
                        LocatorIcon.LayoutOrder = 0
                        LocatorIcon.Size = UDim2.new(0,16,0,16)
                        LocatorIcon.BackgroundTransparency = 1
                        LocatorIcon.Image = "rbxassetid://83346450342441"
                        LocatorIcon.ImageRectOffset = Vector2.new(0, 0)
                        LocatorIcon.ImageRectSize = Vector2.new(0, 0)
                        if NamePlate.PlayerIcon:IsA("ImageLabel") then
                            NamePlate.PlayerIcon.Visible = false
                        end
                    end
                end
            end
        end
    end
    local ListenForDropDown = Container.ChildAdded:Connect(function(child)
        if child.Name == "PlayerDropDown" then
            Modification1(child)
        end
    end)
    game:GetService("RunService").Heartbeat:Wait()
    Container.AncestryChanged:Once(function()
        ListenForDropDown:Disconnect()
    end)
end

PlayerList.ChildAdded:Connect(function(child)
    if child.Name == "Children" then
        Modification2()
    end
end)

if PlayerList:FindFirstChild("Children") then
    local Container = PlayerList:WaitForChild("Children"):WaitForChild("OffsetFrame"):WaitForChild("PlayerScrollList"):WaitForChild("SizeOffsetFrame"):WaitForChild("ScrollingFrameContainer")
    if Container:FindFirstChild("PlayerDropDown") then
        Modification1(Container.PlayerDropDown)
    else
        Modification2()
    end
end
