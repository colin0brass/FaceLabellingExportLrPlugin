--[[----------------------------------------------------------------------------
ImageMagickAPI.lua
ImageMagick functions for Lightroom thumbnail export
--------------------------------------------------------------------------------
Colin Osborne
August 2020
------------------------------------------------------------------------------]]

--============================================================================--
-- Lightroom imports
local LrDate 			= import 'LrDate'
local LrPathUtils 		= import 'LrPathUtils'
local LrFileUtils 		= import 'LrFileUtils'
--local LrPrefs	 		= import 'LrPrefs'
local LrTasks 			= import 'LrTasks'

--============================================================================--
-- Local imports
require "Utils.lua"

--============================================================================--
-- Local variables
local ImageMagickAPI = {}

local tmpdir = LrPathUtils.getStandardFilePath("temp")

-------------------------------------------------------------------------------
-- ImageMagick session handling

function ImageMagickAPI.init(prefs)
    local handle = {} -- handle
    handle.app = prefs.imageMagicApp
    if not LrFileUtils.exists(handle.app) then
        logger.writeLog(0, "ImageMagic: Cannot find ImageMagic app: " .. handle.app .. " not found")
        return false
    end
        
    -- create unique command file
    dateStr = tostring(LrDate.currentTime())
    handle.commandFile = LrPathUtils.child(tmpdir, "ImageMagicCmds-" .. dateStr .. ".txt")
    --logger.writeLog(4, "ImageMagick command file:" ... handle.commandFile)
    logger.writeLog(3, "ImageMagick command file:" .. handle.commandFile)
    local cmdFile = io.open(handle.commandFile, "w")
    io.close(cmdFile)
    
    return handle
end

function ImageMagickAPI.cleanup(handle)
    success = true
    if handle then
        logger.writeLog(4, "ImageMagic: cleaning-up after use")
        if LrFileUtils.exists(handle.commandFile) then
            LrFileUtils.delete(handle.commandFile)
        end
    end
    
    -- should this set handle to nil?
    
    return success
end

----------------------------------------------------------------------------------
-- ImageMagick command handling

function ImageMagickAPI.add_command_string(handle, command_string)
    success = true
    if not handle then
        success = false
    else
        logger.writeLog(4, "ImageMagick add command string: " .. command_string)
        local cmdFile = io.open(handle.commandFile, "a")
        if not cmdFile then
            success = false
        else
            cmdFile:write(command_string .. "\n")
            io.close(cmdFile)
        end
    end
    return success
end

function ImageMagickAPI.execute_commands(handle)
    success = true
    if not handle then
        success = false
    else
        exe = handle.app
        if not LrFileUtils.exists(exe) then
            logger.writeLog(0, "Could not find ImageMagick app:" .. exe)
        --else
        --    logger.writeLog(3, "Found ImageMagick app:" .. exe)
        end
        if not LrFileUtils.exists(handle.commandFile) then
            logger.writeLog(0, "Could not find ImageMagick command file:" .. handle.commandFile)
        --else
        --    logger.writeLog(3, "Found ImageMagick command file:" .. handle.commandFile)
        end
        
        command_line = exe .. " -script " .. path_quote_selection_for_platform(handle.commandFile)
        logger.writeLog(3, "ImageMagick execute command: " .. command_line)
        if LrTasks.execute(command_line) ~= 0 then
            logger.writeLog(0, "Failed to contact ImageMagick Application")
            success = false
        end
        
        -- clean-up command file
        local cmdFile = io.open(handle.commandFile, "w")
        io.close (cmdFile)

    end

    return success
end

return ImageMagickAPI