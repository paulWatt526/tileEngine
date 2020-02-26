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
        {
            -- tiles_3
            x=103,
            y=1,
            width=32,
            height=32,

        },
    },
    
    sheetContentWidth = 136,
    sheetContentHeight = 34
}

SheetInfo.frameIndex =
{

    ["tiles_0"] = 1,
    ["tiles_1"] = 2,
    ["tiles_2"] = 3,
    ["tiles_3"] = 4,
}

function SheetInfo:getSheet()
    return self.sheet;
end

function SheetInfo:getFrameIndex(name)
    return self.frameIndex[name];
end

return SheetInfo
