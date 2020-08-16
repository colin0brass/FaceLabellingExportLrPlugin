--[[----------------------------------------------------------------------------
Logger.lua
Logging helper functions for Lightroom thumbnail export

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

--============================================================================--
-- Functions

--------------------------------------------------------------------------------
-- init

function logger.init(filename, set_log_level_threshold)
	log_level_threshold = set_log_level_threshold
	
	myLogger = LrLogger(filename)
	myLogger:enable("logfile")
	
    -- open and truncate log file if it already exists
	local docdir = LrPathUtils.getStandardFilePath("documents")
	local file_path = LrPathUtils.child(
	                    LrPathUtils.child(docdir, 'LrClassicLogs'), 
	                    filename .. '.log')
	if LrFileUtils.exists(file_path) then
	    local file = io.open(file_path, "w")
	    if file then
            io.close(file)
        end -- if file
    end -- if LrFileUtils.exists(file_path)
end
	
--------------------------------------------------------------------------------
-- write message to log file

function logger.writeLog(level, message)
	if level <= log_level_threshold then
		myLogger:trace(level .. " : " .. message)
	end
end

--------------------------------------------------------------------------------
-- write table (recursively if needed) to log file

function logger.writeTable(level, tbl, indent)
    if level <= log_level_threshold then
        if not indent then indent = 0 end
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
                else
                    logger.writeLog(level, formatting .. v)
                end
            end
        end -- for k, v in pairs(tbl)
    end -- if level <= log_level_threshold
end

--------------------------------------------------------------------------------
-- return table

return logger