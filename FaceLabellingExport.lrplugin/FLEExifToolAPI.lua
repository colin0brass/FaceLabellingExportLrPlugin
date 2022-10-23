--[[----------------------------------------------------------------------------
FLEExifToolAPI.lua
ExifTool functions for Lightroom face labelling export plugin

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
require("Utils.lua")
json = require("json.lua")

--============================================================================--
-- Local variables
local FLEExifToolAPI = {}

--============================================================================--
-- Functions

--------------------------------------------------------------------------------
-- ExifTool session handling

function FLEExifToolAPI.openSession(exportParams)
	logger.writeLog(2, 'Starting exiftool session')

	handle = _openExifTool(exportParams)
	return handle
end

function FLEExifToolAPI.closeSession(handle)
	logger.writeLog(2, 'Closing exiftool session')

	if handle then
		_closeExifTool(handle)
	end
end

--------------------------------------------------------------------------------
-- ExifTool get Face Regions and Photo Info

function FLEExifToolAPI.getFaceRegionsAndPhotoInfo(handle, photoFilename)
    local success = true -- initial value
    local queryResults = nil -- initial value
    local personTags = {} -- initial value
    local photoSize = {} -- initial value
    local photoDescription = '' -- initial value

    -- Define which fields to retrieve from EXIF using ExifTool and custom config (script) file
    local exif_command = '-struct -j -RegionsAbsoluteNotFocus -Description -ImageWidth'
    if logger.get_log_level() >= 5 then -- get more information to help with debug
        exif_command = exif_command .. ' -RegionsCentred -AlreadyApplied -ImageHeight -Orientation'
    end

	success = _exifTool_send_command(handle, exif_command)
	success = success and _exifTool_send_filename(handle, photoFilename)

	if not success then
		logger.writeLog(2, string.format("FLEExifToolAPI.getFaceRegionsList send command failed: %s",
							photoFilename))
	else
        success, queryResults = _exifTool_execute_commands(handle)
        if not success or not queryResults then
            logger.writeLog(2, "FLEExifToolAPI.getFaceRegionsList: exiftool execution failed")
        else
            logger.writeLog(5, queryResults)
            local results = json.parse(queryResults)
            if not results or #results < 1 then
                logger.writeLog(2, "FLEExifToolAPI.getFaceRegionsList: JSON decode of results failed")
                success = false
            else
                logger.writeTable(5, results) -- write to log for debug
                personTags, photoSizes = _extract_face_regions(results[1])
                photoDescription = utils.ifnil(results[1].Description, '')
            end
        end
    end

	return personTags, photoSizes, photoDescription
end

--------------------------------------------------------------------------------
-- ExifTool add Face Region

function FLEExifToolAPI.addFaceRegion(handle, personTag, photoFilename, replace)
    local success = true -- initial value

    local join_operator = '+=' -- default is to append
    if replace then
        join_operator = '=' -- replace without appending
    else
        join_operator = '+=' -- append
    end

    local exif_command = string.format('-regionlist%s{Area={H=%.1f,W=%.1f,X=%.1f,Y=%.1f,Unit=%s},Name=\'%s\',Type=Face}',
                                        join_operator,
                                        personTag.h, personTag.w,
                                        personTag.x, personTag.y,
                                        personTag.unit,
                                        personTag.name)

	success = _exifTool_send_command(handle, exif_command)
	success = success and _exifTool_send_filename(handle, photoFilename)

	if not success then
		logger.writeLog(2, string.format("FLEExifToolAPI.addFaceRegion send command failed: %s",
							photoFilename))
	else
	    logger.writeLog(3, string.format("FLEExifToolAPI.addFaceRegion: %s", photoFilename))
	    logger.writeLog(3, exif_command)
	    success, queryResults = _exifTool_execute_commands(handle)
	end
end

--------------------------------------------------------------------------------
-- extract and calculate face region bounding boxes

function _extract_face_regions(results)
    local personTags = {}
    local photoSize = {}

    logger.writeLog(3, "_extract_face_regions")
    photoSize.width   = results.ImageWidth
    if results.RegionsAbsoluteNotFocus then
        local regionsInfo = results.RegionsAbsoluteNotFocus
        photoSize.height  = regionsInfo.ImageInfo.ImageHeight
        photoSize.orient  = regionsInfo.ImageInfo.Orientation
        photoSize.CropX   = utils.ifnil(regionsInfo.ImageInfo.CropX, 0)
        photoSize.CropY   = utils.ifnil(regionsInfo.ImageInfo.CropY, 0)
        photoSize.CropW   = utils.ifnil(regionsInfo.ImageInfo.CropW, photoSize.width)
        photoSize.CropH   = utils.ifnil(regionsInfo.ImageInfo.CropH, photoSize.height)
        photoSize.HasCrop = utils.ifnil(regionsInfo.ImageInfo.HasCrop, false)

        if regionsInfo.RegionList and #regionsInfo.RegionList > 0 then
            local regionList = regionsInfo.RegionList

            face_num = 0
            for i = 1, #regionList do
                logger.writeLog(3, "_extract_face_regions: num " .. i)
                local region = regionList[i]
                if (region.Type == 'Face') or (not region.Type) then
                    local personTag = {}
                    face_num = face_num + 1

                    personTag.x 	    = tonumber(region.Area.X)
                    personTag.y 	    = tonumber(region.Area.Y)
                    personTag.w 		= tonumber(region.Area.W)
                    personTag.h 		= tonumber(region.Area.H)
                    personTag.name 		= tostring(utils.ifnil(region.Name,''))

                    personTags[face_num] = personTag

                    logger.writeLog(4, string.format("_extract_face_regions: Area %d: '%s': x:%d y:%d, w:%d, h:%d",
                                                    face_num,
                                                    personTags[face_num].name,
                                                    personTags[face_num].x,
                                                    personTags[face_num].y,
                                                    personTags[face_num].w,
                                                    personTags[face_num].h
                                                ))
                end -- if not region.Type ...
            end -- for i = 1, #regionList
        end -- if regionsInfo.RegionList ...
    end -- if results.RegionsAbsoluteNotFocus

    return personTags, photoSize
end

--------------------------------------------------------------------------------
-- ExifTool session handling - local functions

function _openExifTool(exportParams)
	local handle = {} -- handle
	local success = true -- initial value

    local tmpdir = LrPathUtils.getStandardFilePath("temp")
    local exiftool_config_file = LrPathUtils.child(_PLUGIN.path, "get_regions.config")

	-- create unique CommandFile and LogFile
    local dateStr = tostring(LrDate.currentTime())
	handle.exiftool_command_file   = LrPathUtils.child(tmpdir, "exiftool_commands_" ..
	                                                   dateStr .. ".txt")
	handle.exiftool_log_file       = LrPathUtils.replaceExtension(handle.exiftool_command_file, "log")
	handle.exiftool_error_log_file = LrPathUtils.replaceExtension(handle.exiftool_command_file, "error.log")

    handle.cmd_num = 0

    local exif_args      = ' -common_args -charset filename=UTF8 -overwrite_original -fast2 -m '

	-- open and truncate commands file
	local file = io.open(handle.exiftool_command_file, "w")
	if not file then
	    handle = {}
	    success = false
    else
        io.close (file)

        -- precautionary check and delete, really for debugging with re-used files
        if LrFileUtils.exists(handle.exiftool_log_file) then LrFileUtils.delete(handle.exiftool_log_file) end
        if LrFileUtils.exists(handle.exiftool_error_log_file) then LrFileUtils.delete(handle.exiftool_error_log_file) end

        LrTasks.startAsyncTask ( function()
                local command = '"' .. exportParams.exifToolApp .. '"' ..
                                ' -config ' .. '"' .. exiftool_config_file .. '"' ..
                                ' -stay_open True ' ..
                                ' -@ ' .. '"' .. handle.exiftool_command_file .. '"' ..
                                exif_args ..
                                ' > ' .. '"' .. handle.exiftool_log_file .. '"' ..
                                ' 2> ' .. '"' .. handle.exiftool_error_log_file .. '"'

                logger.writeLog(3, string.format("exiftool starting: %s", command))
                -- on Windows, whole command line needs to be wrapped in an additional set of quotes
                local exitStatus = LrTasks.execute(utils.command_line_quote(command))
                if exitStatus > 0 then
                    logger.writeLog(0, string.format("exiftool error: %s", tostring(exitStatus)))
                    success = false
                end

                -- Clean-up
                if exportParams.exifToolLogDelete then
                    logger.writeLog(3, "exiftool finishing: cleanup")
                    logger.writeLog(5, "deleting:" .. handle.exiftool_command_file)
                    LrFileUtils.delete(handle.exiftool_command_file)
                    logger.writeLog(5, "deleting:" .. handle.exiftool_log_file)
                    LrFileUtils.delete(handle.exiftool_log_file)
                    logger.writeLog(5, "deleting:" .. handle.exiftool_error_log_file)
                    LrFileUtils.delete(handle.exiftool_error_log_file)
                else
                    logger.writeLog(3, "exiftool finishing: leaving files for inspection")
                    logger.writeLog(5, "leaving:" .. handle.exiftool_command_file)
                    logger.writeLog(5, "leaving:" .. handle.exiftool_log_file)
                    logger.writeLog(5, "leaving:" .. handle.exiftool_error_log_file)
                end
            end
        )
    end -- if not file; else

	return handle
end

function _closeExifTool(handle)
    success = true -- initial value
	if not handle then
	    success = false
    else
		logger.writeLog(4, "FLEExifToolAPI: closing exiftool session")
		success = _exifTool_send_command(handle, "-stay_open False")
	end

	return success
end

--------------------------------------------------------------------------------
-- ExifTool command handling - local functions

function _exifTool_send_filename(handle, filename)
    -- send directly with no newline insertion, just newline at end
    return _exifTool_insert_command_lines(handle, filename .. "\n")
end

function _exifTool_send_command(handle, command)
    -- commands, parameters & options all separated by \n
    local command_lines = string.gsub(command,"%s", "\n") .. "\n"
    return _exifTool_insert_command_lines(handle, command_lines)
end

function _exifTool_insert_command_lines(handle, command_lines)
    success = true -- initial value
    if not handle then
        success = false
    else
        logger.writeLog(4, "_exifTool_insert_command_lines:" .. command_lines)
        local command_file = io.open(handle.exiftool_command_file, "a")
        if not command_file then
            success = false
        else
            command_file:write(command_lines)
            io.close(command_file)
        end -- if not command_file; else
    end -- if not handle; else

	return success
end

function _exifTool_execute_commands(handle)
    local success = true -- initial value
    local exiftool_result = nil -- initial value
    local exiftool_expected_result = nil -- initial value

	handle.cmd_num = handle.cmd_num + 1 -- increment ExifTool command number

	-- send execute command
	success = _exifTool_send_command(handle, string.format("-execute%04d\n",
	                                                             handle.cmd_num))

	if success then -- wait for response from ExifTool
	    if handle.cmd_num == 1 then
	        exiftool_expected_result = string.format("(.*){ready%04d}",
	                                                 handle.cmd_num)
	    else
	        exiftool_expected_result = string.format("{ready%04d}[\r\n]+(.*){ready%04d}",
	                                                 handle.cmd_num - 1, handle.cmd_num)
	    end

    	local deadline_time = LrDate.currentTime() + 5 -- number of seconds to wait for result
    	success = false -- initial value on entry to wait for response
        while not exiftool_result and (LrDate.currentTime() < deadline_time) do
            LrTasks.yield()
            if LrFileUtils.exists(handle.exiftool_log_file) then
                local log_file = io.input (handle.exiftool_log_file)
                local log_line = log_file:read("*a")
                io.close(log_file)

                if log_line then
                    exiftool_result = string.match(log_line, exiftool_expected_result)
                    success = true
                end
            end -- if LrFileUtils.exists
        end -- while not exiftool_result and (LrDate.currentTime() < deadline_time)
    end -- if success

    return success, exiftool_result
end

--------------------------------------------------------------------------------
-- return FLEExifToolAPI table

return FLEExifToolAPI