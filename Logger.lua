--[[----------------------------------------------------------------------------
Logger.lua
Logging helper functions for Lightroom thumbnail export
--------------------------------------------------------------------------------
Colin Osborne
July 2020
------------------------------------------------------------------------------]]

--============================================================================--
-- Lightroom imports
local LrLogger = import("LrLogger")

--============================================================================--
-- Local imports

require "Utils.lua"

-------------------------------------------------------------------------------

local logger = {}

filename = "logger"
log_level_threshold = 2
local myLogger = {}

function logger.init(filename, set_log_level_threshold)
	log_level_threshold = set_log_level_threshold
	
	myLogger = LrLogger(filename)
	myLogger:enable("logfile")
end
	
function logger.writeLog(level, message)
	if level <= log_level_threshold then
		myLogger:trace(message)
	end
end

-- getAttrValueOutputString(key, value, pwKeyPattern, hideKeyPattern)
-- returns the output string of an key-value-pair according to given keyname pattern for passwords
-- and for keys to hide
function getAttrValueOutputString(key, value, pwKeyPattern, hideKeyPattern)
	if hideKeyPattern and string.match(key, hideKeyPattern) then
		return nil
	elseif pwKeyPattern and string.match(key, pwKeyPattern) then
		return '"' .. key ..'":"***"'
	else
		return '"' .. key ..'":"' .. tostring(ifnil(value, '<Nil>')) ..'"'
	end
end

function logger.writeTable(level, tableName, printTable, compact, pwKeyPattern, hideKeyPattern, isObservableTable)
	if level > ifnil(loglevel, 2) then return end
	
	local tableCompactOutputLine = {}
	
	if type(printTable) ~= 'table' then
		logger.writeLog(level, tableName .. ' is not a table, but ' .. type(printTable) .. '\n')
		return
	end
	
	-- the pairs() iterator is different for observable tables
	local pairs_r1, pairs_r2, pairs_r3
	if isObservableTable then
		pairs_r1, pairs_r2, pairs_r3 = printTable:pairs()
	else
		pairs_r1, pairs_r2, pairs_r3 = pairs(printTable)
	end
	
	if not compact then logger.writeLog(level, '"' .. tableName .. '":{\n') end
--	for key, value in pairs( printTable ) do
	for key, value in pairs_r1, pairs_r2, pairs_r3 do
		if type(key) == 'table' then
			local outputLine = {}
			if not compact then
				logger.writeLog(level, '\t<table>' .. ':{' ..  iif(compact, ' ', '\n'))
			end
			for key2, value2 in pairs( key ) do
				local attrValueString = getAttrValueOutputString(key2, value2, pwKeyPattern, hideKeyPattern)
				
				if compact then
					table.insert(outputLine, attrValueString)
				else	
					logger.writeLog(level, '\t\t' .. attrValueString .. '\n')
				end
			end
			if attrValueString then
				if compact then
					table.sort(outputLine)
					table.insert(tableCompactOutputLine, '\n\t\t<table> : {' .. table.concat(outputLine, ', ') .. '}')
				else				
					logger.writeLog(level, '\t}\n')
				end
			end
		elseif type(value) == 'table' and not (hideKeyPattern and string.match(key, hideKeyPattern)) then
			local outputLine = {}
			if not compact then
				logger.writeLog(level, '\t"' .. key .. '":{' ..  iif(compact, ' ', '\n'))
			end
			for key2, value2 in pairs( value ) do
				local attrValueString = getAttrValueOutputString(key2, value2, pwKeyPattern, hideKeyPattern)
				if attrValueString then
					if compact then
						table.insert(outputLine, attrValueString)
					else	
						 logger.writeLog(level, '\t\t' .. attrValueString .. '\n') 
					end
				end
			end
			if compact then
				table.sort(outputLine)
				table.insert(tableCompactOutputLine, '\n\t\t"' .. key .. '":{' .. table.concat(outputLine, ', ') .. '}')
			else				
				logger.writeLog(level, '\t}\n')
			end
		else
			local attrValueString = getAttrValueOutputString(key, value, pwKeyPattern, hideKeyPattern)
			if attrValueString then
				if compact then 
					table.insert(tableCompactOutputLine, attrValueString)
				else
					logger.writeLog(level, '	' .. attrValueString .. '\n')
				end
			end
		end
	end

	if compact then
		table.sort(tableCompactOutputLine)
		logger.writeLog(level, '"' .. tableName .. '":{' .. table.concat(tableCompactOutputLine, ', ') .. '\n\t}\n')
	else
		logger.writeLog(level, '}\n')
	end
end

return logger