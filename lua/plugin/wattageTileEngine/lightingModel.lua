local Los = require "plugin.wattageTileEngine.lineOfSight"
local ObjectSystem = require "plugin.wattageTileEngine.objectSystem"
local Utils = require "plugin.wattageTileEngine.utils"

local min = math.min

local AggregateLightTransitioner = {}
AggregateLightTransitioner.new = function(params)
    local self = {}

    self.index = params.index
    local aggregateLightByCoordinate = params.aggregateLightByCoordinate
    local transitionerTargetCoordinates = params.transitionerTargetCoordinates
    self.row = params.row
    self.column = params.column
    local startR = params.startR
    local startG = params.startG
    local startB = params.startB
    local endR = params.endR
    local endG = params.endG
    local endB = params.endB
    local transitionTime = params.transitionTime
    self.transitionerIndexesForRemoval = params.transitionerIndexesForRemoval
    local elapsedTime = 0

    local diffR = endR - startR
    local diffG = endG - startG
    local diffB = endB - startB
    local curR = startR
    local curG = startG
    local curB = startB

    function self.resetIfChanged(params)
        if endR ~= params.endR or endG ~= params.endG or endB ~= params.endB then
            startR = curR
            startG = curG
            startB = curB
            endR = params.endR
            endG = params.endG
            endB = params.endB
            diffR = endR - startR
            diffG = endG - startG
            diffB = endB - startB
            elapsedTime = 0
        end
    end

    function self.getEndRGB()
        return {r = endR, g = endG, b = endB}
    end

    function self.forceFinish()
        elapsedTime = transitionTime
        self.update(0)
    end

    function self.update(deltaTime)
        elapsedTime = elapsedTime + deltaTime

        curR = startR + (elapsedTime / transitionTime) * diffR
        curG = startG + (elapsedTime / transitionTime) * diffG
        curB = startB + (elapsedTime / transitionTime) * diffB

        if elapsedTime >= transitionTime then
            curR = endR
            curG = endG
            curB = endB
            startR = endR
            startG = endG
            startB = endB
            table.insert(self.transitionerIndexesForRemoval, self.index)
            table.insert(transitionerTargetCoordinates, {row = self.row, column = self.column})
        else
            table.insert(transitionerTargetCoordinates, {row = self.row, column = self.column})
        end

        local columns = aggregateLightByCoordinate[self.row]
        if columns == nil then
            columns = {}
            aggregateLightByCoordinate[self.row] = columns
        end

        local cell = columns[self.column]
        if cell == nil then
            cell = {}
            columns[self.column] = cell
        end

        cell.r = curR
        cell.g = curG
        cell.b = curB
    end

    return self
end

local LightingModel = {}
LightingModel.objectType = "LightingModel"
LightingModel.new = function(params)
    local requireParams = Utils.requireParams
    requireParams({
        "isTransparent",
        "isTileAffectedByAmbient",
        "useTransitioners",
        "compensateLightingForViewingPosition"
    }, params)

    local isTransparentCallback = params.isTransparent
    local isTileAffectedByAmbientCallback = params.isTileAffectedByAmbient
    local useTransitioners = params.useTransitioners
    local compensateLightingForViewingPosition = params.compensateLightingForViewingPosition

    local self = ObjectSystem.Object.new({objectType=LightingModel.objectType})

    -- Tracks next available light ID to assign to new lights
    local nextLightId

    -- Instance of line of sight module
    local lineOfSight

    -- Ambient Light
    local ambientRed
    local ambientGreen
    local ambientBlue
    local ambientIntensity

    -- Dirty coordinates
    local ambientLightChanged                           -- This is true if the ambient lighting has changed.  This is necessary since a change in the ambient lighting changes all lighting tiles and requires a resync with the tile engine.
    local dirtyAggregateUniqueIndex                     -- This is a table of tables.  The existence of a value in the table indicates that that coordinate has already been marked as dirty.
    local dirtyAggregateRows                            -- An array of row coordinates for dirty aggregate tiles.
    local dirtyAggregateColumns                         -- An array of column coordinates for dirty aggregate tiles.
    local dirtyAggregateIndex                           -- Tracks the next available index for dirtyAggregateRows and dirtyAggregateColumns.

    -- Stores aggregate light values
    local aggregateLightByCoordinate                    -- This is a table of tables representing rows of columns.  Each coordinate stores the corresponding aggregated lighting value.
    local transparencyStateByRow

    -- Stores the aggregate light transitioners
    local aggregateLightTransitionerByCoordinate        -- This stores the transitioners for aggregate lighting.
    local activeTransitioners                           -- Stores the active transitioners
    local transitionerIndexesForRemoval                 -- Stores the indexes of the transitioners that can be removed from the active transitioner list.
    local transitionerTargetCoordinates                 -- Stores tile coordinates of the tiles affected by the transitioners.  This is necessary to notify tiles to update their tint.

    -- Stores IDs for dirty lights
    local dirtyLightIds                                 -- This table stores the IDs of all lights that have been made dirty.

    -- Stores lights indexed by their ID
    local lightsById                                    -- Index of IDs to lights.

    -- Stores affected areas for each light by ID
    local affectedAreasByLightId                        -- Stores table of tables representing rows and columns of tiles holding data for how the light would affect that tile.

    -- Tracks current affected area for use in the callback
    local curLight                                      -- Reference to current light used during processing
    local curAffectedArea                               -- Reference to current affected area used during processing

    -- Marks the tile at the row/column coordinate as dirty and ensures uniqueness of entries.
    local function markDirtyAggregateTile(row, column)
        local uniqueRowIndex = dirtyAggregateUniqueIndex[row]
        if uniqueRowIndex ~= nil then
            if uniqueRowIndex[column] then
                return
            end
        else
            uniqueRowIndex = {}
            dirtyAggregateUniqueIndex[row] = uniqueRowIndex
        end

        uniqueRowIndex[column] = true
        dirtyAggregateRows[dirtyAggregateIndex] = row
        dirtyAggregateColumns[dirtyAggregateIndex] = column
        dirtyAggregateIndex = dirtyAggregateIndex + 1
    end

    -- Convenience function to clamp a value to a specified range.
    local function clamp(v, min, max)
        if v < min then
            return min
        end

        if v > max then
            return max
        end

        return v
    end

    -- Callback to light affected area
    local function fovCallback(x, y, distanceSquared, isTransparent)
        -- Record state of transparency if compensating for viewing position
        if compensateLightingForViewingPosition then
            local transparencyStateRow = transparencyStateByRow[y]
            if transparencyStateRow == nil then
                transparencyStateRow = {}
                transparencyStateByRow[y] = transparencyStateRow
            end
            transparencyStateRow[x] = isTransparent
        end

        local curAffectedRow = curAffectedArea[y]
        if curAffectedRow == nil then
            curAffectedRow = {}
            curAffectedArea[y] = curAffectedRow
        end

        -- New equation simple
        local attenuation = clamp(1.0 - distanceSquared / (curLight.radius * curLight.radius), 0, 1)
        attenuation = attenuation * attenuation

        -- New equation not as simple
        --    local attenuation = clamp(1.0 - ((distance * distance) / (curLight.radius * curLight.radius)), 0, 1)
        --    attenuation = attenuation * attenuation

        local adjustedIntensity = curLight.intensity * attenuation
        if adjustedIntensity > 0 then
            curLight.affectedRows[curLight.affectedIndex] = y
            curLight.affectedColumns[curLight.affectedIndex] = x
            curLight.affectedIndex = curLight.affectedIndex + 1

            curAffectedRow[x] = {
                adjustedIntensity = adjustedIntensity
            }
            markDirtyAggregateTile(y, x)
        end
    end

    -- Inserts light ID into the dirty list if it does not already exist.
    local function markLightAsDirty(lightId)
        local found = false
        for i=1,#dirtyLightIds do
            if lightId == dirtyLightIds[i] then
                found = true
            end
        end
        if not found then
            table.insert(dirtyLightIds, lightId)
        end
    end

    -- Marks all lights as dirty
    local function markAllLightsAsDirty()
        dirtyLightIds = {}
        local index = 1
        for k,v in pairs(lightsById) do
            dirtyLightIds[index] = k
            index = index + 1
        end
    end

    -- Marks the affected tiles of the light as dirty
    local function markAggregateTilesAffectedByLightAsDirty(id)
        local light = lightsById[id]
        local affectedRows = light.affectedRows
        local affectedColumns = light.affectedColumns
        for i=1,light.affectedIndex - 1 do
            markDirtyAggregateTile(affectedRows[i], affectedColumns[i])
        end
    end

    -- Marks the corresponding aggregate tile as dirty for each of the current affected tiles of all lights
    local function markAllAggregateTilesAffectedByLightAsDirty()
        for id,light in pairs(lightsById) do
            local affectedRows = light.affectedRows
            local affectedColumns = light.affectedColumns
            for i=1,light.affectedIndex - 1 do
                markDirtyAggregateTile(affectedRows[i], affectedColumns[i])
            end
        end
    end

    function self.setUseTransitioners(useTransitionersParam)
        useTransitioners = useTransitionersParam

        if not useTransitioners then
            for i=1,#activeTransitioners do
                activeTransitioners[i].forceFinish()
            end

            for i=1,#transitionerTargetCoordinates do
                local coordinate = transitionerTargetCoordinates[i]
                markDirtyAggregateTile(coordinate.row, coordinate.column)
            end
        end
    end

    -- Will result in all aggregate tiles affected by light as dirty and set the ambientLightChanged flag to true
    function self.setAmbientLight(red, green, blue, intensity)
        if ambientRed ~= red
                or ambientGreen ~= green
                or ambientBlue ~= blue
                or ambientIntensity ~= intensity then
            ambientRed = red
            ambientGreen = green
            ambientBlue = blue
            ambientIntensity = intensity
            markAllAggregateTilesAffectedByLightAsDirty()
            ambientLightChanged = true
        end
    end

    function self.markChangeInTransparency(row, column)
        self.markLightAsDirtyIfAffectedAreaContainsTile(row, column)
        -- clear transparency cache
        local transparencyRow = transparencyStateByRow[row]
        if transparencyRow ~= nil then
            transparencyRow[column] = nil
        end
    end

    function self.getAmbientLight()
        return {
            r = math.min(ambientRed * ambientIntensity, 1),
            g = math.min(ambientGreen * ambientIntensity, 1),
            b = math.min(ambientBlue * ambientIntensity, 1),
            intensity = ambientIntensity
        }
    end

    function self.update(deltaTime)
        --region Update transitioners
        -- update transitioners
        for i=1,#activeTransitioners do
            activeTransitioners[i].update(deltaTime)
        end
        -- sort indexes
        table.sort(transitionerIndexesForRemoval)
        -- remove indexes
        for i=#transitionerIndexesForRemoval,1,-1 do
            local indexToRemove = transitionerIndexesForRemoval[i]
            local transitionerForRemoval = activeTransitioners[indexToRemove]
            if transitionerForRemoval ~= nil then
                markDirtyAggregateTile(transitionerForRemoval.row, transitionerForRemoval.column)
                aggregateLightTransitionerByCoordinate[transitionerForRemoval.row][transitionerForRemoval.column] = nil
                table.remove(activeTransitioners, indexToRemove)
            end
        end
        transitionerIndexesForRemoval = {}
        for i=1,#activeTransitioners do
            activeTransitioners[i].transitionerIndexesForRemoval = transitionerIndexesForRemoval
        end
        -- reset indexes
        for i=1,#activeTransitioners do
            activeTransitioners[i].index = i
        end
        --endregion

        --region Mark dirty aggregate coords resulting from dirty lights
        -- and clear current light affected areas
        for k,lightId in pairs(dirtyLightIds) do
            local light = lightsById[lightId]

            local affectedRows = light.affectedRows
            local affectedColumns = light.affectedColumns
            local affectedAreas = affectedAreasByLightId[lightId]
            if affectedAreas ~= nil then
                for curAffectedIndex=1,light.affectedIndex - 1 do
                    local row = affectedRows[curAffectedIndex]
                    local affectedRow = affectedAreas[row]
                    if affectedRow ~= nil then
                        local column = affectedColumns[curAffectedIndex]
                        if affectedRow[column] ~=  nil then
                            markDirtyAggregateTile(row, column)
                        end
                    end
                end
                affectedAreasByLightId[lightId] = {}
            end
            light.affectedRows = {}
            light.affectedColumns = {}
            light.affectedIndex = 1
        end
        --endregion

        --region Update affected areas for dirty lights
        for k,lightId in pairs(dirtyLightIds) do
            curLight = lightsById[lightId]
            curAffectedArea = affectedAreasByLightId[lightId]
            if curAffectedArea == nil then
                curAffectedArea = {}
                affectedAreasByLightId[lightId] = curAffectedArea
            end
            lineOfSight.calculateFov({
                startX = curLight.column,
                startY = curLight.row,
                radius = curLight.radius
            })
        end
        --endregion

        --region Aggregate dirty light data

        -- First get bounding region for dirty tiles
        local minRow
        local maxRow
        local minCol
        local maxCol

        for i=1,dirtyAggregateIndex - 1 do
            if minRow == nil then
                minRow = dirtyAggregateRows[i]
                maxRow = minRow
                minCol = dirtyAggregateColumns[i]
                maxCol = minCol
            else
                local curRow = dirtyAggregateRows[i]
                local curCol = dirtyAggregateColumns[i]
                if curRow < minRow then
                    minRow = curRow
                end
                if curRow > maxRow then
                    maxRow = curRow
                end
                if curCol < minCol then
                    minCol = curCol
                end
                if curCol > maxCol then
                    maxCol = curCol
                end
            end
        end

        local trimmedAffectedAreas = {}

        if minRow ~= nil then
            local halfWidth = (maxCol - minCol) / 2
            local halfHeight = (maxRow - minRow) / 2
            local boundingCenterCol = minCol + halfWidth
            local boundingCenterRow = minRow + halfHeight
            local boundingRadius = math.sqrt(halfWidth * halfWidth + halfHeight * halfHeight)

            for lightId,area in pairs(affectedAreasByLightId) do
                local light = lightsById[lightId]
                local lightRadius = light.radius
                local distanceRows = boundingCenterRow - light.row
                local distanceCols = boundingCenterCol - light.column
                local distance = math.sqrt(distanceRows * distanceRows + distanceCols * distanceCols)
                if distance <= boundingRadius + lightRadius then
                    table.insert(trimmedAffectedAreas, {
                        light = light,
                        area = area
                    })
                end
            end
        end

        for i=1,dirtyAggregateIndex - 1 do
            local aggregateRow = dirtyAggregateRows[i]
            local aggregateCol = dirtyAggregateColumns[i]
            local aggregateR = 0
            local aggregateG = 0
            local aggregateB = 0

            --region Calculate aggregate value
            local isAffectedByLight = false
            for i=1,#trimmedAffectedAreas do
                local entry = trimmedAffectedAreas[i]
                local areaRow = entry.area[aggregateRow]
                if areaRow ~= nil then
                    local areaTile = areaRow[aggregateCol]
                    if areaTile ~= nil then
                        local light = entry.light
                        local intensity = areaTile.adjustedIntensity
                        aggregateR = min(aggregateR + light.r * intensity, 1)
                        aggregateG = min(aggregateG + light.g * intensity, 1)
                        aggregateB = min(aggregateB + light.b * intensity, 1)
                        isAffectedByLight = true
                    end
                end
            end
            --endregion

            --region Store aggregate value
            local aggregateRowArray = aggregateLightByCoordinate[aggregateRow]
            if aggregateRowArray == nil then
                aggregateRowArray = {}
                aggregateLightByCoordinate[aggregateRow] = aggregateRowArray
            end
            local cell = aggregateRowArray[aggregateCol]

            if not isAffectedByLight then
                local transitionerRow = aggregateLightTransitionerByCoordinate[aggregateRow]
                if transitionerRow == nil then
                    transitionerRow = {}
                    aggregateLightTransitionerByCoordinate[aggregateRow] = transitionerRow
                end
                local transitioner = transitionerRow[aggregateCol]

                -- No light data, clear the aggregate value or update transitioner
                if not useTransitioners or transitioner == nil then
                    aggregateRowArray[aggregateCol] = nil
                else
                    if isTileAffectedByAmbientCallback(aggregateRow, aggregateCol) then
                        transitioner.resetIfChanged({
                            endR = ambientRed * ambientIntensity,
                            endG = ambientGreen * ambientIntensity,
                            endB = ambientBlue * ambientIntensity
                        })
                    else
                        transitioner.resetIfChanged({
                            endR = 0,
                            endG = 0,
                            endB = 0
                        })
                    end
                end
            else
                local newR
                local newG
                local newB
                if isTileAffectedByAmbientCallback(aggregateRow, aggregateCol) then
                    newR = min(ambientRed * ambientIntensity + aggregateR, 1)
                    newG = min(ambientGreen * ambientIntensity + aggregateG, 1)
                    newB = min(ambientBlue * ambientIntensity + aggregateB, 1)
                else
                    newR = aggregateR
                    newG = aggregateG
                    newB = aggregateB
                end

                if cell == nil or not useTransitioners then
                    aggregateRowArray[aggregateCol] = {
                        r = newR,
                        g = newG,
                        b = newB
                    }
                else
                    local transitionerRow = aggregateLightTransitionerByCoordinate[aggregateRow]
                    if transitionerRow == nil then
                        transitionerRow = {}
                        aggregateLightTransitionerByCoordinate[aggregateRow] = transitionerRow
                    end
                    local transitioner = transitionerRow[aggregateCol]
                    if transitioner == nil then
                        transitioner = AggregateLightTransitioner.new({
                            index = #activeTransitioners,
                            aggregateLightByCoordinate = aggregateLightByCoordinate,
                            transitionerTargetCoordinates = transitionerTargetCoordinates,
                            row = aggregateRow,
                            column = aggregateCol,
                            startR = cell.r,
                            startG = cell.g,
                            startB = cell.b,
                            endR = newR,
                            endG = newG,
                            endB = newB,
                            transitionTime = 250,
                            transitionerIndexesForRemoval = transitionerIndexesForRemoval
                        })
                        transitionerRow[aggregateCol] = transitioner
                        table.insert(activeTransitioners, transitioner)
                    else
                        transitioner.resetIfChanged({
                            endR = newR,
                            endG = newG,
                            endB = newB
                        })
                    end
                end
            end
            --endregion
        end
        --endregion
        --After processing tiles which need full aggregate computations, add the ones managed by the transitioners to the list.
        for i=1,#transitionerTargetCoordinates do
            local coordinate = transitionerTargetCoordinates[i]
            markDirtyAggregateTile(coordinate.row, coordinate.column)
        end
    end

    -- todo rename this to resetDirtyFlagsAndIndexes
    function self.resetDirtyFlags()
        dirtyLightIds = {}
        ambientLightChanged = false
        dirtyAggregateUniqueIndex = {}
        dirtyAggregateRows = {}
        dirtyAggregateColumns = {}
        dirtyAggregateIndex = 1
        for i=1,#transitionerTargetCoordinates do
            transitionerTargetCoordinates[i] = nil
        end
    end

    function self.addLight(params)
        requireParams({"row","column","r","g","b","intensity","radius"}, params)

        -- Fetch next light id and increment to the next value
        local lightId
        if params.lightId ~= nil then
            lightId = params.lightId
        else
            lightId = nextLightId
            nextLightId = nextLightId + 1
        end

        -- Add the light ID to the dirty list
        table.insert(dirtyLightIds, lightId)

        -- Add the light
        lightsById[lightId] = {
            row = params.row,
            column = params.column,
            r = params.r,
            g = params.g,
            b = params.b,
            intensity = params.intensity,
            radius = params.radius,
            affectedRows = {},
            affectedColumns = {},
            affectedIndex = 1
        }

        return lightId
    end

    -- todo expand interface to allow changing color, intensity, radius, or any attribute of the light
    function self.updateLight(params)
        requireParams({"lightId","newRow","newColumn"}, params)

        local newRow = params.newRow
        local newColumn = params.newColumn
        local light = lightsById[params.lightId]
        if newRow ~= light.row or newColumn ~= light.column then
            light.row = newRow
            light.column = newColumn
            markLightAsDirty(params.lightId)
        end
    end

    function self.removeLight(lightId)
        markAggregateTilesAffectedByLightAsDirty(lightId)
        lightsById[lightId] = nil
        affectedAreasByLightId[lightId] = nil
    end

    function self.getLightProperties(lightId)
        local props
        local light = lightsById[lightId]
        if light ~= nil then
            props = {}
            props.row = light.row
            props.column = light.column
            props.r = light.r
            props.g = light.g
            props.b = light.b
            props.intensity = light.intensity
            props.radius = light.radius
        end
        return props
    end

    function self.markLightAsDirtyIfAffectedAreaContainsTile(row, col)
        for lightId, light in pairs(lightsById) do
            local affectedArea = affectedAreasByLightId[lightId]
            local affectedRow = affectedArea[row]
            if affectedRow ~= nil then
                local affectedColumn = affectedRow[col]
                if affectedColumn ~= nil then
                    markLightAsDirty(lightId)
                end
            end
        end
    end

    local function checkTransparent(row, col)
        local transparent = true
        local transparencyStateRow = transparencyStateByRow[row]
        if transparencyStateRow ~= nil then
            local isTransparent = transparencyStateRow[col]
            if isTransparent == false then
                transparent = false
            elseif isTransparent == nil then
                transparent = isTransparentCallback(col, row)
            end
        else
            transparent = isTransparentCallback(col, row)
        end
        return transparent
    end

    function self.getAggregateLightIfRowColumnOpaque(row, col, viewRow, viewCol)
        local light
        if not checkTransparent(row, col) then
            local totalR = 0
            local totalG = 0
            local totalB = 0
            local total = 0
            if viewRow >= row then
                if viewCol >= col then -- bottom right
                    if checkTransparent(row, col + 1) then
                        local l1 = self.getAggregateLight(row, col + 1)
                        if l1 ~= nil then
                            totalR = totalR + l1.r
                            totalG = totalG + l1.g
                            totalB = totalB + l1.b
                            total = total + 1
                        end
                    end

                    if checkTransparent(row + 1, col + 1) then
                        local l2 = self.getAggregateLight(row + 1, col + 1)
                        if l2 ~= nil then
                            totalR = totalR + l2.r
                            totalG = totalG + l2.g
                            totalB = totalB + l2.b
                            total = total + 1
                        end
                    end

                    if checkTransparent(row + 1, col) then
                        local l3 = self.getAggregateLight(row + 1, col)
                        if l3 ~= nil then
                            totalR = totalR + l3.r
                            totalG = totalG + l3.g
                            totalB = totalB + l3.b
                            total = total + 1
                        end
                    end

                else -- bottom left

                    if checkTransparent(row, col - 1) then
                        local l1 = self.getAggregateLight(row, col - 1)
                        if l1 ~= nil then
                            totalR = totalR + l1.r
                            totalG = totalG + l1.g
                            totalB = totalB + l1.b
                            total = total + 1
                        end
                    end

                    if checkTransparent(row + 1, col - 1) then
                        local l2 = self.getAggregateLight(row + 1, col - 1)
                        if l2 ~= nil then
                            totalR = totalR + l2.r
                            totalG = totalG + l2.g
                            totalB = totalB + l2.b
                            total = total + 1
                        end
                    end

                    if checkTransparent(row + 1, col) then
                        local l3 = self.getAggregateLight(row + 1, col)
                        if l3 ~= nil then
                            totalR = totalR + l3.r
                            totalG = totalG + l3.g
                            totalB = totalB + l3.b
                            total = total + 1
                        end
                    end

                end
            else
                if viewCol >= col then -- top right

                    if checkTransparent(row - 1, col) then
                        local l1 = self.getAggregateLight(row - 1, col)
                        if l1 ~= nil then
                            totalR = totalR + l1.r
                            totalG = totalG + l1.g
                            totalB = totalB + l1.b
                            total = total + 1
                        end
                    end

                    if checkTransparent(row - 1, col + 1) then
                        local l2 = self.getAggregateLight(row - 1, col  + 1)
                        if l2 ~= nil then
                            totalR = totalR + l2.r
                            totalG = totalG + l2.g
                            totalB = totalB + l2.b
                            total = total + 1
                        end
                    end

                    if checkTransparent(row, col + 1) then
                        local l3 = self.getAggregateLight(row, col + 1)
                        if l3 ~= nil then
                            totalR = totalR + l3.r
                            totalG = totalG + l3.g
                            totalB = totalB + l3.b
                            total = total + 1
                        end
                    end

                else -- top left

                    if checkTransparent(row - 1, col) then
                        local l1 = self.getAggregateLight(row - 1, col)
                        if l1 ~= nil then
                            totalR = totalR + l1.r
                            totalG = totalG + l1.g
                            totalB = totalB + l1.b
                            total = total + 1
                        end
                    end

                    if checkTransparent(row - 1, col - 1) then
                        local l2 = self.getAggregateLight(row - 1, col - 1)
                        if l2 ~= nil then
                            totalR = totalR + l2.r
                            totalG = totalG + l2.g
                            totalB = totalB + l2.b
                            total = total + 1
                        end
                    end

                    if checkTransparent(row, col - 1) then
                        local l3 = self.getAggregateLight(row, col - 1)
                        if l3 ~= nil then
                            totalR = totalR + l3.r
                            totalG = totalG + l3.g
                            totalB = totalB + l3.b
                            total = total + 1
                        end
                    end

                end
            end

            light = {
                r = totalR / total,
                g = totalG / total,
                b = totalB / total
            }
        end

        return light
    end

    function self.getAggregateLight(row, col)
        local light
        local rowArray = aggregateLightByCoordinate[row]
        if rowArray ~= nil then
            light = rowArray[col]
        end
        -- Return a default ambient light if no aggregate data is found
        if light == nil and isTileAffectedByAmbientCallback(row, col) then
            light = {
                r=ambientRed * ambientIntensity,
                g=ambientGreen * ambientIntensity,
                b=ambientBlue * ambientIntensity
            }
        elseif light == nil then
            light = {
                r=0,
                g=0,
                b=0
            }
        end
        return light
    end

    function self.getDirtyAggregateRows()
        return dirtyAggregateRows
    end

    function self.getDirtyAggregateColumns()
        return dirtyAggregateColumns
    end

    function self.getDirtyAggregateCount()
        return dirtyAggregateIndex - 1
    end

    function self.hasDirtyAggregateTile()
        return dirtyAggregateIndex > 1
    end

    function self.hasAmbientLightChanged()
        return ambientLightChanged
    end

    function self.setIsTransparentCallback(callback)
        isTransparentCallback = callback
        lineOfSight.setIsTransparentCallback(callback)
    end

    function self.setIsTileAffectedByAmbientCallback(callback)
        isTileAffectedByAmbientCallback = callback
    end

    local parentSave = self.save
    function self.save(diskStream)
        parentSave(diskStream)

        diskStream.write(useTransitioners)
        diskStream.write(compensateLightingForViewingPosition)

        diskStream.write(nextLightId)

        diskStream.write(ambientRed)
        diskStream.write(ambientGreen)
        diskStream.write(ambientBlue)
        diskStream.write(ambientIntensity)

        local lightCount = 0
        for k,v in pairs(lightsById) do
            lightCount = lightCount + 1
        end
        diskStream.write(lightCount)

        for lightId,light in pairs(lightsById) do
            diskStream.write(lightId)
            diskStream.write(light.row)
            diskStream.write(light.column)
            diskStream.write(light.r)
            diskStream.write(light.g)
            diskStream.write(light.b)
            diskStream.write(light.intensity)
            diskStream.write(light.radius)
        end
    end

    local parentLoad = self.load
    function self.load(diskStream)
        parentLoad(diskStream)

        useTransitioners = diskStream.read()
        compensateLightingForViewingPosition = diskStream.read()

        nextLightId = diskStream.read()

        ambientRed = diskStream.read()
        ambientGreen = diskStream.read()
        ambientBlue = diskStream.read()
        ambientIntensity = diskStream.read()

        local lightCount = diskStream.read()
        for i=1,lightCount do
            local lightId = diskStream.read()
            local row = diskStream.read()
            local column = diskStream.read()
            local r = diskStream.read()
            local g = diskStream.read()
            local b = diskStream.read()
            local intensity = diskStream.read()
            local radius = diskStream.read()

            self.addLight({
                lightId = lightId,
                row = row,
                column = column,
                r = r,
                g = g,
                b = b,
                intensity = intensity,
                radius = radius
            })
        end
    end

    local function initialize()
        lineOfSight = Los.new({
            maxRadius = 20,
            isTransparent = isTransparentCallback,
            fovCallback = fovCallback
        })

        nextLightId = 0

        ambientRed = 1
        ambientGreen = 1
        ambientBlue = 1
        ambientIntensity = 0.3

        ambientLightChanged = false
        dirtyAggregateUniqueIndex = {}
        dirtyAggregateRows = {}
        dirtyAggregateColumns = {}
        dirtyAggregateIndex = 1

        aggregateLightByCoordinate = {}
        transparencyStateByRow = {}
        dirtyLightIds = {}
        lightsById = {}
        affectedAreasByLightId = {}

        aggregateLightTransitionerByCoordinate = {}
        activeTransitioners = {}
        transitionerIndexesForRemoval = {}
        transitionerTargetCoordinates = {}
    end

    initialize()

    return self
end
ObjectSystem.Factory.registerForType(LightingModel.objectType, LightingModel.new)

return LightingModel