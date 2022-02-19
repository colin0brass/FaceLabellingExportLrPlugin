--[[----------------------------------------------------------------------------
Logger.lua
Logging helper functions for Lightroom face labelling export plugin

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
local LrLogger          = import("LrLogger")
local LrPathUtils 		= import 'LrPathUtils'
local LrFileUtils 		= import 'LrFileUtils'

--============================================================================--
-- Local imports
require "Utils.lua"

--============================================================================--
-- Local variables

local logger = {}

filename = "logger"
log_level_threshold = 2 -- defaut
local myLogger = {}

logger.logFilePath = '' -- initial value

--============================================================================--
-- Functions

--------------------------------------------------------------------------------
-- init

function logger.init(filename, set_log_level_threshold)
	logger.set_log_level(set_log_level_threshold)
	
	myLogger = LrLogger(filename)
	myLogger:enable("logfile")
	
    -- open and truncate log file if it already exists
	local docdir = LrPathUtils.getStandardFilePath("documents")
	logger.logFilePath = LrPathUtils.child(
	                    LrPathUtils.child(docdir, 'LrClassicLogs'), 
	                    filename .. '.log')
	if LrFileUtils.exists(logger.logFilePath) then
	    local file = io.open(logger.logFilePath, "w")
	    if file then
            io.close(file)
        end -- if file
    end -- if LrFileUtils.exists(logger.logFilePath)
    logger.writeLog(0, 'logger.init:' .. logger.logFilePath)
end

--------------------------------------------------------------------------------
-- set_log_level

function logger.set_log_level(set_log_level_threshold)
	log_level_threshold = set_log_level_threshold
end
	
--------------------------------------------------------------------------------
-- get_log_level

function logger.get_log_level()
	return log_level_threshold
end
	
--------------------------------------------------------------------------------
-- write message to log file

function logger.writeLog(level, message)
    if log_level_threshold then -- handle case where logger is used during FLEInitPlugin, before logger init 
        if level <= log_level_threshold then
            message = utils.ifnil(message, '')
            if type(message) ~= 'string' then -- == 'boolean' then
                message = tostring(message)
            end
            myLogger:trace(level .. " : " .. message)
        end
    end
end

--------------------------------------------------------------------------------
-- write table (recursively if needed) to log file

function logger.writeTable(level, tbl, indent)
    if level <= log_level_threshold then
        if not indent then indent = 0 end
        if tbl==nil then
            logger.writeLog(level, 'nil')
        elseif type(tbl) ~= 'table' then
            formatting = string.rep("  ", indent) .. tostring(tbl)
            logger.writeLog(level, formatting)
        else
            for k, v in pairs(tbl) do
                if type(k) == "table" then
                    logger.writeTable(level, k, indent+1)
                else
                    formatting = string.rep("  ", indent) .. k .. ": "
                    if type(v) == "table" then
                        logger.writeLog(level, formatting)
                        logger.writeTable(level, v, indent+1)
                    elseif type(v) == 'boolean' then
                        logger.writeLog(level, formatting .. tostring(v))
                    elseif type(v) ~= 'function' then -- don't try to display functions
                        logger.writeLog(level, formatting .. v)
                    end
                end
            end -- for k, v in pairs(tbl)
        end -- if tble==nil; else
    end -- if level <= log_level_threshold
end

--------------------------------------------------------------------------------
-- return table

return logger