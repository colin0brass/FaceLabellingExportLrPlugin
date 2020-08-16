--[[----------------------------------------------------------------------------
ImageMagickAPI.lua
ImageMagick functions for Lightroom thumbnail export

--------------------------------------------------------------------------------
Copyright 2020 Colin Osborne

This file is part of FaceLabellingExport, a Lightroom plugin

FaceLabellingExport is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FaceLabellingExport is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

FaceLabellingExport requires the following additional software:
- imagemagick, convert      http://www.imagemagick.org/
- exiftool                  https://exiftool.org

------------------------------------------------------------------------------]]

--============================================================================--
-- Lightroom imports
local LrDate 			= import 'LrDate'
local LrPathUtils 		= import 'LrPathUtils'
local LrFileUtils 		= import 'LrFileUtils'
local LrTasks 			= import 'LrTasks'

--============================================================================--
-- Local imports
require "Utils.lua"

--============================================================================--
-- Local variables
local ImageMagickAPI = {}

local tmpdir = LrPathUtils.getStandardFilePath("temp")

--============================================================================--
-- Functions

--------------------------------------------------------------------------------
-- ImageMagick session handling

function ImageMagickAPI.init(prefs)
    local handle = {} -- handle
    handle.app = prefs.imageMagickApp
    handle.convert_app = prefs.imageConvertApp
        
    -- create unique command file
    local dateStr = tostring(LrDate.currentTime())
    handle.commandFile = LrPathUtils.child(tmpdir, "ImageMagicCmds-" .. dateStr .. ".txt")
    
    -- create and truncate command file
    logger.writeLog(4, "ImageMagick command file:" .. handle.commandFile)
    local cmdFile = io.open(handle.commandFile, "w")
    io.close(cmdFile)
    
    return handle
end

function ImageMagickAPI.cleanup(handle, leave_command_file)
    success = true
    if handle then
        logger.writeLog(4, "ImageMagic: cleaning-up after use")
        if not leave_command_file then
            if LrFileUtils.exists(handle.commandFile) then
                LrFileUtils.delete(handle.commandFile)
            end
        end
    end
    
    return success
end

--------------------------------------------------------------------------------
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

function ImageMagickAPI.execute_commands(handle, leave_command_file)
    success = true
    if not handle then
        success = false
    else
        exe = handle.app
        if not LrFileUtils.exists(handle.commandFile) then
            logger.writeLog(0, "Could not find ImageMagick command file:" .. handle.commandFile)
        end
        
        command_line = exe .. " -script " .. path_quote_selection_for_platform(handle.commandFile)
        logger.writeLog(4, "ImageMagick execute command: " .. command_line)
        if LrTasks.execute(command_line) ~= 0 then
            logger.writeLog(0, "Failed to contact ImageMagick Application")
            success = false
        end
        
        -- clean-up command file
        if not leave_command_file then
            local cmdFile = io.open(handle.commandFile, "w")
            io.close (cmdFile)
        end

    end

    return success
end

function ImageMagickAPI.execute_convert_get_output(handle, command_string)
    success = true
    output = ""
    if not handle then
        success = false
    else
        exe = handle.convert_app

        command_line = exe .. " " .. command_string
        logger.writeLog(5, "ImageMagick execute command: " .. command_line)

        exitStatus, output, errOutput = safeExecute(command_line, true)
        if exitStatus then
            logger.writeLog(5, "ImageMagick output: " .. output)
        else
            success = false
            logger.writeLog(0, "ImageMagick safeExecute failed: " .. errOutput)
        end
        
    end

    return success, output
end

--------------------------------------------------------------------------------
-- return table

return ImageMagickAPI