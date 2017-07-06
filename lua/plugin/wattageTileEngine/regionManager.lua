local TileEngine = require "plugin.wattageTileEngine.tileEngine"
local Utils = require "plugin.wattageTileEngine.utils"

local Class = {}
Class.new = function(params)
    Utils.requireParams({
        "regionWidthInTiles",
        "regionHeightInTiles",
        "renderRegionWidth",
        "renderRegionHeight",
        "tileSize",
        "tileLayersByIndex",
        "entityLayersByIndex",
        "camera",
        "listener"
    }, params)

    local regionWidthInTiles = params.regionWidthInTiles
    local regionHeightInTiles = params.regionHeightInTiles
    local renderRegionWidth = params.renderRegionWidth
    local renderRegionHeight = params.renderRegionHeight
    local tileSize = params.tileSize
    local tileLayersByIndex = params.tileLayersByIndex
    local entityLayersByIndex = params.entityLayersByIndex
    local camera = params.camera
    local listener = params.listener

    local self = {}

    local cameraWorldX          -- The world X position of the camera
    local cameraWorldY          -- The world Y position of the camera
    local regionsCache          -- Stores the local region coords of filled regions
    local activeRegionRowOffsetInTiles  -- Stores the row offset of the active region in tiles
    local activeRegionColOffsetInTiles  -- Stores the col offset of the active region in tiles
    local activeRegionRowOffsetInPoints -- Stores the row offset of the active region in points
    local activeRegionColOffsetInPoints -- Stores the col offset of the active region in points
    local activeRegionWidth             -- The active region width in regions
    local activeRegionHeight            -- The active region height in regions
    local activeRegionsWidthInTiles     -- Number of horizontal tiles within the active region of the buffer layer
    local activeRegionsHeightInTiles    -- Number of vertical tiles within the active region of the buffer layer
    local activeRegionWidthInPoints     -- Width of the active region in points
    local activeRegionHeightInPoints    -- Height of the active region in points
    local subRegions            -- Stores the layer sub regions
    local regionsHigh           -- Number of vertical regions in layer
    local regionsWide           -- Number of horizontal regions in layer

    local floor = math.floor

    ---
    -- Class which represents a sub region
    --
    local SubRegion = {}
    SubRegion.new = function(params)
        Utils.requireParams({
            "regionRow",
            "regionCol",
            "topLayerRowOffset",
            "leftLayerColOffset"
        }, params)

        local regionRow = params.regionRow
        local regionCol = params.regionCol
        local topLayerRowOffset = params.topLayerRowOffset
        local leftLayerColOffset = params.leftLayerColOffset

        local self = {}

        local regionData

        function self.paint(absoluteRegionRow, absoluteRegionCol)
            -- Check to see if the region is cached and render only if it is not
            local cacheRow = regionsCache.array[regionRow]
            if cacheRow == nil then
                cacheRow = {}
                regionsCache.array[regionRow] = cacheRow
            end
            local regionCache = cacheRow[regionCol]
            if regionCache == nil then
                regionCache = {}
                cacheRow[regionCol] = regionCache
            end
            if regionCache.absoluteRegionRow ~= absoluteRegionRow
                    or regionCache.absoluteRegionCol ~= absoluteRegionCol then
                -- not cached so update cache
                regionCache.absoluteRegionRow = absoluteRegionRow
                regionCache.absoluteRegionCol = absoluteRegionCol

                -- inform listener that old region data is being released (if there is any)
                if regionData ~= nil then
                    listener.regionReleased(regionData)
                end

                -- query for new region data from the listener
                regionData = listener.getRegion({
                    absoluteRegionRow = absoluteRegionRow,
                    absoluteRegionCol = absoluteRegionCol,
                    topRowOffset = topLayerRowOffset,
                    leftColumnOffset = leftLayerColOffset
                })

                -- update tile layers
                if regionData ~= nil and regionData.tilesByLayerIndex ~= nil then
                    for layerIndex, tiles in pairs(regionData.tilesByLayerIndex) do
                        local layer = tileLayersByIndex[layerIndex]
                        for sourceRow=1,regionHeightInTiles do
                            local targetRow = topLayerRowOffset + sourceRow
                            for sourceCol=1,regionWidthInTiles do
                                local targetCol = leftLayerColOffset + sourceCol
                                local value = tiles[sourceRow][sourceCol]
                                if value ~= nil then
                                    layer.updateTile(targetRow, targetCol, TileEngine.Tile.new({
                                        resourceKey = value
                                    }))
                                else
                                    layer.updateTile(targetRow, targetCol, nil)
                                end
                            end
                        end
                    end
                else
                    for layerIndex, layer in pairs(tileLayersByIndex) do
                        for sourceRow=1,regionHeightInTiles do
                            local targetRow = topLayerRowOffset + sourceRow
                            for sourceCol=1,regionWidthInTiles do
                                local targetCol = leftLayerColOffset + sourceCol
                                layer.updateTile(targetRow, targetCol, nil)
                            end
                        end
                    end
                end
            end
        end

        function self.destroy()
            if regionData ~= nil then
                listener.regionReleased(regionData)
            end
            regionData = nil
        end

        return self
    end

    ---
    -- @param worldX the continuous camera position in column units
    -- @param worldY the continuous camera position in row units
    --
    function self.setCameraLocation(worldX, worldY)
        -- Determine previous layer region row and column 0-based
        local prevLayerRegionRow = floor(cameraWorldY / activeRegionsHeightInTiles)
        local prevLayerRegionCol = floor(cameraWorldX / activeRegionsWidthInTiles)

        -- Determine current layer region row and column
        local curLayerRegionRow = floor(worldY / activeRegionsHeightInTiles)
        local curLayerRegionCol = floor(worldX / activeRegionsWidthInTiles)

        -- If we have moved to a different layer region, then invalidate the region cache and shift entities
        if curLayerRegionRow ~= prevLayerRegionRow or curLayerRegionCol ~= prevLayerRegionCol then
            regionsCache.array = {}    -- invalidates the region cache

            --region Shift resource and non-resource entities
            local layerRegionRowDelta = curLayerRegionRow - prevLayerRegionRow
            local layerRegionColDelta = curLayerRegionCol - prevLayerRegionCol

            local yOffset = -layerRegionRowDelta * activeRegionHeightInPoints
            local xOffset = -layerRegionColDelta * activeRegionWidthInPoints
            for layerIndex,layer in pairs(entityLayersByIndex) do
                local entityInfos = layer.getEntityInfos()
                for entityId, info in pairs(entityInfos) do
                    local sprite = info.imageRect
                    sprite.x = sprite.x + xOffset
                    sprite.y = sprite.y + yOffset
                end

                local nonResourceEntities = layer.getNonResourceEntities()
                for entityId, entity in pairs(nonResourceEntities) do
                    entity.x = entity.x + xOffset
                    entity.y = entity.y + yOffset
                end
            end
            --endregion
        end

        -- Determine the row and column relative to the active region which contains the camera (0-based)
        local cameraActiveRegionRow = floor(worldY) % activeRegionsHeightInTiles
        local cameraActiveRegionCol = floor(worldX) % activeRegionsWidthInTiles

        -- Determine the row and column of the region relative to the active area which contains the camera (0-based)
        local cameraActiveAreaSubRegionRow = floor(cameraActiveRegionRow / regionHeightInTiles)
        local cameraActiveAreaSubRegionCol = floor(cameraActiveRegionCol / regionWidthInTiles)

        -- Determine the row and column of the sub region relative to the layer which contains the camera (0-based)
        local cameraSubRegionRow = cameraActiveAreaSubRegionRow + floor(renderRegionHeight / 2)
        local cameraSubRegionCol = cameraActiveAreaSubRegionCol + floor(renderRegionWidth / 2)

        -- Determine absolute region row and column 0-based
        local absoluteRegionRow = floor(worldY / regionHeightInTiles)
        local absoluteRegionCol = floor(worldX / regionWidthInTiles)

        -- Fill center region and surrounding regions to configured render region width and height
        local minSubRegionRow = cameraSubRegionRow - floor(renderRegionHeight / 2)
        local maxSubRegionRow = cameraSubRegionRow + floor(renderRegionHeight / 2)
        local minSubRegionCol = cameraSubRegionCol - floor(renderRegionWidth / 2)
        local maxSubRegionCol = cameraSubRegionCol + floor(renderRegionWidth / 2)

        local curAbsoluteRegionRow = absoluteRegionRow - floor(renderRegionHeight / 2)
        local curAbsoluteRegionCol = absoluteRegionCol - floor(renderRegionWidth / 2)
        for subRegionRow=minSubRegionRow,maxSubRegionRow do
            for subRegionCol=minSubRegionCol,maxSubRegionCol do
                local subRegion = subRegions[subRegionRow][subRegionCol]
                subRegion.paint(curAbsoluteRegionRow, curAbsoluteRegionCol)
                curAbsoluteRegionCol = curAbsoluteRegionCol + 1
            end
            curAbsoluteRegionCol = absoluteRegionCol - floor(renderRegionWidth / 2)
            curAbsoluteRegionRow = curAbsoluteRegionRow + 1
        end

        cameraWorldX = worldX
        cameraWorldY = worldY

        local activeRegionRowOffset = floor(renderRegionHeight / 2) * regionHeightInTiles
        local activeRegionColOffset = floor(renderRegionWidth / 2) * regionWidthInTiles
        local cameraLocalX = (cameraWorldX - curLayerRegionCol * activeRegionsWidthInTiles) + activeRegionColOffset
        local cameraLocalY = (cameraWorldY - curLayerRegionRow * activeRegionsHeightInTiles) + activeRegionRowOffset
        camera.setLocation(cameraLocalX, cameraLocalY)
    end

    function self.centerEntityOnTile(entityLayerIndex, entityId, worldRow, worldColumn)
        self.setEntityLocation(
            entityLayerIndex, entityId, (worldColumn + 0.5) * tileSize, (worldRow + 0.5) * tileSize)
    end

    function self.centerNonResourceEntityOnTile(entityLayerIndex, entityId, worldRow, worldColumn)
        self.setNonResourceEntityLocation(
            entityLayerIndex, entityId, (worldColumn + 0.5) * tileSize, (worldRow + 0.5) * tileSize)
    end

    function self.getEntityLocation(entityLayerIndex, entityId)
        local entityLayer = entityLayersByIndex[entityLayerIndex]
        local sprite = entityLayer.getEntityInfo(entityId).imageRect
        local curLayerRegionRow = floor(cameraWorldY / activeRegionsHeightInTiles)
        local curLayerRegionCol = floor(cameraWorldX / activeRegionsWidthInTiles)
        local pointRowOffset = curLayerRegionRow * activeRegionHeightInPoints
        local pointColOffset = curLayerRegionCol * activeRegionWidthInPoints
        local x = sprite.x - activeRegionColOffsetInPoints + pointColOffset
        local y = sprite.y - activeRegionRowOffsetInPoints + pointRowOffset
        return x, y
    end

    function self.getNonResourceEntityLocation(entityLayerIndex, entityId)
        local entityLayer = entityLayersByIndex[entityLayerIndex]
        local sprite = entityLayer.getNonResourceEntities()[entityId]
        local curLayerRegionRow = floor(cameraWorldY / activeRegionsHeightInTiles)
        local curLayerRegionCol = floor(cameraWorldX / activeRegionsWidthInTiles)
        local pointRowOffset = curLayerRegionRow * activeRegionHeightInPoints
        local pointColOffset = curLayerRegionCol * activeRegionWidthInPoints
        local x = sprite.x - activeRegionColOffsetInPoints + pointColOffset
        local y = sprite.y - activeRegionRowOffsetInPoints + pointRowOffset
        return x, y
    end

    function self.setEntityLocation(entityLayerIndex, entityId, worldX, worldY)
        local entityLayer = entityLayersByIndex[entityLayerIndex]
        local sprite = entityLayer.getEntityInfo(entityId).imageRect
        local curLayerRegionRow = floor(cameraWorldY / activeRegionsHeightInTiles)
        local curLayerRegionCol = floor(cameraWorldX / activeRegionsWidthInTiles)
        local pointRowOffset = curLayerRegionRow * activeRegionHeightInPoints
        local pointColOffset = curLayerRegionCol * activeRegionWidthInPoints
        sprite.x = worldX - pointColOffset + activeRegionColOffsetInPoints
        sprite.y = worldY - pointRowOffset + activeRegionRowOffsetInPoints
    end

    function self.setNonResourceEntityLocation(entityLayerIndex, entityId, worldX, worldY)
        local entityLayer = entityLayersByIndex[entityLayerIndex]
        local sprite = entityLayer.getNonResourceEntities()[entityId]
        local curLayerRegionRow = floor(cameraWorldY / activeRegionsHeightInTiles)
        local curLayerRegionCol = floor(cameraWorldX / activeRegionsWidthInTiles)
        local pointRowOffset = curLayerRegionRow * activeRegionHeightInPoints
        local pointColOffset = curLayerRegionCol * activeRegionWidthInPoints
        sprite.x = worldX - pointColOffset + activeRegionColOffsetInPoints
        sprite.y = worldY - pointRowOffset + activeRegionRowOffsetInPoints
    end

    function self.destroy()
        for subRegionRow=0,regionsHigh - 1 do
            for subRegionCol=0,regionsWide - 1 do
                subRegions[subRegionRow][subRegionCol].destroy()
            end
        end
        subRegions = nil
    end

    local function init()
        --region Validations
        local rowCount
        local colCount

        --region Validate that all tile layers have the same dimension
        for layerIndex,tileLayer in pairs(tileLayersByIndex) do
            if rowCount == nil then
                rowCount = tileLayer.getRows()
            end
            if colCount == nil then
                colCount = tileLayer.getColumns()
            end

            if rowCount ~= tileLayer.getRows() or colCount ~= tileLayer.getColumns() then
                error "Tile layers must all be the same dimensions"
            end
        end
        --endregion

        --region Validate that layer dimensions are divisible by 2
        if rowCount % 2 ~= 0 or colCount % 2 ~= 0 then
            error "Layer dimensions must be even"
        end
        --endregion

        --region Validate that layer height is evenly divisible by region height
        if rowCount % regionHeightInTiles ~= 0 then
            error "Layer row count must be evenly divisible by region height"
        end
        --endregion

        --region Validate that the number of regions high is divisible by 2
        local regionHeight = rowCount / regionHeightInTiles
        if regionHeight % 2 ~= 0 then
            error "Number of region rows in layer must be an even number"
        end
        --endregion

        --region Validate that layer width is evenly divisible by region width
        if colCount % regionWidthInTiles ~= 0 then
            error "Layer column count must be evenly divisible by region width"
        end
        --endregion

        --region Validate that the number of regions wide is divisible by 2
        local regionWidth = colCount / regionWidthInTiles
        if regionWidth % 2 ~= 0 then
            error "Number of region columns in layer must be an even number"
        end
        --endregion

        --region Validate that render region width is an odd number
        if renderRegionWidth % 2 == 0 then
            error "Render Region Width must be an odd number"
        end
        --endregion

        --region Validate that render region height is an odd number
        if renderRegionHeight % 2 == 0 then
            error "Render Region Height must be an odd number"
        end
        --endregion

        --region Validate layer width is at least three times render region width
        if regionWidth < (3 * renderRegionWidth) then
            error "Layer width must be at least 3 times render region width"
        end
        --endregion

        --region Validate layer height is at least three times render region height
        if regionHeight < (3 * renderRegionHeight) then
            error "Layer height must be at least 3 times render region height"
        end
        --endregion

        --endregion

        cameraWorldX = 0
        cameraWorldY = 0
        regionsCache = {
            array = {}
        }

        local leftRightEdgeRegionCount = floor(renderRegionWidth / 2)
        local topBottomEdgeRegionCount = floor(renderRegionHeight / 2)
        activeRegionRowOffsetInTiles = topBottomEdgeRegionCount * regionHeightInTiles
        activeRegionColOffsetInTiles = leftRightEdgeRegionCount * regionWidthInTiles
        activeRegionRowOffsetInPoints = activeRegionRowOffsetInTiles * tileSize
        activeRegionColOffsetInPoints = activeRegionColOffsetInTiles * tileSize
        activeRegionWidth = regionWidth - leftRightEdgeRegionCount * 2
        activeRegionHeight = regionHeight - topBottomEdgeRegionCount * 2
        activeRegionsWidthInTiles = activeRegionWidth * regionWidthInTiles
        activeRegionsHeightInTiles = activeRegionHeight * regionHeightInTiles
        activeRegionWidthInPoints = activeRegionsWidthInTiles * tileSize
        activeRegionHeightInPoints = activeRegionsHeightInTiles * tileSize

        regionsHigh = regionHeight
        regionsWide = regionWidth

        subRegions = {}
        for row=0,regionsHigh - 1 do
            for col=0,regionsWide - 1 do
                local subRegionRow = subRegions[row]
                if subRegionRow == nil then
                    subRegionRow = {}
                    subRegions[row] = subRegionRow
                end
                subRegionRow[col] = SubRegion.new({
                    regionRow = row,
                    regionCol = col,
                    topLayerRowOffset = row * regionHeightInTiles,
                    leftLayerColOffset = col * regionWidthInTiles
                })
            end
        end
    end

    init()

    return self
end

return Class