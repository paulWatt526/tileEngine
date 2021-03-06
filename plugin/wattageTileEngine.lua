-- Create library
local lib = {}
-------------------------------------------------------------------------------
-- BEGIN (Insert your implementation starting here)
-------------------------------------------------------------------------------

local TileEngineModule = require "plugin.wattageTileEngine.tileEngine"
local Utils = require "plugin.wattageTileEngine.utils"

lib.Camera = TileEngineModule.Camera
lib.Engine = TileEngineModule.Engine
lib.EntityLayer = TileEngineModule.EntityLayer
lib.LayerConstants = TileEngineModule.LayerConstants
lib.LightingModel = require "plugin.wattageTileEngine.lightingModel"
lib.LineOfSightModel = require "plugin.wattageTileEngine.lineOfSightModel"
lib.Module = TileEngineModule.Module
lib.ObjectSystem = require "plugin.wattageTileEngine.objectSystem"
lib.RegionManager = require "plugin.wattageTileEngine.regionManager"
lib.SpriteInfo = TileEngineModule.SpriteInfo
lib.Tile = TileEngineModule.Tile
lib.TileLayer = TileEngineModule.Layer
--lib.TileSelectionLayer = TileEngineModule.TileSelectionLayer
lib.Utils = {}
lib.Utils.addToGrid = Utils.addToGrid
lib.Utils.getFromGrid = Utils.getFromGrid
lib.Utils.loadJsonFile = Utils.loadJsonFile
lib.Utils.removeFromGrid = Utils.removeFromGrid
lib.Utils.removeItem = Utils.removeItem
lib.Utils.requireParams = Utils.requireParams
lib.ViewControl = require "plugin.wattageTileEngine.tileEngineViewControl"

-------------------------------------------------------------------------------
-- END
-------------------------------------------------------------------------------

-- Return library instance
return lib
