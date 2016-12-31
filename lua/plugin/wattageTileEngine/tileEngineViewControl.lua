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

    local function initialize()
        container = display.newContainer(params.pixelWidth, params.pixelHeight)
        params.parentGroup:insert(container)
        container:insert(tileEngineInstance.getMasterGroup())

        container.x = params.centerX
        container.y = params.centerY

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