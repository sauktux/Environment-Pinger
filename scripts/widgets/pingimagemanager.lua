local Widget = require "widgets/widget"
local Image = require "widgets/image"
local Text = require "widgets/text"

local TOP_EDGE_BUFFER = 30
local BOTTOM_EDGE_BUFFER = 40
local LEFT_EDGE_BUFFER = 67
local RIGHT_EDGE_BUFFER = 80
local screen_x,screen_z


local function LoadConfig(name)
	local mod = "Environment Pinger"
	return GetModConfigData(name,mod) or GetModConfigData(name,KnownModIndex:GetModActualName(mod))
end

local pingsound = LoadConfig("pingsound")

local PingImageManager = Class(Widget,function(self,inst)
        screen_x,screen_z = TheSim:GetScreenSize()
        self.owner = inst
        Widget._ctor(self,"PingImageManager")
        self.indicators = {}
        --Format: {[source] = {widget = widget, pos = pos, target = target, colour = colour}}
        self.tasks = {}
        self.images = {
         ["ground"] = {atlas = "images/inventoryimages.xml", tex = "turf_grass.tex"},
         ["item"] = {atlas = "images/inventoryimages1.xml", tex = "minifan.tex"},
         ["structure"] = {atlas = "images/hud.xml", tex = "tab_build.tex"},
         ["mob"] = {atlas = "images/inventoryimages.xml", tex = "mole.tex"},
         ["boss"] = {atlas = "images/inventoryimages.xml", tex = "deerclops_eyeball.tex"},
         ["other"] = {atlas = "images/inventoryimages.xml", tex = "nightmare_timepiece.tex"},
         ["background"] = {atlas = "images/avatars.xml",tex = "avatar_frame_white.tex"},
        }
        self.img_scale_modifier = 0.5
        self:Show()
        self:SetClickable(false)
        self:MoveToBack()
        self:StartUpdating()
    end)

function PingImageManager:KillIndicator(source)
    if self.indicators[source] then
       self.indicators[source].widget:Kill()
       if self.tasks[source] then
          self.tasks[source]:Cancel()
          self.tasks[source] = nil
       end
       if self.indicators[source].target then
          self:StopEntHighlighting(self.indicators[source].target) 
       end
       self.indicators[source] = nil
    end
end

function PingImageManager:RemoveIndicatorWithTarget(target)
    if not target then return nil end
    for source,data in pairs(self.indicators) do
       if data.target == target then
           self:KillIndicator(source)
           break
       end
    end
end


function PingImageManager:PlayVolumeScaledSound(pos,sound)
    if not (pingsound and sound) then return nil end
    local player_pos = self.owner:GetPosition()
    local dist_sq = Dist2dSq({x = pos[1], y = pos[3]},{x = player_pos.x,y = player_pos.z})
    local near_audio_gate_distsq = TUNING.MINIFLARE.HUD_MAX_DISTANCE_SQ
    local far_audio_gate_distsq = TUNING.MINIFLARE.FAR_AUDIO_GATE_DISTANCE_SQ
    local volume = (dist_sq > far_audio_gate_distsq and TUNING.MINIFLARE.BASE_VOLUME)
                or (dist_sq > near_audio_gate_distsq and
                        TUNING.MINIFLARE.BASE_VOLUME + (1 - Remap(dist_sq, near_audio_gate_distsq, far_audio_gate_distsq, 0, 1)) * (1-TUNING.MINIFLARE.BASE_VOLUME)
                    )
                or 1.0
    TheFrontEnd:GetSound():PlaySound(sound, nil, volume)
end

function PingImageManager:AddIndicator(source,ping_type,position,colour)
    self:KillIndicator(source)
    position = position and position.x and {position.x,position.y,position.z} or {0,0,0}
    local img = self.images[ping_type]
    if not img then return nil end
    local img_widget = self:AddChild(Image(img.atlas,img.tex))
    img_widget:SetScale(self.img_scale_modifier)
    self:AddIndicatorBackgroundAndText(source,img_widget,ping_type,colour)
    local target
    local entities = TheSim:FindEntities(position[1],position[2],position[3],1,{},{"INLIMBO"},{"epic","_inventoryitem","structure","_health"})
    target = ping_type ~= "ground" and ping_type ~= "other" and entities[1]
    self:RemoveIndicatorWithTarget(target)
    self.indicators[source] = {widget = img_widget, pos = position, target = target, colour = colour}
    self:PlayVolumeScaledSound(position,"turnoftides/common/together/miniflare/explode")
    
    self.tasks[source] = self.owner:DoTaskInTime(20,function() self:KillIndicator(source) end)
    self:UpdateIndicatorPositions()
end


function PingImageManager:AddIndicatorBackgroundAndText(source,img_widget,ping_type,colour)
    local background = self.images.background
    img_widget.bg = img_widget:AddChild(Image(background.atlas,background.tex))
    img_widget.bg:SetTint(unpack(colour))

    local tile_x,tile_y = img_widget.bg:GetSize()
    local item_x,item_y = img_widget:GetSize()
    local average_scale = 1
    local inverse_average_scale = 1
    if tile_x < item_x and tile_y < item_y then
        local item_scale_x = item_x/tile_x
        local item_scale_y = item_y/tile_y
        average_scale = (item_scale_x+item_scale_y)/2
        inverse_average_scale = 1/average_scale
        img_widget:SetScale(inverse_average_scale*self.img_scale_modifier)
        img_widget.bg:SetScale(average_scale)
    end
    
    img_widget.text = img_widget:AddChild(Text(NUMBERFONT,32*average_scale))
    img_widget.text:SetPosition(0,64*average_scale)
    img_widget.text:SetString(source)
    img_widget.text:SetColour(unpack(colour))
    img_widget.text_distance = img_widget:AddChild(Text(NUMBERFONT,32*average_scale))
    img_widget.text_distance:SetPosition(0,-64*average_scale)
    img_widget.text_distance:SetColour(unpack(colour))
end

function PingImageManager:UpdateIndicatorPositions()
   for source,data in pairs(self.indicators) do
      local target = data.target
      if target and target:IsValid() and not target:HasTag("INLIMBO") then
          local pos = {target.Transform:GetWorldPosition()}
          self:DoEntHighlighting(target,self.indicators[source].colour)
          self.indicators[source].pos = pos
      elseif target then
          self.indicators[source].target = nil
      end
      local pos_x,pos_y = TheSim:GetScreenPos(unpack(data.pos))
      if pos_x > screen_x or pos_x < 0 or pos_y < 0 or pos_y > screen_z then
         self:DoOffscreenIndicator(data.widget,data.pos,screen_x,screen_z)
      else
         data.widget:SetPosition(pos_x,pos_y)
      end
      if self.owner and self.owner:IsValid() then
          local x,y,z = self.owner.Transform:GetWorldPosition()
          local dist_sq = Dist2dSq({x = x, y = z},{x = data.pos[1],y = data.pos[3]})
          local dist = string.format("%.1f",math.sqrt(dist_sq))
         data.widget.text_distance:SetString(dist.."m")
      end
   end
end

local function GetXCoord(angle, width)
    if angle >= 90 and angle <= 180 then -- left side
        return 0
    elseif angle <= 0 and angle >= -90 then -- right side
        return width
    else -- middle somewhere
        if angle < 0 then
            angle = -angle - 90
        end
        local pctX = 1 - (angle / 90)
        return pctX * width
    end
end

local function GetYCoord(angle, height)
    if angle <= -90 and angle >= -180 then -- top side
        return height
    elseif angle >= 0 and angle <= 90 then -- bottom side
        return 0
    else -- middle somewhere
        if angle < 0 then
            angle = -angle
        end
        if angle > 90 then
            angle = angle - 90
        end
        local pctY = (angle / 90)
        return pctY * height
    end
end

function PingImageManager:DoOffscreenIndicator(widget,pos,screenWidth,screenHeight)
    -- On the one hand, I could scale it,
    -- on the other hand, the player can see the distance so I'm too lazy to scale it.
    local angleToTarget = self.owner:GetAngleToPoint(unpack(pos))
    local downVector = TheCamera:GetDownVec()
    local downAngle = -math.atan2(downVector.z, downVector.x) / DEGREES
    local indicatorAngle = (angleToTarget - downAngle) + 45 -- Based of the South East being the starting angle system. Clockwise.
    while indicatorAngle > 180 do indicatorAngle = indicatorAngle - 360 end
    while indicatorAngle < -180 do indicatorAngle = indicatorAngle + 360 end
    local x = GetXCoord(indicatorAngle,screenWidth)
    local y = GetYCoord(indicatorAngle,screenHeight)
    
    if x <= LEFT_EDGE_BUFFER then 
        x = LEFT_EDGE_BUFFER
    elseif x >= screenWidth - RIGHT_EDGE_BUFFER then
        x = screenWidth - RIGHT_EDGE_BUFFER
    end

    if y <= 2*BOTTOM_EDGE_BUFFER then 
        y = 2*BOTTOM_EDGE_BUFFER
    elseif y >= screenHeight - 2*TOP_EDGE_BUFFER then
        y = screenHeight - 2*TOP_EDGE_BUFFER
    end
    -- I would really like to change this to be very accurate
    -- But the current method is very quick and simple
    -- and the approximation is good enough to have a sense of direction
    -- so I'll keep it as it is.
    widget:SetPosition(x,y,0)
end

function PingImageManager:DoEntHighlighting(ent,colour)
   if not ent.components.highlight then
       ent:AddComponent("highlight")
   end
   local highlighter = ent.components.highlight
   highlighter:SetAddColour({x = colour[1], y = colour[2], z = colour[3]})
   highlighter:Highlight()
end

function PingImageManager:StopEntHighlighting(ent)
   if not ent.components.highlight then return nil end
   local highlighter = ent.components.highlight
   highlighter:OnRemoveFromEntity()
   highlighter:UnHighlight()
end

function PingImageManager:OnUpdate(dt)
   self:UpdateIndicatorPositions()
end

return PingImageManager