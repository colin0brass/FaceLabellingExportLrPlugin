--[[----------------------------------------------------------------------------
Utils.lua
Helper functions for Lightroom thumbnail export
--------------------------------------------------------------------------------
Colin Osborne
August 2020
------------------------------------------------------------------------------]]

--============================================================================--
-- Lightroom imports
local LrDate 			= import 'LrDate'
local LrPathUtils 		= import 'LrPathUtils'
local LrFileUtils 		= import 'LrFileUtils'
local LrTasks 			= import 'LrTasks'
local LrFunctionContext = import 'LrFunctionContext'

--============================================================================--
-- Local variables
local tmpdir = LrPathUtils.getStandardFilePath("temp")

-------------------------------------------------------------------------------

function list_reverse(list)
    reversed = {}
    if list and #list > 0 then
        for i = 1, #list do
            reversed[i] = list[#list - i + 1]
        end
    end
    return reversed
end

function ifnil(str, subst)
	return ((str == nil) and subst) or str
end 

function iif(condition, thenExpr, elseExpr)
	if condition then
		return thenExpr
	else
		return elseExpr
	end
end

function cmdlineQuote()
	if WIN_ENV then
		return '"'
	elseif MAC_ENV then
		return ''
	else
		return ''
	end
end

function path_quote_selection_for_platform(path)
    if WIN_ENV == true then
        path = path -- no change
    else -- Mac
        path = '"' .. path .. '"'
    end
    
    return path
end

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
function safeExecute (commandLine, getOutput)
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
