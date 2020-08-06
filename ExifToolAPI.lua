--[[----------------------------------------------------------------------------
ExifToolAPI.lua
ExifTool functions for Lightroom thumbnail export
--------------------------------------------------------------------------------
Colin Osborne
August 2020
------------------------------------------------------------------------------]]

--============================================================================--
-- Lightroom imports
local LrDate 			= import 'LrDate'
local LrPathUtils 		= import 'LrPathUtils'
local LrFileUtils 		= import 'LrFileUtils'
-- local LrPrefs	 		= import 'LrPrefs'
local LrTasks 			= import 'LrTasks'

--============================================================================--
-- Local imports
require "Utils.lua"
JSON = assert(loadfile (LrPathUtils.child(_PLUGIN.path, 'JSON.lua')))()

--============================================================================--
-- Local variables
local ExifToolAPI = {}

local tmpdir = LrPathUtils.getStandardFilePath("temp")

local noWhitespaceConversion = true	-- do not convert whitespaces to \n 
local etConfigFile = LrPathUtils.child(_PLUGIN.path, 'Exiftool.conf')

-------------------------------------------------------------------------------
-- ExifTool session handling

function ExifToolAPI.openSession(prefs)
	logger.writeLog(2, 'Starting exiftool session')
	
	handle = _openExifTool(prefs) 
	return handle
	
end

function ExifToolAPI.closeSession(handle)
	logger.writeLog(2, 'Closing exiftool session')
	
	if handle then 
		_closeExifTool(handle)
		--exportParams.exifToolHandle = nil 
	end
end

----------------------------------------------------------------------------------
-- ExifTool get Face Regions

function ExifToolAPI.getFaceRegionsList(h, photoFilename)
	if not _sendCmd(h, "-struct -j -ImageWidth -ImageHeight -Orientation -HasCrop -CropTop -CropLeft -CropBottom -CropRight -CropAngle -XMP-mwg-rs:RegionInfo")
	or not _sendCmd(h, photoFilename, noWhitespaceConversion)
	then
		logger.writeLog(3, string.format("ExifToolAPI.getFaceRegionsList for %s failed: could not read XMP data\n",
							photoFilename))
		return nil
	end  

	local queryResults = _executeCmds(h) 
	if not queryResults then
		logger.writeLog(3, "ExifToolAPI.getFaceRegionsList: execute query failed\n")
		return nil
	end
	
	local results = JSON:decode(queryResults, "ExifToolAPI.getFaceRegionsList(" .. photoFilename .. ")")
	if not results or #results < 1 then
		logger.writeLog(3, "ExifToolAPI.getFaceRegionsList: JSON decode of results failed\n")
		return nil
	end
	
	-- Face Region translations ---------
	local personTags = {}
	local photoDimension = {}
	
	photoDimension.width 		= results[1].ImageWidth
	photoDimension.height 		= results[1].ImageHeight
	photoDimension.orient 		= ifnil(results[1].Orientation, 'Horizontal')
	photoDimension.hasCrop 		= results[1].HasCrop
	photoDimension.cropTop 		= tonumber(ifnil(results[1].CropTop, 0))
	photoDimension.cropLeft		= tonumber(ifnil(results[1].CropLeft, 0))
	photoDimension.cropBottom 	= tonumber(ifnil(results[1].CropBottom, 1))
	photoDimension.cropRight	= tonumber(ifnil(results[1].CropRight, 1))
	photoDimension.cropAngle	= tonumber(ifnil(results[1].CropAngle, 0))

  	if results[1].RegionInfo and results[1].RegionInfo.RegionList and #results[1].RegionInfo.RegionList > 0 then 
		local regionList 			= results[1].RegionInfo.RegionList 
    
    	local photoRotation = string.format("%1.5f", 0)
    	if string.find(photoDimension.orient, 'Horizontal') then
    		photoRotation	= string.format("%1.5f", 0)
    	elseif string.find(photoDimension.orient, '90') then
    		photoRotation = string.format("%1.5f", math.rad(-90))
    	elseif string.find(photoDimension.orient, '180') then
    		photoRotation	= string.format("%1.5f", math.rad(180))
    	elseif string.find(photoDimension.orient, '270') then
    		photoRotation = string.format("%1.5f", math.rad(90))
    	end
    	
    	photoRotation = photoRotation + math.rad(photoDimension.cropAngle)
	
		local j = 0 
		for i = 1, #regionList do
			local region = regionList[i]
			if not region.Type or region.Type == 'Face' then
				local xCentre, yCentre, width, height = tonumber(region.Area.X), tonumber(region.Area.Y), tonumber(region.Area.W), tonumber(region.Area.H)
				j = j + 1
				local personTag = {}
				
				personTag.xCentre 	= xCentre
				personTag.yCentre 	= yCentre
				personTag.w 		= width
				personTag.h 		= height
				personTag.rotation 	= photoRotation
				personTag.trotation = ifnil(region.Rotation, 0.0)
				personTag.name 		= region.Name
				
				personTags[j] = personTag 
				
				logger.writeLog(3, string.format("ExifToolAPI.getFaceRegionsList: Area '%s' --> x:%f y:%f, w:%f, h:%f, rot:%f, trot:%f\n", 
												personTags[j].name,
												personTags[j].xCentre,
												personTags[j].yCentre,
												personTags[j].w,
												personTags[j].h,	
												personTags[j].rotation,	
												personTags[j].trotation	
											))
			end
		end
	end
	
	return personTags, photoDimension
end

-------------------------------------------------------------------------------
-- ExifTool session handling - local functions

function _openExifTool(prefs)
	local h = {} -- handle
	
	h.exiftool = prefs.exiftoolprog
	if not LrFileUtils.exists(h.exiftool) then 
		logger.writeLog(1, "ExifToolAPI: Cannot start exifTool Listener: " .. h.exiftool .. " not found\n")
		return false 
	end
	
	-- create unique CommandFile and LogFile
	h.etCommandFile = LrPathUtils.child(tmpdir, "ExiftoolCmds-" .. tostring(LrDate.currentTime()) .. ".txt")
	h.etLogFile = LrPathUtils.replaceExtension(h.etCommandFile, "log")
	h.etErrLogFile = LrPathUtils.replaceExtension(h.etCommandFile, "error.log")

	-- open and truncate commands file
	local cmdFile = io.open(h.etCommandFile, "w")
	io.close (cmdFile)

	LrTasks.startAsyncTask ( function()
        	local cmdline = cmdlineQuote() .. 
        					'"' .. h.exiftool .. '" ' ..
        					'-config "' .. etConfigFile .. '" ' ..
        					'-stay_open True ' .. 
        					'-@ "' .. h.etCommandFile .. '" ' ..
        					' -common_args -charset filename=UTF8 -overwrite_original -fast2 -m ' ..
        					'> "'  .. h.etLogFile .. 	'" ' ..
        					'2> "' .. h.etErrLogFile .. '"' .. 
        					cmdlineQuote()
        	local retcode
        	
        	logger.writeLog(3, string.format("exiftool Listener(%s): starting ...\n", cmdline))
        	h.cmdNumber = 0
        	local exitStatus = LrTasks.execute(cmdline)
        	if exitStatus > 0 then
        		logger.writeLog(1, string.format("exiftool Listener(%s): terminated with error %s\n", h.etCommandFile, tostring(exitStatus)))
        		retcode = false
        	else
        		logger.writeLog(3, string.format("exiftool Listener(%s): terminated.\n", h.etCommandFile))
        		retcode = true
        	end
        
        	-- Clean-up
        	LrFileUtils.delete(h.etCommandFile)
        	LrFileUtils.delete(h.etLogFile)
        	LrFileUtils.delete(h.etErrLogFile)
        	
        	return retcode
        end 
	)	
	
	return h
end

function _closeExifTool(h)
	if h then	
		logger.writeLog(4, "ExifToolAPI: closing exiftool session\n")
		_sendCmd(h, "-stay_open False")
		return true
	else
		return false
	end
end

function _sendCmd(h, cmd, noWsConv)
	if not h then return false end

	-- commands, parameters & options all separated by \n
	local cmdlines = iif(noWsConv, cmd .. "\n", string.gsub(cmd,"%s", "\n") .. "\n")
	logger.writeLog(4, "_sendCmd:\n" .. cmdlines)
	
	local cmdFile = io.open(h.etCommandFile, "a")
	if not cmdFile then return false end
	
	cmdFile:write(cmdlines)
	io.close(cmdFile)
	return true;
end

function _executeCmds(h)
	h.cmdNumber = h.cmdNumber + 1
	
	if not _sendCmd(h, string.format("-execute%04d\n", h.cmdNumber)) then
		return nil
	end
	
	-- wait for exiftool to acknowledge the command
	local cmdResult = nil
	local startTime = LrDate.currentTime()
	local now = startTime
	local expectedResult = iif(h.cmdNumber == 1, 
								string.format(					"(.*){ready%04d}",	  			    h.cmdNumber),
								string.format("{ready%04d}[\r\n]+(.*){ready%04d}", h.cmdNumber - 1, h.cmdNumber))
								
	
	while not cmdResult  and (now < (startTime + 10)) do
		LrTasks.yield()
		if LrFileUtils.exists(h.etLogFile) and LrFileUtils.isReadable(h.etLogFile) then 
			local resultStrings
			local logfile = io.input (h.etLogFile)
			resultStrings = logfile:read("*a")
			io.close(logfile)
			if resultStrings then
--				writeLogfile(4, "_executeCmds(): got response file contents:\n" .. resultStrings .. "\n")
				cmdResult = string.match(resultStrings, expectedResult) 
			end
		end
		now = LrDate.currentTime()
	end
	logger.writeLog(3, string.format("_executeCmds(%s, cmd %d) took %d secs, got:\n%s\n", h.etLogFile, h.cmdNumber, now - startTime, ifnil(cmdResult, '<Nil>', cmdResult)))
	return cmdResult 
end

return ExifToolAPI