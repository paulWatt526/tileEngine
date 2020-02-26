local Los = require "plugin.wattageTileEngine.lineOfSight"
local Utils = require "plugin.wattageTileEngine.utils"

local LineOfSightTransitioner = {}
LineOfSightTransitioner.new = function(params)
        Utils.requireParams({
            "index",
            "transitionerValueByCoordinate",
            "transitionerTargetCoordinates",
            "row",
            "column",
            "startValue",
            "endValue",
            "transitionTime",
            "transitionerIndexesForRemoval"}, params)

    local self = {}

    self.index = params.index
    local transitionerValueByCoordinate = params.transitionerValueByCoordinate
    local transitionerTargetCoordinates = params.transitionerTargetCoordinates
    self.row = params.row
    self.column = params.column
    local startValue = params.startValue
    local endValue = params.endValue
    local transitionTime = params.transitionTime
    self.transitionerIndexesForRemoval = params.transitionerIndexesForRemoval
    local elapsedTime = 0

    local diffValue = endValue - startValue
    local curValue = startValue

    function self.resetIfChanged(params)
        if endValue ~= params.endValue then
            startValue = curValue
            endValue = params.endValue
            diffValue = endValue - startValue
            elapsedTime = 0
        end
    end

    function self.getEndValue()
        return {value = endValue}
    end

    function self.update(deltaTime)
        elapsedTime = elapsedTime + deltaTime

        curValue = startValue + (elapsedTime / transitionTime) * diffValue

        if elapsedTime >= transitionTime then
            curValue = endValue
            startValue = endValue
            table.insert(self.transitionerIndexesForRemoval, self.index)
            table.insert(transitionerTargetCoordinates, {row = self.row, column = self.column})
        else
            table.insert(transitionerTargetCoordinates, {row = self.row, column = self.column})
        end

        local columns = transitionerValueByCoordinate[self.row]
        if columns == nil then
            columns = {}
            transitionerValueByCoordinate[self.row] = columns
        end

        local cell = columns[self.column]
        if cell == nil then
            cell = {}
            columns[self.column] = cell
        end

        cell.value = curValue
    end

    local function init()
        local columns = transitionerValueByCoordinate[self.row]
        if columns == nil then
            columns = {}
            transitionerValueByCoordinate[self.row] = columns
        end

        local cell = columns[self.column]
        if cell == nil then
            cell = {}
            columns[self.column] = cell
        end

        cell.value = curValue
    end

    init()

    return self
end

local LineOfSightModel = {}

LineOfSightModel.ALL_VISIBLE = {
    update = function(centerRow, centerCol, deltaTime)
        -- does nothing
    end,
    makeDirty = function()
        -- does nothing
    end,
    hasDirtyTiles = function()
        -- does nothing
        return false
    end,
    resetDirtyFlags = function()
        -- does nothing
    end,
    isInLineOfSight = function(rowParam, columnParam)
        return true
    end,
    getLineOfSightTransitionValue = function(rowParam, columnParam)
        return 1
    end,
    resetChangeTracking = function()
        -- does nothing
    end,
    getDirtyRows = function()
        return {}
    end,
    getDirtyColumns = function()
        return {}
    end,
    getDirtyCount = function()
        return {}
    end,
    getRowsTransitionedIn = function()
        return {}
    end,
    getColsTransitionedIn = function()
        return {}
    end,
    getRowsTransitionedOut = function()
        return {}
    end,
    getColsTransitionedOut = function()
        return {}
    end,
    getCoordinatesIn = function()
        return {}
    end
}

LineOfSightModel.new = function(params)
    Utils.requireParams({
        "radius",
        "isTransparent"
    }, params)

    local self = {}

    self.useTransitioners = true

    local losInstance
    local curCenterRow
    local curCenterColumn
    local coordinatesIn
    local nextCoordinatesIn

    local columnsTransitionedInByRow
    local rowsTransitionedIn
    local colsTransitionedIn

    local columnsTransitionedOutByRow
    local rowsTransitionedOut
    local colsTransitionedOut

    local transitionerValueByCoordinate        -- This stores the transitioners
    local activeTransitioners                  -- Stores the active transitioners
    local transitionerIndexesForRemoval        -- Stores the indexes of the transitioners that can be removed from the active transitioner list.
    local transitionerTargetCoordinates        -- Stores tile coordinates of the tiles affected by the transitioners.  This is necessary to notify tiles to update their tint.
    local transitionTime                       -- Stores the time in milliseconds for transitions to occur.

    local dirtyRows
    local dirtyColumns
    local dirtyIndex
    local isDirty

    local function fovCallback(x, y, distance)
        -- Add to new collection of coordinates in
        local newCoordsRow = nextCoordinatesIn[y]
        if newCoordsRow == nil then
            newCoordsRow = {}
            nextCoordinatesIn[y] = newCoordsRow
        end
        newCoordsRow[x] = {}


        -- Determine deltas for in transitions
        local row = coordinatesIn[y]
        if row == nil then
            -- Currently not in, so add to list of transitioned in

            -- Add to list indexed by row
            local inRow = columnsTransitionedInByRow[y]
            if inRow == nil then
                inRow = {}
                columnsTransitionedInByRow[y] = inRow
            end
            inRow[x] = true

            -- Add to unindexed list
            table.insert(rowsTransitionedIn, y)
            table.insert(colsTransitionedIn, x)
        else
            local columnValue = row[x]
            if columnValue == nil then
                -- Currently not in, so add to list of transitioned in

                -- Add to list indexed by row
                local inRow = columnsTransitionedInByRow[y]
                if inRow == nil then
                    inRow = {}
                    columnsTransitionedInByRow[y] = inRow
                end
                inRow[x] = true

                -- Add to unindexed list
                table.insert(rowsTransitionedIn, y)
                table.insert(colsTransitionedIn, x)
            else
                -- Is in, so mark it so that it won't go to the out transitions
                columnValue.willRemain = true
            end
        end
    end

    local function assembleOutTransitions()
        for row,columns in pairs(coordinatesIn) do
            for column, value in pairs(columns) do
                if not value.willRemain then
                    -- Add to list indexed by row
                    local outRow = columnsTransitionedOutByRow[row]
                    if outRow == nil then
                        outRow = {}
                        columnsTransitionedOutByRow[row] = outRow
                    end
                    outRow[column] = true

                    -- Add to unindexed list
                    table.insert(rowsTransitionedOut, row)
                    table.insert(colsTransitionedOut, column)
                end
            end
        end
    end

    local function applyDeltas()
        coordinatesIn = nextCoordinatesIn
        nextCoordinatesIn = {}
    end

    function self.setTransitionTime(time)
        transitionTime = time
    end

    function self.update(centerRow, centerCol, deltaTime)
        if curCenterRow == nil and curCenterColumn == nil then
            curCenterRow = centerRow
            curCenterColumn = centerCol
            isDirty = true
        elseif curCenterRow ~= centerRow or curCenterColumn ~= centerCol then
            curCenterRow = centerRow
            curCenterColumn = centerCol
            isDirty = true
        end

        -- update transitioners
        for i=1,#activeTransitioners do
            activeTransitioners[i].update(deltaTime)
        end
        -- sort indexes in descending order
        table.sort(transitionerIndexesForRemoval, function(a, b) return a > b end)
        -- remove indexes
        for i=1,#transitionerIndexesForRemoval do
            local indexToRemove = transitionerIndexesForRemoval[i]
            local transitionerForRemoval = activeTransitioners[indexToRemove]
            if transitionerForRemoval ~= nil then
                transitionerValueByCoordinate[transitionerForRemoval.row][transitionerForRemoval.column] = nil
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

        if isDirty then
            self.resetChangeTracking()

            losInstance.calculateFov({
                startX = centerCol,
                startY = centerRow,
                radius = params.radius
            })

            assembleOutTransitions()
            applyDeltas()
        end

        if isDirty and self.useTransitioners then
            -- Transitioners for transitions in
            local transitionInCount = #rowsTransitionedIn
            for index=1,transitionInCount do
                local row = rowsTransitionedIn[index]
                local col = colsTransitionedIn[index]

                local transitionerRow = transitionerValueByCoordinate[row]
                if transitionerRow == nil then
                    transitionerRow = {}
                    transitionerValueByCoordinate[row] = transitionerRow
                end
                local transitioner = transitionerRow[col]
                if transitioner == nil then
                    transitioner = LineOfSightTransitioner.new({
                        index = #activeTransitioners,
                        transitionerValueByCoordinate = transitionerValueByCoordinate,
                        transitionerTargetCoordinates = transitionerTargetCoordinates,
                        row = row,
                        column = col,
                        startValue = 0,
                        endValue = 1,
                        transitionTime = transitionTime,
                        transitionerIndexesForRemoval = transitionerIndexesForRemoval
                    })
                    transitionerRow[col] = transitioner
                    table.insert(activeTransitioners, transitioner)
                else
                    transitioner.resetIfChanged({endValue = 1})
                end
            end

            -- Transitioners for transitions out
            local transitionOutCount = #rowsTransitionedOut
            for index=1, transitionOutCount do
                local row = rowsTransitionedOut[index]
                local col = colsTransitionedOut[index]

                local transitionerRow = transitionerValueByCoordinate[row]
                if transitionerRow == nil then
                    transitionerRow = {}
                    transitionerValueByCoordinate[row] = transitionerRow
                end
                local transitioner = transitionerRow[col]
                if transitioner == nil then
                    transitioner = LineOfSightTransitioner.new({
                        index = #activeTransitioners,
                        transitionerValueByCoordinate = transitionerValueByCoordinate,
                        transitionerTargetCoordinates = transitionerTargetCoordinates,
                        row = row,
                        column = col,
                        startValue = 1,
                        endValue = 0,
                        transitionTime = transitionTime,
                        transitionerIndexesForRemoval = transitionerIndexesForRemoval
                    })
                    transitionerRow[col] = transitioner
                    table.insert(activeTransitioners, transitioner)
                else
                    transitioner.resetIfChanged({endValue = 0})
                end
            end
        end

        for i=1,#transitionerTargetCoordinates do
            local coordinate = transitionerTargetCoordinates[i]
            dirtyRows[dirtyIndex] = coordinate.row
            dirtyColumns[dirtyIndex] = coordinate.column
            dirtyIndex = dirtyIndex + 1
            isDirty = true
        end
    end

    function self.makeDirty()
        isDirty = true
    end

    function self.hasDirtyTiles()
        return isDirty
    end

    function self.resetDirtyFlags()
        dirtyIndex = 1
        dirtyRows = {}
        dirtyColumns = {}
        for i=1,#transitionerTargetCoordinates do
            transitionerTargetCoordinates[i] = nil
        end
        isDirty = false
    end

    function self.isInLineOfSight(rowParam, columnParam)
        local row = coordinatesIn[rowParam]
        if row ~= nil then
            local column = row[columnParam]
            if column ~= nil then
                return true
            end
        end
        return false
    end

    function self.getLineOfSightTransitionValue(rowParam, columnParam)
        -- check active transitioners first
        if self.useTransitioners then
            local transitionerRow = transitionerValueByCoordinate[rowParam]
            if transitionerRow ~= nil then
                local transitioner = transitionerRow[columnParam]
                if transitioner ~= nil then
                    return transitioner.value
                end
            end
        end

        if self.isInLineOfSight(rowParam, columnParam) then
            return 1
        else
            return 0
        end
    end

    function self.resetChangeTracking()
        columnsTransitionedInByRow = {}
        rowsTransitionedIn = {}
        colsTransitionedIn = {}

        columnsTransitionedOutByRow = {}
        rowsTransitionedOut = {}
        colsTransitionedOut = {}
    end

    function self.getDirtyRows()
        return dirtyRows
    end

    function self.getDirtyColumns()
        return dirtyColumns
    end

    function self.getDirtyCount()
        return dirtyIndex - 1
    end

    function self.getRowsTransitionedIn()
        return rowsTransitionedIn
    end

    function self.getColsTransitionedIn()
        return colsTransitionedIn
    end

    function self.getRowsTransitionedOut()
        return rowsTransitionedOut
    end

    function self.getColsTransitionedOut()
        return colsTransitionedOut
    end

    function self.getCoordinatesIn()
        return coordinatesIn
    end

    local function init()
        coordinatesIn = {}
        nextCoordinatesIn = {}

        columnsTransitionedInByRow = {}
        rowsTransitionedIn = {}
        colsTransitionedIn = {}

        columnsTransitionedOutByRow = {}
        rowsTransitionedOut = {}
        colsTransitionedOut = {}

        transitionerValueByCoordinate = {}
        activeTransitioners = {}
        transitionerIndexesForRemoval = {}
        transitionerTargetCoordinates = {}
        transitionTime = 375

        dirtyRows = {}
        dirtyColumns = {}
        dirtyIndex = 1
        isDirty = false

        losInstance = Los.new({
            maxRadius = params.radius + 2,
            isTransparent = params.isTransparent,
            fovCallback = fovCallback
        })
    end

    init()

    return self
end

return LineOfSightModel