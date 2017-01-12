-- 
-- Abstract: wattageTileEngine Library Plugin Test Project
-- 
-- Sample code is MIT licensed, see http://www.coronalabs.com/links/code/license
-- Copyright (C) 2015 Corona Labs Inc. All Rights Reserved.
--
------------------------------------------------------------
local composer = require( "composer" )

--profiler = require "Profiler"
--profiler.startProfiler({time = 10000, delay = 1000})

-------------------------------------------------------------------------------
-- BEGIN (Insert your sample test starting here)
-------------------------------------------------------------------------------
display.setStatusBar(display.HiddenStatusBar)
display.setDefault( "background", 0, 0, 0)

composer.gotoScene( "noLosScene" )
-------------------------------------------------------------------------------
-- END
-------------------------------------------------------------------------------
