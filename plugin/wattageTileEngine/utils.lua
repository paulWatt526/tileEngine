local JSON = require "json"

local Utils = {}

local require = true
Utils.toggleRequireParams = function(v)
    require = v
end

Utils.requireParams = function(paramNames, params)
    if not require then
        return
    end

    for i=1,#paramNames do
        local paramName = paramNames[i]
        if params[paramName] == nil then
            error(paramName .. " is required.")
        end
    end
end

Utils.indexOf = function(table, element)
    for i=1,#table do
        if table[i] == element then
            return i
        end
    end
    return nil
end

Utils.removeItem = function(table, element)
    local index = Utils.indexOf(table, element)
    if index ~= nil then
        return table.remove(table, index)
    end
    return nil
end

Utils.addToGrid = function(value, grid, row, column)
    local columnArray = grid[row]
    if columnArray == nil then
        columnArray = {}
        grid[row] = columnArray
    end
    columnArray[column] = value
end

Utils.getFromGrid = function(grid, row, column)
    local columns = grid[row]
    if columns ~= nil then
        return columns[column]
    end
    return nil
end

Utils.removeFromGrid = function(grid, row, column)
    local columnArray = grid[row]
    if columnArray ~= nil then
        columnArray[column] = nil
    end
end

Utils.loadJsonFile = function( filename )
    -- set default base dir if none specified
    local base = system.ResourceDirectory

    -- create a file path for corona i/o
    local path = system.pathForFile( filename, base )

    -- will hold contents of file
    local contents

    -- io.open opens a file at path. returns nil if no file found
    local file = io.open( path, "r" )
    if file then
        -- read all contents of file into a string
        contents = file:read( "*a" )
        io.close( file )    -- close the file after using it
        --return decoded json string
        return JSON.decode( contents )
    else
        --or return nil if file didn't ex
        return nil
    end
end

return Utils