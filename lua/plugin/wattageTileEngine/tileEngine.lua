local Utils = require "plugin.wattageTileEngine.utils"

local min = math.min
local max = math.max
local floor = math.floor
local ceil = math.ceil
local requireParams = Utils.requireParams

local SpriteInfo = {}


-- Deprecated
SpriteInfo.new = function(params)
--    requireParams({"imageRect", "width", "height"}, params)

    local self = {}

    self.imageRect = params.imageRect
    self.width = params.width
    self.height = params.height

    function self.destroy()
        self.imageRect:removeSelf()
        self.imageRect = nil
        self.width = nil
        self.height = nil
    end

    return self
end



local Tile = {}

Tile.new = function(params)
--    requireParams({"resourceKey"}, params)

    local self = {}

    self.resourceKey = params.resourceKey

    function self.destroy()
        self.resourceKey = nil
    end

    return self
end



local Array2D = {}

Array2D.new = function(params)
    requireParams({"rows","columns"}, params)

    local self = {}

    self.elements = {}
    self.rowCount = params.rows
    self.columnCount = params.columns

    local function init()
        for row=1,params.rows do
            local curRow = {}
            self.elements[row] = curRow
            for col=1, params.columns do
                curRow[col] = nil
            end
        end
    end

    self.clear = function()
        init()
    end

    function self.destroy()
        self.elements = nil
        self.rowCount = nil
        self.columnCount = nil
    end

    init()

    return self
end


local LAYER_TILE = 1
local LAYER_ENTITY = 2
local LAYER_TILE_SELECTION = 3

local LayerConstants = {}
LayerConstants.LIGHTING_MODE_APPLY_ALL = 0
LayerConstants.LIGHTING_MODE_AMBIENT_ONLY = 1
LayerConstants.LIGHTING_MODE_NONE = 2

local BaseLayer = {}
BaseLayer.new = function(layerType)
    local self = {}

    self.lightingMode = LayerConstants.LIGHTING_MODE_APPLY_ALL --Default
    self.type = layerType
    self.displayGroup = display.newGroup()
    self.displayGroup.isVisible = false

    function self.clear()
        error("Implement the layer clear function")
    end

    function self.setLightingMode(mode)
        self.lightingMode = mode
    end

    function self.getLightingMode()
        return self.lightingMode
    end

    function self.destroy()
        self.type = nil
        self.displayGroup:removeSelf()
        self.displayGroup = nil
    end

    return self
end



local TileSelectionLayer = {}
TileSelectionLayer.new = function(params)
    requireParams({"tileSize"}, params)

    local self = BaseLayer.new(LAYER_TILE_SELECTION)

    local tileSize = params.tileSize
    local tileSelectors = {}
    local tileSelectorsByRowColumn = {}
    local selectionListeners = {}

    local function tapListener(event)
        for i=1,#selectionListeners do
            selectionListeners[i](event.target.row, event.target.column)
        end
    end

    local function addTileSelector(tileSelector)
        table.insert(tileSelectors, tileSelector)

        local row = tileSelectorsByRowColumn[tileSelector.row]
        if row == nil then
            row = {}
            tileSelectorsByRowColumn[tileSelector.row] = row
        end
        row[tileSelector.column] = tileSelector
    end

    local function exists(row, column)
        local row = tileSelectorsByRowColumn[row]
        if row == nil then
            return false
        else
            return row[column] ~= nil
        end
    end

    function self.show()
        self.displayGroup.alpha = 1
    end

    function self.hide()
        self.displayGroup.alpha = 0
    end

    function self.addSelectableTile(row, column)
        if not exists(row, column) then
            local x = tileSize * (column - 1) + tileSize / 2
            local y = tileSize * (row - 1) +  tileSize / 2
            local sprite = display.newRect(self.displayGroup, 0, 0, tileSize, tileSize)
            sprite.strokeWidth = 1
            sprite:setFillColor(1,1,0,0.25)
            sprite:setStrokeColor(0,0,0)
            sprite.x = x
            sprite.y = y
            sprite.row = row
            sprite.column = column
            sprite:addEventListener( "tap", tapListener )
            addTileSelector(sprite)
        end
    end

    function self.clearTileSelectionOptions()
        for i=1,#tileSelectors do
            tileSelectors[i]:removeEventListener( "tap", tapListener )
            tileSelectors[i]:removeSelf()
        end
        tileSelectors = {}
        tileSelectorsByRowColumn = {}
    end

    function self.addSelectionListener(listener)
        table.insert(selectionListeners, listener)
    end

    function self.clearSelectionListeners()
        selectionListeners = {}
    end

    local parentDestroy = self.destroy
    function self.destroy()
        self.clearTileSelectionOptions()
        self.clearSelectionListeners()
        tileSize = nil
        tileSelectors = nil
        tileSelectorsByRowColumn = nil
        selectionListeners = nil
        parentDestroy()
    end

    return self
end



local EntityLayer = {}

EntityLayer.new = function(params)
    requireParams({"tileSize","spriteResolver"}, params)

    local self = BaseLayer.new(LAYER_ENTITY)

    local tileSize= params.tileSize
    local spriteResolver = params.spriteResolver
    local nextEntityId = 1
    local nextNonResourceEntityId = 1
    local entities = {}
    local nonResourceEntities = {}

    function self.clear()
        for id,spriteInfo in pairs(entities) do
            self.displayGroup:remove(spriteInfo.imageRect)
            entities[id] = nil
        end

        for id,displayObject in pairs(nonResourceEntities) do
            self.displayGroup:remove(displayObject)
            nonResourceEntities[id] = nil
        end
    end

    function self.addEntity(resourceKey)
        local id = nextEntityId
        nextEntityId = nextEntityId + 1

        local spriteInfo = spriteResolver.resolveForKey(resourceKey)

        entities[id] = spriteInfo
        self.displayGroup:insert(spriteInfo.imageRect)

        return id, spriteInfo
    end

    function self.addNonResourceEntity(displayObject)
        local id = nextNonResourceEntityId
        nextNonResourceEntityId = nextNonResourceEntityId + 1

        nonResourceEntities[id] = displayObject
        self.displayGroup:insert(displayObject)

        return id
    end

    function self.removeEntity(entityId)
        local spriteInfo = entities[entityId]
        self.displayGroup:remove(spriteInfo.imageRect)
        entities[entityId] = nil
    end

    function self.removeNonResourceEntity(entityId)
        local displayObject = nonResourceEntities[entityId]
        self.displayGroup:remove(displayObject)
        nonResourceEntities[entityId] = nil
    end

    function self.centerEntityOnTile(entityId, row, column)
        local x = tileSize * (column - 1) + tileSize / 2
        local y = tileSize * (row - 1) +  tileSize / 2
        local sprite = entities[entityId].imageRect
        sprite.x = x
        sprite.y = y
    end

    function self.centerNonResourceEntityOnTile(entityId, row, column)
        local x = tileSize * (column - 1) + tileSize / 2
        local y = tileSize * (row - 1) +  tileSize / 2
        local sprite = nonResourceEntities[entityId]
        sprite.x = x
        sprite.y = y
    end

    function self.setEntityTilePosition(entityId, rowContinuous, colContinuous)
        local sprite = entities[entityId].imageRect
        sprite.x = tileSize * colContinuous
        sprite.y = tileSize * rowContinuous
    end

    function self.getEntityTilePosition(entityId)
        local sprite = entities[entityId].imageRect
        local row = sprite.y / tileSize
        local col = sprite.x / tileSize
        return row, col
    end

    function self.setNonResourceEntityTilePosition(entityId, rowContinuous, colContinuous)
        local sprite = nonResourceEntities[entityId]
        sprite.x = tileSize * colContinuous
        sprite.y = tileSize * rowContinuous
    end

    function self.getNonResourceEntityTilePosition(entityId)
        local sprite = nonResourceEntities[entityId]
        local row = sprite.y / tileSize
        local col = sprite.x / tileSize
        return row, col
    end

    function self.getEntityInfo(entityId)
        return entities[entityId]
    end

    function self.getEntityInfos()
        return entities
    end

    function self.getNonResourceEntities()
        return nonResourceEntities
    end

    local parentDestroy = self.destroy
    function self.destroy()
        for id,spriteInfo in pairs(entities) do
            spriteInfo.imageRect:removeSelf()
        end
        entities = nil
        for id, displayObject in pairs(nonResourceEntities) do
            displayObject:removeSelf()
        end
        nonResourceEntities = nil

        tileSize = nil
        spriteResolver = nil
        nextEntityId = nil
        nextNonResourceEntityId = nil
        entities = nil
        nonResourceEntities = nil

        parentDestroy()
    end

    return self
end



local Layer = {}
Layer.new = function(params)
    requireParams({"rows", "columns"}, params)

    local self = BaseLayer.new(LAYER_TILE)

    local dirtyTileCoordinateNextIndex = 1
    local dirtyTileCoordinates = {}

    local tiles = Array2D.new({
        rows = params.rows,
        columns = params.columns
    })
    local rows = params.rows
    local columns = params.columns

    function self.clear()
        dirtyTileCoordinateNextIndex = 1
        for row=1,rows do
            for col=1,columns do
                dirtyTileCoordinates[dirtyTileCoordinateNextIndex] = {row=row,column=col }
                dirtyTileCoordinateNextIndex = dirtyTileCoordinateNextIndex + 1
            end
        end
        tiles.clear()
    end

    function self.getTiles()
        return tiles
    end

    function self.updateTile(row, column, newValue)
        tiles.elements[row][column] = newValue
        dirtyTileCoordinates[dirtyTileCoordinateNextIndex] = {row=row,column=column }
        dirtyTileCoordinateNextIndex = dirtyTileCoordinateNextIndex + 1
    end

    function self.getDirtyTileCoordinates()
        return dirtyTileCoordinates
    end

    function self.resetDirtyTileCollection()
        dirtyTileCoordinateNextIndex = 1
        dirtyTileCoordinates = {}
    end

    function self.getRows()
        return rows
    end

    function self.getColumns()
        return columns
    end

    local parentDestroy = self.destroy
    function self.destroy()
        dirtyTileCoordinateNextIndex = nil
        dirtyTileCoordinates = nil
        tiles.destroy()
        rows = nil
        columns = nil

        parentDestroy()
    end

    return self
end



local Module = {}

Module.new = function(params)
    requireParams({"name","rows","columns", "lightingModel", "losModel"}, params)

    local self = {}

    local physicsBodies = {}

    self.name = params.name
    self.layers = {}
    self.lightingModel = params.lightingModel
    self.losModel = params.losModel

    function self.insertLayerAtIndex(layer, index, scalingDelta, xScrollCoefficient, yScrollCoefficient, xOffset, yOffset)
        if xScrollCoefficient == nil then
            xScrollCoefficient = 1
        end

        if yScrollCoefficient == nil then
            yScrollCoefficient = 1
        end

        if xOffset == nil then
            xOffset = 0
        end

        if yOffset == nil then
            yOffset = 0
        end

        table.insert(self.layers, index, {
            layer = layer,
            scalingDelta = scalingDelta,
            xScrollCoefficient = xScrollCoefficient,
            yScrollCoefficient = yScrollCoefficient,
            xOffset = xOffset,
            yOffset = yOffset
        })
    end

    function self.addPhysicsBody(physicsBody)
        table.insert(physicsBodies, physicsBody)
    end

    function self.removePhysicsBody(physicsBody)
        for i=1,#physicsBodies do
            if physicsBodies[i] == physicsBody then
                table.remove(physicsBodies, i)
                return
            end
        end
    end

    function self.hasDirtyTile()
        for i=1,#self.layers do
            local layer = self.layers[i].layer
            if layer.getDirtyTileCoordinates ~= nil and #layer.getDirtyTileCoordinates() > 0 then
                return true
            end
        end
        return false
    end

    function self.activate()
        for i=1,#physicsBodies do
            physicsBodies[i].isBodyActive = true
        end
        for i=1,#self.layers do
            self.layers[i].layer.displayGroup.alpha = 1
        end
    end

    function self.deactivate()
        for i=1,#physicsBodies do
            physicsBodies[i].isBodyActive = false
        end
        for i=1,#self.layers do
            self.layers[i].layer.displayGroup.alpha = 0
        end
    end

    function self.destroy()
        for i=1,#self.layers do
            self.layers[i].layer.destroy()
        end
        physicsBodies = nil
        self.name = nil
        self.layers = nil
        self.lightingModel = nil
        self.losModel = nil
    end

    return self
end



local Camera = {}
Camera.new = function(params)
    requireParams({"x","y","width","height","pixelWidth","pixelHeight"}, params)

    local self = {}

    local x = params.x
    local y = params.y
    local islocationDirty = true

    function self.isLocationDirty()
        return islocationDirty
    end

    function self.setLocationDirty(v)
        islocationDirty = v
    end

    function self.setLocation(px, py)
        if px ~= x or py ~= y then
            x = px
            y = py
            islocationDirty = true
        end
    end

    function self.getX()
        return x
    end

    function self.getY()
        return y
    end

    self.width = params.width
    self.height = params.height
    self.pixelWidth = params.pixelWidth
    self.pixelHeight = params.pixelHeight

    local layer = params.layer ~= nil and params.layer or 1
    local isLayerDirty = true

    function self.getLayer()
        return layer
    end

    function self.setLayer(v)
        if v ~= layer then
            layer = v
            isLayerDirty = true
        end
    end

    function self.isLayerDirty()
        return isLayerDirty
    end

    function self.setLayerDirty(v)
        isLayerDirty = v
    end

    local zoom = params.zoom ~= nil and params.zoom or 1
    local isZoomDirty = true

    function self.getZoom()
        return zoom
    end

    function self.setZoom(v)
        if v ~= zoom then
            zoom = v
            isZoomDirty = true
        end
    end

    function self.isZoomDirty()
        return isZoomDirty
    end

    function self.setZoomDirty(v)
        isZoomDirty = v
    end

    return self
end



local Engine = {}

Engine.new = function(params)
    requireParams({
        "tileSize",
        "spriteResolver",
        "compensateLightingForViewingPosition",
        "hideOutOfSightElements"
    }, params)

    local LIGHTING_MODE_APPLY_ALL = LayerConstants.LIGHTING_MODE_APPLY_ALL
    local LIGHTING_MODE_AMBIENT_ONLY = LayerConstants.LIGHTING_MODE_AMBIENT_ONLY
    local LIGHTING_MODE_NONE = LayerConstants.LIGHTING_MODE_NONE

    local self = {}

    local tileSize = params.tileSize
    local halfTileSize = tileSize / 2
    local hideOutOfSightElements = params.hideOutOfSightElements
    local compensateLightingForViewingPosition = params.compensateLightingForViewingPosition
    local spriteResolver = params.spriteResolver
    local resolveSpriteForKey = spriteResolver.resolveForKey
    local modules = {}
    local activeModule
    local masterGroup = display.newGroup()
    local trimmedLayers

    local function getTileDisplayObject(layer, tile, row, col)
        local newGroup = resolveSpriteForKey(tile.resourceKey).imageRect
        if newGroup ~= nil then
            local lineOfSightTransitionValue = activeModule.losModel.getLineOfSightTransitionValue(row, col)
            local layerLightingMode = layer.lightingMode
            if layerLightingMode == LIGHTING_MODE_APPLY_ALL then
                local light = activeModule.lightingModel.getAggregateLight(row, col)
                if light ~= nil then
                    newGroup:setFillColor(light.r, light.g, light.b)
                    newGroup.alpha = lineOfSightTransitionValue
                end
            elseif layerLightingMode == LIGHTING_MODE_AMBIENT_ONLY then
                local ambientLight = activeModule.lightingModel.getAmbientLight()
                newGroup:setFillColor(ambientLight.r, ambientLight.g, ambientLight.b)
                newGroup.alpha = lineOfSightTransitionValue
            elseif layerLightingMode ~= LIGHTING_MODE_NONE then
                error "Unsupported lighting mode."
            end
        end
        return newGroup
    end

    -- Determines absolute scaling values relative to the current layer of the camera.
    local function determineAbsoluteScalingForLayers(trimmedLayers, camera, module)
        -- Determine absolute scales up
        local curScale = 1
        local cameraLayer = camera.getLayer()
        for i=cameraLayer,#module.layers do
            if i == cameraLayer then
                curScale = 1
            else
                curScale = curScale + module.layers[i].scalingDelta * camera.getZoom()
            end

            if trimmedLayers[i] == nil then
                trimmedLayers[i] = {
                    scale = curScale
                }
            else
                trimmedLayers[i].scale = curScale
            end
        end

        -- Determine absolute scales down
        local curScale = 1
        for i=cameraLayer,1,-1 do
            if i == cameraLayer then
                curScale = 1
            else
                curScale = curScale - module.layers[i].scalingDelta * camera.getZoom()
            end

            if trimmedLayers[i] == nil then
                trimmedLayers[i] = {
                    scale = curScale
                }
            else
                trimmedLayers[i].scale = curScale
            end
        end
    end

    --[[
        This returns the following structure:
        [
            {
                scale = 1.0,
                visibleTilesInfo = {
                    minRow = 1,
                    maxRow = 2,
                    minCol = 1,
                    maxCol = 2,
                    visibleTiles = {
                        1 = {<tileReference>, ...},
                        2 = {<tileReference>, ...},
                        ...
                    }
                }
            }
        ]
     ]]
    local function updateVisibilityInfo(camera, module)
        local isFirstRun = false
        if trimmedLayers == nil then
            isFirstRun = true
            trimmedLayers = {}
        end

        if isFirstRun or camera.isLayerDirty() or camera.isZoomDirty() then
            determineAbsoluteScalingForLayers(trimmedLayers, camera, module)
        end

        if isFirstRun then
            for i=1,#module.layers do
                local layerGroup = module.layers[i].layer.displayGroup
                layerGroup.isVisible = true
                trimmedLayers[i].displayGroup = layerGroup
                masterGroup:insert(layerGroup)
            end
        end

        if isFirstRun or camera.isZoomDirty() or camera.isLocationDirty() or activeModule.lightingModel.hasDirtyAggregateTile() or activeModule.losModel.hasDirtyTiles() or activeModule.hasDirtyTile() then
            for i=1,#trimmedLayers do
                -- Localize current layer from module
                local curLayerMeta = module.layers[i]
                local curLayer = curLayerMeta.layer
                -- Determine adjusted camera position
                local adjustedCamY = camera.getY() * curLayerMeta.yScrollCoefficient + curLayerMeta.yOffset
                local adjustedCamX = camera.getX() * curLayerMeta.xScrollCoefficient + curLayerMeta.xOffset
                -- Localize current trimmed layer
                local curTrimmedLayer = trimmedLayers[i]
                curTrimmedLayer.adjustedCamY = adjustedCamY
                curTrimmedLayer.adjustedCamX = adjustedCamX
                if curLayer.type == LAYER_TILE then
                    -- Localize scaling for trimmed layer
                    local curScale = curTrimmedLayer.scale * camera.getZoom()
                    -- Determine scaling coefficient, this will be used to scale camera width and height
                    local scalingCoefficient = 1 / curScale
                    local scaledWidth = scalingCoefficient * camera.width
                    local scaledHeight = scalingCoefficient * camera.height
                    -- Determine the bounds of what is visible
                    local cameraRow = floor(adjustedCamY)
                    local cameraCol = floor(adjustedCamX)
                    local newMinCol = floor(adjustedCamX - scaledWidth / 2)
                    local newMaxCol = ceil(newMinCol + scaledWidth + 1)
                    local newMinRow = floor(adjustedCamY - scaledHeight / 2)
                    local newMaxRow = ceil(newMinRow + scaledHeight + 1)

                    local tiles = curLayer.getTiles().elements

                    if not isFirstRun then
                        --region When not the first run, identify cells that have moved out of or into view and update accordingly
                        local visibleTileGroups = curTrimmedLayer.visibleTilesInfo.visibleTileGroups

                        -- Get old boundaries
                        local oldMinCol = curTrimmedLayer.visibleTilesInfo.minCol
                        local oldMaxCol = curTrimmedLayer.visibleTilesInfo.maxCol
                        local oldMinRow = curTrimmedLayer.visibleTilesInfo.minRow
                        local oldMaxRow = curTrimmedLayer.visibleTilesInfo.maxRow

                        --region Remove row(s) which have scrolled out the top of the view.
                        if oldMinRow < newMinRow then
                            for row=oldMinRow,min(newMinRow - 1, oldMaxRow) do
                                if visibleTileGroups[row] ~= nil then
                                    for col=oldMinCol,oldMaxCol do
                                        local tileGroup = visibleTileGroups[row][col]
                                        if tileGroup ~= nil then
                                            tileGroup:removeSelf()
                                        end
                                    end
                                    visibleTileGroups[row] = nil
                                end
                            end
                        end
                        --endregion

                        --region Remove column(s) which have scrolled out the left of the view.
                        if oldMinCol < newMinCol then
                            for row=oldMinRow,oldMaxRow do
                                if visibleTileGroups[row] ~= nil then
                                    for col=oldMinCol,min(newMinCol - 1, oldMaxCol) do
                                        local tileGroup = visibleTileGroups[row][col]
                                        if tileGroup ~= nil then
                                            tileGroup:removeSelf()
                                            visibleTileGroups[row][col] = nil
                                        end
                                    end
                                end
                            end
                        end
                        --endregion

                        --region Remove row(s) which have scrolled out the bottom of the view.
                        if oldMaxRow > newMaxRow then
                            for row=max(newMaxRow + 1,oldMinRow), oldMaxRow do
                                if visibleTileGroups[row] ~= nil then
                                    for col=oldMinCol,oldMaxCol do
                                        local tileGroup = visibleTileGroups[row][col]
                                        if tileGroup ~= nil then
                                            tileGroup:removeSelf()
                                        end
                                    end
                                    visibleTileGroups[row] = nil
                                end
                            end
                        end
                        --endregion

                        --region Remove column(s) which have scrolled out the right of the view.
                        if oldMaxCol > newMaxCol then
                            for row=oldMinRow,oldMaxRow do
                                if visibleTileGroups[row] ~= nil then
                                    for col=max(newMaxCol + 1,oldMinCol), oldMaxCol do
                                        local tileGroup = visibleTileGroups[row][col]
                                        if tileGroup ~= nil then
                                            tileGroup:removeSelf()
                                            visibleTileGroups[row][col] = nil
                                        end
                                    end
                                end
                            end
                        end
                        --endregion

                        -- todo for each dirty tile which falls within the affected area of a light, that light needs to be marked dirty since shadows may need to be recast. (This only applies while processing Layer 1)
                        -- todo also, I think it is possible for this piece to create a display group that is not in and thus not needed at the moment
                        --region Update dirty tiles within new boundaries
                        local dirtyTileCoordinates = curLayer.getDirtyTileCoordinates()
                        for i=1,#dirtyTileCoordinates do
                            local coordinate = dirtyTileCoordinates[i]
                            local dirtyRow = coordinate.row
                            local dirtyCol = coordinate.column
                            local dirtyRowArray = visibleTileGroups[dirtyRow]
                            if dirtyRowArray ~= nil and dirtyCol >= newMinCol and dirtyCol <= newMaxCol then
                                local dirtyGroup = dirtyRowArray[dirtyCol]
                                if dirtyGroup ~= nil then
                                    dirtyRowArray[dirtyCol] = nil
                                    dirtyGroup:removeSelf()
                                end

                                local newGroup
                                local tile = tiles[dirtyRow][dirtyCol]
                                if tile ~= nil then
                                    newGroup = getTileDisplayObject(curLayer, tile, dirtyRow, dirtyCol)
                                end
                                if newGroup ~= nil then
                                    newGroup.x = (dirtyCol - 1) * tileSize + halfTileSize
                                    newGroup.y = (dirtyRow - 1) * tileSize + halfTileSize
                                    dirtyRowArray[dirtyCol] = newGroup
                                    curTrimmedLayer.displayGroup:insert(newGroup)
                                end
                            end
                        end
                        --endregion

                        -- Reset dirty tiles
                        curLayer.resetDirtyTileCollection()

                        --region Add new row(s) which have scrolled into view from the top
                        if newMinRow < oldMinRow then
                            for row=newMinRow,min(oldMinRow - 1,newMaxRow) do
                                local newRow = visibleTileGroups[row]
                                if newRow == nil then
                                    newRow = {}
                                    visibleTileGroups[row] = newRow
                                end
                                for col=newMinCol,newMaxCol do
                                    local tileRow = tiles[row]
                                    if tileRow ~= nil then
                                        local tile = tileRow[col]
                                        -- Check for nil tile is needed for corner cases where a corner would be added
                                        -- by multiple handlers
                                        if tile ~= nil and newRow[col] == nil then
                                            local newGroup = getTileDisplayObject(curLayer, tile, row, col)
                                            if newGroup ~= nil then
                                                newGroup.x = (col - 1) * tileSize + halfTileSize
                                                newGroup.y = (row - 1) * tileSize + halfTileSize
                                                newRow[col] = newGroup
                                                curTrimmedLayer.displayGroup:insert(newGroup)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        --endregion

                        --region Add new row(s) which have scrolled into view from bottom
                        if newMaxRow > oldMaxRow then
                            for row=max(newMinRow,oldMaxRow + 1),newMaxRow do
                                local newRow = visibleTileGroups[row]
                                if newRow == nil then
                                    newRow = {}
                                    visibleTileGroups[row] = newRow
                                end
                                for col=newMinCol,newMaxCol do
                                    local tileRow = tiles[row]
                                    if tileRow ~= nil then
                                        local tile = tileRow[col]
                                        -- Check for nil tile is needed for corner cases where a corner would be added
                                        -- by multiple handlers
                                        if tile ~= nil and newRow[col] == nil then
                                            local newGroup = getTileDisplayObject(curLayer, tile, row, col)
                                            if newGroup ~= nil then
                                                newGroup.x = (col - 1) * tileSize + halfTileSize
                                                newGroup.y = (row - 1) * tileSize + halfTileSize
                                                newRow[col] = newGroup
                                                curTrimmedLayer.displayGroup:insert(newGroup)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        --endregion

                        --region Add new column(s) which have scrolled into view from left
                        if newMinCol < oldMinCol then
                            for row=newMinRow,newMaxRow do
                                local newRow = visibleTileGroups[row]
                                if newRow == nil then
                                    newRow = {}
                                    visibleTileGroups[row] = newRow
                                end
                                for col=newMinCol,min(oldMinCol - 1,newMaxCol) do
                                    local tileRow = tiles[row]
                                    if tileRow ~= nil then
                                        local tile = tileRow[col]
                                        -- Check for nil tile is needed for corner cases where a corner would be added
                                        -- by multiple handlers
                                        if tile ~= nil and newRow[col] == nil then
                                            local newGroup = getTileDisplayObject(curLayer, tile, row, col)
                                            if newGroup ~= nil then
                                                newGroup.x = (col - 1) * tileSize + halfTileSize
                                                newGroup.y = (row - 1) * tileSize + halfTileSize
                                                newRow[col] = newGroup
                                                curTrimmedLayer.displayGroup:insert(newGroup)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        --endregion

                        --region Add new column(s) which have scrolled into view from right
                        if newMaxCol > oldMaxCol then
                            for row=newMinRow,newMaxRow do
                                local newRow = visibleTileGroups[row]
                                if newRow == nil then
                                    newRow = {}
                                    visibleTileGroups[row] = newRow
                                end
                                for col=max(oldMaxCol + 1, newMinCol),newMaxCol do
                                    local tileRow = tiles[row]
                                    if tileRow ~= nil then
                                        local tile = tileRow[col]
                                        -- Check for nil tile is needed for corner cases where a corner would be added
                                        -- by multiple handlers
                                        if tile ~= nil and newRow[col] == nil then
                                            local newGroup = getTileDisplayObject(curLayer, tile, row, col)
                                            if newGroup ~= nil then
                                                newGroup.x = (col - 1) * tileSize + halfTileSize
                                                newGroup.y = (row - 1) * tileSize + halfTileSize
                                                newRow[col] = newGroup
                                                curTrimmedLayer.displayGroup:insert(newGroup)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        --endregion

                        -- Update stale lighting data
                        if activeModule.lightingModel.hasAmbientLightChanged() then
                            --region When ambient light has changed, update all visible tiles.
                            for ambientChangeRow=newMinRow,newMaxRow do
                                for ambientChangeCol=newMinCol,newMaxCol do
                                    local rowArray = visibleTileGroups[ambientChangeRow]
                                    if rowArray ~= nil then
                                        local ambientChangeGroup = rowArray[ambientChangeCol]
                                        if ambientChangeGroup ~= nil then
                                            local layerLightingMode = curLayer.lightingMode
                                            if layerLightingMode == LayerConstants.LIGHTING_MODE_APPLY_ALL then
                                                local light = activeModule.lightingModel.getAggregateLight(ambientChangeRow, ambientChangeCol)
                                                ambientChangeGroup:setFillColor(light.r, light.g, light.b)
                                            elseif layerLightingMode == LayerConstants.LIGHTING_MODE_AMBIENT_ONLY then
                                                local light = activeModule.lightingModel.getAmbientLight()
                                                ambientChangeGroup:setFillColor(light.r, light.g, light.b)
                                            elseif layerLightingMode ~= LIGHTING_MODE_NONE then
                                                error "Unsupported lighting mode."
                                            end
                                        end
                                    end
                                end
                            end
                            --endregion
                        elseif activeModule.lightingModel.hasDirtyAggregateTile() then
                            --region Where there are dirty aggregate tile(s), update them
                            local dirtyLitRows = activeModule.lightingModel.getDirtyAggregateRows()
                            local dirtyLitColumns = activeModule.lightingModel.getDirtyAggregateColumns()
                            for i=1,activeModule.lightingModel.getDirtyAggregateCount() do
                                local dirtyLitRow = dirtyLitRows[i]
                                local dirtyLitColumn = dirtyLitColumns[i]
                                local rowArray = visibleTileGroups[dirtyLitRow]
                                if rowArray ~= nil then
                                    local dirtyLitGroup = rowArray[dirtyLitColumn]
                                    if dirtyLitGroup ~= nil then
                                        local layerLightingMode = curLayer.lightingMode
                                        if layerLightingMode == LayerConstants.LIGHTING_MODE_APPLY_ALL then
                                            local light = activeModule.lightingModel.getAggregateLight(dirtyLitRow, dirtyLitColumn)
                                            dirtyLitGroup:setFillColor(light.r, light.g, light.b)
                                        elseif layerLightingMode == LayerConstants.LIGHTING_MODE_AMBIENT_ONLY then
                                            local light = activeModule.lightingModel.getAmbientLight()
                                            dirtyLitGroup:setFillColor(light.r, light.g, light.b)
                                        elseif layerLightingMode ~= LIGHTING_MODE_NONE then
                                            error "Unsupported lighting mode."
                                        end
                                    end
                                end
                            end
                            --endregion
                        end

                        if hideOutOfSightElements then
                            if not activeModule.losModel.useTransitioners then
                                -- region Update transitions into line of sight
                                local rowsTransitionedIn = activeModule.losModel.getRowsTransitionedIn()
                                local colsTransitionedIn = activeModule.losModel.getColsTransitionedIn()
                                for i=1,#rowsTransitionedIn do
                                    local row = rowsTransitionedIn[i]
                                    local col = colsTransitionedIn[i]
                                    local rowArray = visibleTileGroups[row]
                                    if rowArray ~= nil then
                                        local group = rowArray[col]
                                        if group ~= nil then
                                            local layerLightingMode = curLayer.lightingMode
                                            if layerLightingMode == LayerConstants.LIGHTING_MODE_APPLY_ALL then
                                                local light = activeModule.lightingModel.getAggregateLight(row, col)
                                                group:setFillColor(light.r, light.g, light.b)
                                                group.alpha = 1
                                            elseif layerLightingMode == LayerConstants.LIGHTING_MODE_AMBIENT_ONLY then
                                                local light = activeModule.lightingModel.getAmbientLight()
                                                group:setFillColor(light.r, light.g, light.b)
                                                group.alpha = 1
                                            elseif layerLightingMode ~= LIGHTING_MODE_NONE then
                                                error "Unsupported lighting mode."
                                            end
                                        end
                                    end
                                end
                                -- endregion

                                -- region Update transitions out of line of sight
                                local rowsTransitionedOut = activeModule.losModel.getRowsTransitionedOut()
                                local colsTransitionedOut = activeModule.losModel.getColsTransitionedOut()
                                for i=1,#rowsTransitionedOut do
                                    local row = rowsTransitionedOut[i]
                                    local col = colsTransitionedOut[i]
                                    local rowArray = visibleTileGroups[row]
                                    if rowArray ~= nil then
                                        local group = rowArray[col]
                                        if group ~= nil then
                                            group.alpha = 0
                                        end
                                    end
                                end
                                -- endregion
                            else
                                local dirtyRows = activeModule.losModel.getDirtyRows()
                                local dirtyCols = activeModule.losModel.getDirtyColumns()
                                local dirtyCount = activeModule.losModel.getDirtyCount()
                                for i=1,dirtyCount do
                                    local row = dirtyRows[i]
                                    local col = dirtyCols[i]
                                    local rowArray = visibleTileGroups[row]
                                    if rowArray ~= nil then
                                        local group = rowArray[col]
                                        if group ~= nil then
                                            group.alpha = activeModule.losModel.getLineOfSightTransitionValue(row, col)
                                        end
                                    end
                                end
                            end
                        end

                        --endregion
                    else
                        --region When first run, there is no need to identify cells that have moved into or out of the view.  Simply create all cells that will be visible.
                        local visibleTileGroups = {}
                        curTrimmedLayer.visibleTilesInfo = {}
                        curTrimmedLayer.visibleTilesInfo.visibleTileGroups = visibleTileGroups
                        for row=newMinRow,newMaxRow do
                            local newRow = visibleTileGroups[row]
                            if newRow == nil then
                                newRow = {}
                                visibleTileGroups[row] = newRow
                            end
                            for col=newMinCol,newMaxCol do
                                local tileRow = tiles[row]
                                if tileRow ~= nil then
                                    local tile = tileRow[col]
                                    if tile ~= nil then
                                        local newGroup = getTileDisplayObject(curLayer, tile, row, col)
                                        if newGroup ~= nil then
                                            newGroup.x = (col - 1) * tileSize + halfTileSize
                                            newGroup.y = (row - 1) * tileSize + halfTileSize
                                            newRow[col] = newGroup
                                            curTrimmedLayer.displayGroup:insert(newGroup)
                                        end
                                    end
                                end
                            end
                        end
                        --endregion
                    end

                    --region Update lighting for non-transparent tiles to account for current viewing location
                    if compensateLightingForViewingPosition then
                        local visibleTileGroups = curTrimmedLayer.visibleTilesInfo.visibleTileGroups
                        for opaqueResourceCheckRow =newMinRow,newMaxRow do
                            for opaqueResourceCheckCol =newMinCol,newMaxCol do
                                local light = activeModule.lightingModel.getAggregateLightIfRowColumnOpaque(opaqueResourceCheckRow, opaqueResourceCheckCol, cameraRow, cameraCol)
                                if light ~= nil then
                                    local rowArray = visibleTileGroups[opaqueResourceCheckRow]
                                    if rowArray ~= nil then
                                        local group = rowArray[opaqueResourceCheckCol]
                                        if group ~= nil then
                                            group:setFillColor(light.r, light.g, light.b)
                                        end
                                    end
                                end
                            end
                        end
                    end
                    --endregion

                    -- Update current row/col min/max values
                    curTrimmedLayer.visibleTilesInfo.minCol = newMinCol
                    curTrimmedLayer.visibleTilesInfo.maxCol = newMaxCol
                    curTrimmedLayer.visibleTilesInfo.minRow = newMinRow
                    curTrimmedLayer.visibleTilesInfo.maxRow = newMaxRow
                end
            end
            camera.setLayerDirty(false)
            camera.setZoomDirty(false)
            camera.setLocationDirty(false)
        end
        --region Update tint on entities based on current lighting model
        for i=1,#trimmedLayers do
            -- Localize current layer from module
            local curLayer = module.layers[i].layer
            if curLayer.type == LAYER_ENTITY then
                local entityInfos = curLayer.getEntityInfos()
                for k,v in pairs(entityInfos) do
                    local imageRect = v.imageRect
                    local row = floor(imageRect.y / tileSize) + 1
                    local column = floor(imageRect.x / tileSize) + 1
                    local lineOfSightTransitionValue = activeModule.losModel.getLineOfSightTransitionValue(row, column)
                    local layerLightingMode = curLayer.lightingMode
                    if layerLightingMode == LayerConstants.LIGHTING_MODE_APPLY_ALL then
                        local aggregateLight = activeModule.lightingModel.getAggregateLight(row, column)
                        imageRect:setFillColor(aggregateLight.r, aggregateLight.g, aggregateLight.b)
                        imageRect.alpha = lineOfSightTransitionValue
                    elseif layerLightingMode == LayerConstants.LIGHTING_MODE_AMBIENT_ONLY then
                        local ambientLight = activeModule.lightingModel.getAmbientLight()
                        imageRect:setFillColor(ambientLight.r, ambientLight.g, ambientLight.b)
                        imageRect.alpha = lineOfSightTransitionValue
                    elseif layerLightingMode ~= LIGHTING_MODE_NONE then
                        error "Unsupported lighting mode."
                    end
                end
            end
        end
        --endregion
    end

    function self.isTileVisibleInLayer(layerIndex, row, column)
        local trimmedLayer = trimmedLayers[layerIndex]
        local visibleTilesInfo = trimmedLayer.visibleTilesInfo
        return row >= visibleTilesInfo.minRow
                and row <= visibleTilesInfo.maxRow
                and column >= visibleTilesInfo.minCol
                and column <= visibleTilesInfo.maxCol
    end

    function self.addModule(params)
        requireParams({"module"}, params)
        modules[params.module.name] = params.module
    end

    function self.removeModule(params)
        requireParams({"moduleName"}, params)
        local removedModule = modules[params.moduleName]
        modules[params.moduleName] = nil
        return removedModule
    end

    function self.setActiveModule(params)
        requireParams({"moduleName"}, params)

        if trimmedLayers ~= nil then
            for i=1,#trimmedLayers do
                local curTrimmedLayer = trimmedLayers[i]
                if curTrimmedLayer.visibleTilesInfo ~= nil then
                    local minCol = curTrimmedLayer.visibleTilesInfo.minCol
                    local maxCol = curTrimmedLayer.visibleTilesInfo.maxCol
                    local minRow = curTrimmedLayer.visibleTilesInfo.minRow
                    local maxRow = curTrimmedLayer.visibleTilesInfo.maxRow
                    for row=minRow,maxRow do
                        local curRow = curTrimmedLayer.visibleTilesInfo.visibleTileGroups[row]
                        if curRow ~= nil then
                            for col=minCol,maxCol do
                                local tileGroup = curRow[col]
                                if tileGroup ~= nil then
                                    tileGroup:removeSelf()
                                end
                            end
                        end
                    end
                end
            end
            trimmedLayers = nil
        end

        activeModule = modules[params.moduleName]
        for k,v in pairs(modules) do
            if v ~= activeModule then
                v.deactivate()
            end
        end
        activeModule.activate()
    end

    function self.getActiveModule()
        return activeModule
    end

    function self.update(params)
        requireParams({"timeDelta"}, params)
    end

    function self.render(camera)
        local halfPixelWidth = camera.pixelWidth / 2
        local halfPixelHeight = camera.pixelHeight / 2
        updateVisibilityInfo(camera, activeModule)
        for layerIndex=1,#trimmedLayers do
            local trimmedLayer = trimmedLayers[layerIndex]
            local layerGroup = trimmedLayer.displayGroup
            local cameraAdjustedScale = trimmedLayer.scale * camera.getZoom()
            layerGroup.anchorX = 0
            layerGroup.anchorY = 0
            layerGroup.xScale = cameraAdjustedScale
            layerGroup.yScale = cameraAdjustedScale
            layerGroup.x = -trimmedLayer.adjustedCamX * tileSize * cameraAdjustedScale
            layerGroup.y = -trimmedLayer.adjustedCamY * tileSize * cameraAdjustedScale
        end
    end

    -- pixel x,y assume origin at top left of viewport.
    function self.getCoordinateAtPixelInLayer(camera, pixelX, pixelY, layerIndex)
        -- Layer group has been adjusted based on its scrolling coefficients,
        -- offset, scale, camera position, and camera zoom.  This is utilized
        -- to determine the tile coordinate.
        local trimmedLayer = trimmedLayers[layerIndex]
        local layerGroup = trimmedLayer.displayGroup
        local left = -layerGroup.x / layerGroup.xScale - (camera.pixelWidth / layerGroup.xScale / 2)
        local top = -layerGroup.y / layerGroup.yScale - (camera.pixelHeight / layerGroup.yScale / 2)
        local layerPixelX = left + pixelX / layerGroup.xScale
        local layerPixelY = top + pixelY / layerGroup.yScale
        local layerRow = layerPixelY / tileSize
        local layerColumn = layerPixelX / tileSize
        return layerRow, layerColumn
    end

    function self.getMasterGroup()
        return masterGroup
    end

    function self.getTileSize()
        return tileSize
    end

    function self.destroy()
        spriteResolver = nil

        if #modules > 0 then
            for i=1,#modules do
                modules[i].destroy()
            end
        end
        modules = nil

        activeModule = nil

        masterGroup:removeSelf()
        masterGroup = nil

        trimmedLayers = nil
    end

    return self
end



return {
    Engine = Engine,
    Camera = Camera,
    Module = Module,
    TileSelectionLayer = TileSelectionLayer,
    EntityLayer = EntityLayer,
    Layer = Layer,
    LayerConstants = LayerConstants,
    Tile = Tile,
    SpriteInfo = SpriteInfo
}