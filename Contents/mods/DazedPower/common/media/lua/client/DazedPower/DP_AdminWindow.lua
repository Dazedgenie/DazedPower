--[[ DazedPower -- the admin "Inspect system" window: a read-only text dump of one controller's synced state.
     The text comes from DP_Admin.inspectLines, so the window itself only lays it out. ]]

if isServer() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISRichTextPanel"
require "DazedPower/DP_Parts"
require "DazedPower/DP_Admin"

DazedPower = DazedPower or {}
DazedPower.AdminWindow = DazedPower.AdminWindow or {}
local W = DazedPower.AdminWindow
local P = DazedPower.Parts

DP_AdminWindow = ISCollapsableWindow:derive("DP_AdminWindow")

local WIDTH, HEIGHT = 460, 360
local REFRESH = 60    -- UI updates between re-reads of the controller's ModData

--- The rich-text body for the controller, one <LINE> per inspect line.
local function bodyText(object)
    local sq = object and object:getSquare()
    local key = sq and (sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()) or "?"
    local lines = DazedPower.Admin.inspectLines(P.data(object), key)
    return " <SIZE:small> " .. table.concat(lines, " <LINE> ")
end

function DP_AdminWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th = self:titleBarHeight()
    self.body = ISRichTextPanel:new(0, th, self.width, self.height - th)
    self.body:initialise()
    self.body.autosetheight = false
    self.body.clip = true
    self.body.background = false
    self.body.marginLeft, self.body.marginRight, self.body.marginTop = 10, 10, 8
    self.body:setAnchorRight(true)
    self.body:setAnchorBottom(true)
    self:addChild(self.body)
    self.body:addScrollBars()
    self:refresh()
end

function DP_AdminWindow:refresh()
    if not self.body then return end
    self.body.text = bodyText(self.object)
    self.body:paginate()
end

function DP_AdminWindow:update()
    ISCollapsableWindow.update(self)
    if not self.object or self.object:getObjectIndex() == -1 then
        self:close()
        return
    end
    self.tick = (self.tick or 0) + 1
    if self.tick % REFRESH == 0 then self:refresh() end
end

function DP_AdminWindow:close()
    self:removeFromUIManager()
    W.current = nil
end

function DP_AdminWindow:new(x, y, object)
    local o = ISCollapsableWindow.new(self, x, y, WIDTH, HEIGHT)
    o.object = object
    o.title = getText("ContextMenu_DazedPower_AdminInspect")
    o:setResizable(true)
    o.tick = 0
    return o
end

--- Open the window on a controller, replacing one already open.
function W.open(playerObj, object)
    if not object then return nil end
    if W.current then W.current:close() end
    local win = DP_AdminWindow:new(getPlayerScreenLeft(0) + 120, getPlayerScreenTop(0) + 120, object)
    win:initialise()
    win:addToUIManager()
    W.current = win
    return win
end

return W
