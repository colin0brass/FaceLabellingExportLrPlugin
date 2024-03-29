--[[----------------------------------------------------------------------------
FLEImageMagickAPI.lua
ImageMagick functions for Lightroom face labelling export plugin

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

Inspiration gleaned from:
-- https://github.com/Jaid/lightroom-sdk-8-examples
-- https://github.com/flingo64/PhotoStation-Upload-Lr-Plugin
-- https://stackoverflow.com/questions/5059956/algorithm-to-divide-text-into-3-evenly-sized-groups
-- https://stackoverflow.com/questions/640642/how-do-you-copy-a-lua-table-by-value
-- https://community.adobe.com/t5/lightroom-classic/get-output-from-lrtasks-execute-cmd/td-p/8778861?page=1

------------------------------------------------------------------------------]]

--============================================================================--
-- Lightroom imports
local LrDate 			= import("LrDate")
local LrFileUtils 		= import("LrFileUtils")
local LrPathUtils 		= import("LrPathUtils")
local LrTasks 			= import("LrTasks")

--============================================================================--
-- Local imports
require "Utils.lua"

--============================================================================--
-- Local variables
local FLEImageMagickAPI = {}

--============================================================================--
-- Functions

--------------------------------------------------------------------------------
-- ImageMagick session handling

function FLEImageMagickAPI.init(prefs)
    local handle = {} -- handle
    handle.app         = prefs.imageMagickApp
    handle.convert_app = prefs.imageConvertApp
    handle.log_delete  = prefs.imageMagickLogDelete
        
    -- create unique command file
    local dateStr = tostring(LrDate.currentTime())
    local tmpdir = LrPathUtils.getStandardFilePath("temp")
    handle.commandFile = LrPathUtils.child(tmpdir, "ImageMagicCmds-" .. dateStr .. ".txt")
    
    -- create and truncate command file
    logger.writeLog(4, "ImageMagick command file:" .. handle.commandFile)
    local cmdFile = io.open(handle.commandFile, "w")
    io.close(cmdFile)
    
    return handle
end

function FLEImageMagickAPI.cleanup(handle, leave_command_file)
    local success = true -- initial value
    
    if handle then
        if handle.log_delete then
            logger.writeLog(4, "ImageMagic: cleaning-up after final use")
            logger.writeLog(5, "deleting:" .. handle.commandFile)
            if LrFileUtils.exists(handle.commandFile) then
                LrFileUtils.delete(handle.commandFile)
            end
        else
            logger.writeLog(3, "ImageMagic finishing: leaving final command file for inspection")
            logger.writeLog(5, "leaving:" .. handle.commandFile)
        end
    end
    
    return success
end

--------------------------------------------------------------------------------
-- ImageMagick command handling

function FLEImageMagickAPI.start_new_command(handle)
    if LrFileUtils.exists(handle.commandFile) then
        logger.writeLog(4, "ImageMagic: start_new_command by wiping contents of command file")
        local cmdFile = io.open(handle.commandFile, "w")
        io.close (cmdFile)
    end
end

function FLEImageMagickAPI.add_command_string(handle, command_string)
    local success = true -- initial value
    
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

function FLEImageMagickAPI.execute_commands(handle)
    local success = true -- initial value
    
    if not handle then
        success = false
    else
        if not LrFileUtils.exists(handle.commandFile) then
            logger.writeLog(0, "Could not find ImageMagick command file:" .. handle.commandFile)
        end
        
        local command = '"' .. handle.app .. '"' ..
                        " -script " .. '"' .. handle.commandFile .. '"'
        logger.writeLog(4, "ImageMagick execute command: " .. command)
        -- on Windows, whole command line needs to be wrapped in an additional set of quotes
        local exitStatus = LrTasks.execute(utils.command_line_quote(command))
        if exitStatus > 0 then
            logger.writeLog(0, string.format("ImageMagick error: %s", tostring(exitStatus)))
            success = false
        end
        
        -- clean-up command file
        if handle.log_delete then
            --logger.writeLog(4, "ImageMagic: wipe contents of command file after use")
            local cmdFile = io.open(handle.commandFile, "w")
            io.close (cmdFile)
        else
            --logger.writeLog(4, "ImageMagic: leaving contents of command file after use")
        end

    end

    return success
end

function FLEImageMagickAPI.execute_convert_get_output(handle, command_string)
    local success = true -- initial value
    local output = "" -- initial value
    
    if not handle then
        success = false
    else
        local command = '"' .. handle.convert_app .. '"' ..
                        " " .. command_string
        logger.writeLog(5, "ImageMagick execute command: " .. command)

        -- safeExecute function handles wrapping the whole command line in additional set of quotes for Windows platforms 
        exitStatus, output, errOutput = utils.safeExecute(command, true)
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

return FLEImageMagickAPI