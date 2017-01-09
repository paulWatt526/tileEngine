--
-- created with TexturePacker (http://www.codeandweb.com/texturepacker)
--
-- $TexturePacker:SmartUpdate:555151070cb168cc4515f97c9e704cc8:353141410d475a66d0ab1e5d995ca57e:f4492607ea55a754477543692c89a688$
--
-- local sheetInfo = require("mysheet")
-- local myImageSheet = graphics.newImageSheet( "mysheet.png", sheetInfo:getSheet() )
-- local sprite = display.newSprite( myImageSheet , {frames={sheetInfo:getFrameIndex("sprite")}} )
--

local SheetInfo = {}

SheetInfo.sheet =
{
    frames = {
    
        {
            -- tiles_0
            x=1,
            y=1,
            width=32,
            height=32,

        },
        {
            -- tiles_1
            x=35,
            y=1,
            width=32,
            height=32,

        },
        {
            -- tiles_2
            x=69,
            y=1,
            width=32,
            height=32,

        },
    },
    
    sheetContentWidth = 102,
    sheetContentHeight = 34
}

SheetInfo.frameIndex =
{

    ["tiles_0"] = 1,
    ["tiles_1"] = 2,
    ["tiles_2"] = 3,
}

function SheetInfo:getSheet()
    return self.sheet;
end

function SheetInfo:getFrameIndex(name)
    return self.frameIndex[name];
end

return SheetInfo
