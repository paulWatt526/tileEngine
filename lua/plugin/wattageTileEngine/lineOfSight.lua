local Utils = require "plugin.wattageTileEngine.utils"

local sqrt = math.sqrt

local LineOfSight = {}

LineOfSight.new = function(params)
    Utils.requireParams({
        "isTransparent",
        "fovCallback"
    }, params)
    local self = {}

    local isTransparent = params.isTransparent
    local fovCallback = params.fovCallback
    local _startX
    local _startY
    local _radius
    local _radiusSquared

    local function castLight(row, startP, endP, xx, xy, yx, yy)
        local newStart = 0

        if startP < endP then
            return
        end

        local blocked = false
        for distance=row,_radius do
            if blocked then
                return
            end

            local deltaY = -distance
            for deltaX=-distance,0,1 do
                local currentX = _startX + deltaX * xx + deltaY * xy
                local currentY = _startY + deltaX * yx + deltaY * yy
                local leftSlope = (deltaX - 0.5) / (deltaY + 0.5)
                local rightSlope = (deltaX + 0.5) / (deltaY - 0.5)

                local processThisLoop = true
                if startP < rightSlope then
                    processThisLoop = false
                elseif endP > leftSlope then
                    break
                end

                if processThisLoop then
                    local distanceSquared = deltaX * deltaX + deltaY * deltaY
                    if distanceSquared <= _radiusSquared then
                        fovCallback(currentX, currentY, sqrt(distanceSquared), isTransparent(currentX, currentY))
                    end

                    if blocked then
                        if not isTransparent(currentX, currentY) then
                            newStart = rightSlope
                        else
                            blocked = false
                            startP = newStart
                        end
                    else
                        if not isTransparent(currentX, currentY) and distance < _radius then
                            blocked = true
                            castLight(distance + 1, startP, leftSlope, xx, xy, yx, yy)
                            newStart = rightSlope
                        end
                    end
                end
            end
        end
    end

    function self.calculateFov(params)
        Utils.requireParams({
            "startX",
            "startY",
            "radius"
        }, params)

        _startX = params.startX
        _startY = params.startY
        _radius = params.radius
        _radiusSquared = _radius * _radius

        fovCallback(params.startX, params.startY, 0, isTransparent(params.startX, params.startY))

        castLight(1, 1.0, 0.0, 0, -1, 1, 0)
        castLight(1, 1.0, 0.0, -1, 0, 0, 1)

        castLight(1, 1.0, 0.0, 0, -1, -1, 0)
        castLight(1, 1.0, 0.0, -1, 0, 0, -1)

        castLight(1, 1.0, 0.0, 0, 1, 1, 0)
        castLight(1, 1.0, 0.0, 1, 0, 0, 1)

        castLight(1, 1.0, 0.0, 0, 1, -1, 0)
        castLight(1, 1.0, 0.0, 1, 0, 0, -1)
    end

    function self.setIsTransparentCallback(callback)
        isTransparent = callback
    end

    return self
end

return LineOfSight