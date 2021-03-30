--[[----------------------------------------------------------------------------
Utils.lua
Helper functions for Lightroom face labelling export plugin

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
local LrDate            = import("LrDate")
local LrFileUtils       = import("LrFileUtils")
local LrPathUtils       = import("LrPathUtils")
local LrTasks           = import("LrTasks")
local LrFunctionContext = import("LrFunctionContext")

--============================================================================--
-- Local imports

--============================================================================--
-- Local variables
local tmpdir = LrPathUtils.getStandardFilePath("temp")

local utils = {}

--============================================================================--
-- Functions

--------------------------------------------------------------------------------
-- Check if file is present

function utils.file_present( file )
    local file_present = true
    
    if not file then
        file_present = false
    else
        file_present = LrFileUtils.exists(file)
    end
    
    return file_present
end

--------------------------------------------------------------------------------
-- Split text nicely over specified number of lines

-- adapted from: https://stackoverflow.com/questions/5059956/algorithm-to-divide-text-into-3-evenly-sized-groups
function utils.text_line_wrap(text, num_lines)
    words = {}
    for word in text:gmatch("%w+") do table.insert(words, word) end
    num_words = #words
    num_lines = math.min(num_lines, num_words) -- no more lines than words
    
    cumulative_width = {}
    cumulative_width[1] = 0
    for i, word in pairs(words) do
        --logger.writeLog(5, "'" .. word .. "'")
        table.insert(cumulative_width, cumulative_width[#cumulative_width] + string.len(word))
    end
    total_width = cumulative_width[#cumulative_width] + #words - 1 -- len words -1 space
    line_width = (total_width - (num_lines - 1)) / num_lines -- num_lines-1 line breaks
    
    -- cost of a line (words[i] .. words[j-1])
    -- lua table indexes start at 1 (not 0)
    function cost(i, j)
        actual_line_width = math.max(j - i - 1, 0) + cumulative_width[j+1] - cumulative_width[i+1]
        return (line_width - actual_line_width)^2
    end
    
    best = {}
    cost_index_list = {}
    cost_index_pair = {cost = 0, word_index = nil}
    cost_index_list[1] = cost_index_pair
    for w = 1, #words do -- initialise array
        cost_index_pair = {cost = math.huge, word_index = nil}
        cost_index_list[w+1] = cost_index_pair
    end
    table.insert(best, cost_index_list)
    
    for l = 1, num_lines do
        cost_index_list = {}
        for j = 0, num_words do
            min_cost = math.huge -- initial value
            min_index = 0 -- initial value
            for k = 0, j do
                --logger.writeLog(1, string.format("index l,j,k: %d,%d,%d", l,j,k))
                k_cost = best[l-1+1][k+1].cost + cost(k,j)
                if k_cost < min_cost then
                    min_cost = k_cost
                    min_index = k
                end
            end
            table.insert(cost_index_list, {cost = min_cost, word_index = min_index})
        end -- for j
        table.insert(best, cost_index_list)
    end -- for i
    
    lines_reverse_order = {}
    b = num_words
    for l = num_lines, 1, -1 do
        a = best[l+1][b+1].word_index
        sliced = {}
        for i=a+1, b do sliced[#sliced+1] = words[i] end
        line_string = table.concat(sliced, ' ')
        --logger.writeLog(5, "'" .. line_string .. "'")
        table.insert(lines_reverse_order, line_string) -- was: ' ' .. line_string
        b = a
    end
    
    lines = utils.list_reverse(lines_reverse_order)
    lines_string = table.concat(lines, "\n")
    
    return lines_string
end

--------------------------------------------------------------------------------
-- String randomisation, e.g. for photo label obfuscation

function utils.randomise_string(s)
    math.randomseed(os.time())
    char_list = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
    digit_list = '0123456789'
    
    rand_s = '' -- initial value
    if s and #s>0 then
        for i = 1, #s do
            char = string.sub(s, i, i)
            if char == ' ' then -- keep spaces as spaces
                rand_char = ' '
            elseif tonumber(char) then -- numeric
                rand = math.random(1, #digit_list)
                rand_char = string.sub(digit_list, rand, rand)
            else -- not space or numeric, so use alphabetic character
                rand = math.random(1, #char_list)
                rand_char = string.sub(char_list, rand, rand)
            end
            rand_s = rand_s .. rand_char
        end
    else
        rand_s = s
    end
    
    return rand_s
end

--------------------------------------------------------------------------------
-- Reverse the order of a list

function utils.list_reverse(list)
    reversed = {}
    if list and #list > 0 then
        for i = 1, #list do
            reversed[i] = list[#list - i + 1]
        end
    end
    return reversed
end

--------------------------------------------------------------------------------
-- List to comma-separated text string

function utils.list_to_text(list)
    local string = '' -- initial value
    if list == nil then
        string = 'nil'
    else -- if list
        if type(list)=='table' then
            for i, entry in pairs(list) do
                if i ~= 1 then string = string .. ', ' end
                string = string .. tostring(entry)
            end -- for i, entry
        else -- if type
            string = tostring(list) -- handle non-list cases for completeness
        end -- if type; else
    end -- if list; else
    return string
end

--------------------------------------------------------------------------------
-- Table copying

-- https://stackoverflow.com/questions/640642/how-do-you-copy-a-lua-table-by-value
function utils.table_copy(obj, seen)
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end
    local s = seen or {}
    local res = setmetatable({}, getmetatable(obj))
    s[obj] = res
    for k, v in pairs(obj) do res[utils.table_copy(k, s)] = utils.table_copy(v, s) end
    return res
end

--------------------------------------------------------------------------------
-- Condition handling helpers

function utils.ifnil(str, alternate)
    result = str -- initial value
    if str == nil then result = alternate end
	return result
end 

function utils.iif(condition, then_expr, else_expr)
    result = nil -- initial value
	if condition then result = then_expr else result = else_expr end
	return result
end

--------------------------------------------------------------------------------
-- Quote helper for Windows vs Mac

-- on Windows, whole command line needs to be wrapped in an additional set of quotes
-- to handle case where exe or other arguments are also quoted (e.g. to handle spaces in paths)
function utils.command_line_quote(command_line)
    if WIN_ENV == true then
        command_line = '"' .. command_line .. '"'
    else -- Mac
        command_line = command_line -- no change
    end
    
    return command_line
end

--------------------------------------------------------------------------------
-- System command execution and results return

-- https://community.adobe.com/t5/lightroom-classic/get-output-from-lrtasks-execute-cmd/td-p/8778861?page=1

--[[----------------------------------------------------------------------------
public int exitCode, string output, string errOutput
safeExecute (string commandLine [, boolean getOutput])
Executes the command line "commandLine"in the platform shell via
LrTasks.execute, working around a bug in execute() on Windows where quoted
program names aren't accepted.
If "getOutput" is true, "output" will contain standard out and standard
error and "errOutput" will be "".  If "getOutput" is "separate", then
"output" will contain standard out and "errOutput" will contain standard
error.  If "getOutput" is false, then both "output" and "errOutput" will be
"".
Returns in "exitCode" the exit code of the command line. If any errors
occur in safeExecute itself, "exitCode" will be -1, and "output" and
"errOutput" will be:
getOuptut == "separate": "", <error message>
otherwise:              <error message>, ""
------------------------------------------------------------------------------]]
function utils.safeExecute (commandLine, getOutput)
return LrFunctionContext.callWithContext ("", function (context)
    local outFile, errFile
    context:addCleanupHandler (function ()
        if outFile then LrFileUtils.delete (outFile) end
        if errFile then LrFileUtils.delete (errFile) end
        end)
       
    if getOutput then
        dateStr = tostring(LrDate.currentTime())
        outFile = LrPathUtils.child(tmpdir, 'safeExecute-' .. dateStr .. '.txt')
        commandLine = commandLine .. ' > "' .. outFile .. '"'
        if getOutput == "separate" then
            errFile = child (tmpdir, uuid .. ".err")
            commandLine = commandLine .. ' 2>"' .. errFile .. '"'
        else
            commandLine = commandLine .. ' 2>&1'
            end
        end
        
    if WIN_ENV then commandLine = '"' .. commandLine .. '"' end
    
    local exitStatus = LrTasks.execute (commandLine)
    local output, errOutput, success = "", ""
    
    local function outputErr (file, output)
        local err = string.format ("Couldn't read output:\n%s\n%s",
            file, output)
        if getOutput == "separate" then
            return -1, "", err
        else
            return -1, err, ""
            end
        end
        
    if outFile then
        success, output = pcall (LrFileUtils.readFile, outFile)
        if not success then return outputErr (outFile, output) end
        end
        
    if errFile then
        success, errOutput = pcall (LrFileUtils.readFile, errFile)
        if not success then return outputErr (errFile, errOutput) end
        end
        
    return exitStatus, output, errOutput
    end) end

--------------------------------------------------------------------------------
-- Number rounding to decimal places
-- http://lua-users.org/wiki/SimpleRound

function utils.round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

--------------------------------------------------------------------------------
-- return table

return utils