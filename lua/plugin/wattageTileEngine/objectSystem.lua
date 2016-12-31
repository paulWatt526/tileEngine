local Utils = require "plugin.wattageTileEngine.utils"
local TableDao = require "plugin.wattageTileEngine.tableDao"

local curObjectId = 0
local function nextObjectId()
    curObjectId = curObjectId + 1
    return curObjectId
end

local ObjectSystem = {}

ObjectSystem.Factory = {}
ObjectSystem.Factory.factories = {}
ObjectSystem.Factory.registerForType = function(typeName, factoryMethod)
    ObjectSystem.Factory.factories[typeName] = factoryMethod
end
ObjectSystem.Factory.getForType = function(typeName)
    return ObjectSystem.Factory.factories[typeName]
end

ObjectSystem.new = function(params)
    Utils.requireParams({
        "objectType"
    }, params)

    local self = {}

    local objectId = nextObjectId()
    local objectType = params.objectType

    function self.getObjectId()
        return objectId
    end

    function self.getObjectType()
        return objectType
    end

    function self.registerObject(diskStream)
        if not diskStream.isInMap(self) then
            diskStream.insertInOrder(self)
            return true
        end
        return false
    end

    function self.save(diskStream)
        diskStream.write(objectType)
        diskStream.write(objectId)
    end

    function self.load(diskStream)
        local oldObjectId = diskStream.read()
        diskStream.registerNewObjectWithOldId(oldObjectId, self)
    end

    function self.link()
        -- Base implementation does nothing
    end

    return self
end

ObjectSystem.DiskStream = {}
ObjectSystem.DiskStream.new = function()
    local self = {}

    local orderedObjectIds = {}
    local map = {}
    local data = {}
    local oldIdsInInsertionOrder = {}
    local oldIdToNewObjectMap = {}
    local links = {}
    local curLinkIndex = 0
    local curIndex = 0

    local function reset()
        orderedObjectIds = {}
        map = {}
        data = {}
        oldIdsInInsertionOrder = {}
        oldIdToNewObjectMap = {}
        links = {}
        curIndex = 0
    end

    function self.saveToFile(o, fileName)
        o.registerObject(self)
        for i=1,#orderedObjectIds do
            map[orderedObjectIds[i]].save(self)
        end
        TableDao.saveTable(data, fileName)
        reset()
    end


    function self.loadFromFile(fileName)
        Utils.toggleRequireParams(false)

        data = TableDao.loadTable(fileName)
        -- Load all of the objects
        local rootObject
        local curType = self.read()
        while curType ~= nil do
            local factoryMethod = ObjectSystem.Factory.getForType(curType)
            local newObject = factoryMethod({})
            newObject.load(self)
            if rootObject == nil then
                rootObject = newObject
            end
            curType = self.read()
        end

        -- Perform linking
        for i=1,#oldIdsInInsertionOrder do
            oldIdToNewObjectMap[oldIdsInInsertionOrder[i]].link(self)
        end

        Utils.toggleRequireParams(true)

        return rootObject
    end

    function self.isInMap(o)
        return map[o.getObjectId()] ~= nil
    end

    function self.insertInOrder(o)
        local objectId = o.getObjectId()
        table.insert(orderedObjectIds, objectId)
        map[objectId] = o
    end

    function self.write(value)
        table.insert(data, value)
    end

    function self.read()
        curIndex = curIndex + 1
        return data[curIndex]
    end

    function self.registerNewObjectWithOldId(oldObjectId, o)
        table.insert(oldIdsInInsertionOrder, oldObjectId)
        oldIdToNewObjectMap[oldObjectId] = o
    end

    function self.getNewObjectForOldId(oldObjectId)
        return oldIdToNewObjectMap[oldObjectId]
    end

    function self.registerLink(oldObjectId)
        local oldObjectIdValue = {}
        if oldObjectId ~= nil then
            oldObjectIdValue.value = oldObjectId
        end
        table.insert(links, oldObjectIdValue)
    end

    function self.getNextLink()
        curLinkIndex = curLinkIndex + 1
        return links[curLinkIndex].value
    end

    return self
end

return ObjectSystem