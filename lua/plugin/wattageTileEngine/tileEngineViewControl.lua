local Utils = require "plugin.wattageTileEngine.utils"
local TileEngine = require "plugin.wattageTileEngine.tileEngine"

local requireParams = Utils.requireParams

local TileEngineViewControl = {}
TileEngineViewControl.new = function(params)
    requireParams({"parentGroup","centerX","centerY","pixelWidth","pixelHeight","tileEngineInstance"}, params)

    local self = {}

    local container
    local camera
    local tileEngineInstance = params.tileEngineInstance

    function self.getCamera()
        return camera
    end

    function self.render()
        tileEngineInstance.render(camera)
    end

    function self.getTileCoordinateAtContentXY(contentX, contentY, layerIndex)
        local localX, localY = tileEngineInstance.getMasterGroup():contentToLocal(contentX, contentY)
        localX = localX + camera.pixelWidth / 2
        localY = localY + camera.pixelHeight / 2
        return tileEngineInstance.getCoordinateAtPixelInLayer(camera, localX, localY, layerIndex)
    end

    function self.destroy()
        if container ~= nil then
            container:removeSelf()
        end
        container = nil
        camera = nil
        tileEngineInstance = nil
    end

    local function initialize()
        if params.useContainer then
            container = display.newContainer(params.pixelWidth, params.pixelHeight)
            params.parentGroup:insert(container)
            container:insert(tileEngineInstance.getMasterGroup())

            container.x = params.centerX
            container.y = params.centerY
        else
            local tileEngineGroup = tileEngineInstance.getMasterGroup()
            params.parentGroup:insert(tileEngineGroup)
            tileEngineGroup.x = params.centerX
            tileEngineGroup.y = params.centerY
        end

        camera = TileEngine.Camera.new({
            x = 0,
            y = 0,
            width = params.pixelWidth / tileEngineInstance.getTileSize(),
            height = params.pixelHeight / tileEngineInstance.getTileSize(),
            pixelWidth = params.pixelWidth,
            pixelHeight = params.pixelHeight,
            layer = 1
        })
    end

    initialize()

    return self
end

return TileEngineViewControl