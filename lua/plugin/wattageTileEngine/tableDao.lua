local json = require "json"

local TableDao = {}

local function getPath(fileName)
    return system.pathForFile(fileName, system.DocumentsDirectory)
end

TableDao.saveTable = function(table, fileName)
    local file = io.open(getPath(fileName), "w")
    if file then
        local contents = json.encode(table)
        file:write(contents)
        io.close(file)
        if (system.getInfo("platformName") == "iPhone OS") then
            native.setSync( fileName, { iCloudBackup = false } )
        end
    end
end

TableDao.loadTable = function(fileName)
    local table = {}
    local file = io.open(getPath(fileName), "r")
    if file then
        local contents = file:read("*a")
        table = json.decode(contents)
        io.close(file)
        if (system.getInfo("platformName") == "iPhone OS") then
            native.setSync( fileName, { iCloudBackup = false } )
        end
    end
    return table
end

return TableDao