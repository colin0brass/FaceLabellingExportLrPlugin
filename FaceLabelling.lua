--[[----------------------------------------------------------------------------
FaceLabelling.lua
Main face labelling functions for Lightroom face labelling export plugin
--------------------------------------------------------------------------------
Colin Osborne
August 2020
------------------------------------------------------------------------------]]

--============================================================================--
-- Lightroom imports
local LrDate      = import('LrDate')
local LrPathUtils = import("LrPathUtils")
local LrFileUtils = import("LrFileUtils")
local LrTasks     = import("LrTasks")

--============================================================================--
-- Local imports
require "Utils.lua"
ExifToolAPI       = require("ExifToolAPI.lua")
ImageMagickAPI    = require("ImageMagickAPI.lua")

--============================================================================--
-- Local variables
local FaceLabelling = {}

local exportParams = {} -- should probably pick this up properly from FaceLabellingExportService

-- override of paths until prefs properly integrated into dialogs
local prefs_override = {}
prefs_override.exiftoolprog = LrPathUtils.child(_PLUGIN.path, 'ExifTool/exiftool')
--prefs_override.imageMagicApp = "/usr/local/bin/magick"
prefs_override.imageMagicApp = LrPathUtils.child(_PLUGIN.path, 'ImageMagick/magick2')

-------------------------------------------------------------------------------

function FaceLabelling.renderPhoto(photo, pathOrMessage)
    local success = true
    local failures = {}
    
    -- create summary of people from regions 
    facesLr, photoDimension = FaceLabelling.getRegions(photo)
    local people = {}
    if facesLr and #facesLr > 0 then
        for i, regionFaces in pairs(facesLr) do
            local name = ifnil(regionFaces.name, 'Unknown')
            w = math.floor( photoDimension.width * regionFaces.w + 0.5)
            h = math.floor( photoDimension.height * regionFaces.h + 0.5)
            xCentre = photoDimension.width * regionFaces.xCentre
            yCentre = photoDimension.height * regionFaces.yCentre
            x = math.floor( xCentre - w/2 + 0.5)
            y = math.floor( yCentre - h/2 + 0.5)
            
            logger.writeLog(4, string.format("%d: Name '%s', x:%d y:%d, w:%d, h:%d", 
                i, name, x, y, w, h))
            --local cropDimensions = string.format("%dx%d+%d+%d", w, h, x, y)
            
            person = {}
            person.x = x
            person.y = y
            person.w = w
            person.h = h
            person.name = name
            
            people[i] = person

        end -- for i, regionFaces in pairs(facesLr)
    end -- if facesLr and #facesLr > 0

    -- create labels
    local labels = {}
    -- TODO

    -- input file
    exported_file = path_quote_selection_for_platform(pathOrMessage)
    ImageMagickAPI.add_command_string(exportParams.imageMagickHandle, exported_file)

    command_string = '# Person face outlines'
    ImageMagickAPI.add_command_string(exportParams.imageMagickHandle, command_string)
    command_string = '-strokewidth 10 -stroke white -fill "rgba( 255, 255, 255, 0.0)"'
    ImageMagickAPI.add_command_string(exportParams.imageMagickHandle, command_string)
    for i, person in pairs(people) do -- is this robust for zero length?
        command_string = string.format('-draw "rectangle %d,%d %d,%d"',
                person['x'], person['y'], person['x']+person['w'], person['y']+person['h'])
        ImageMagickAPI.add_command_string(exportParams.imageMagickHandle, command_string)
    end
    
    -- output file
    local filename = LrPathUtils.leafName( pathOrMessage )
    exported_path = LrPathUtils.parent(pathOrMessage)
    outputPath = path_quote_selection_for_platform( LrPathUtils.child(exported_path, filename) )
    command_string = "-write " .. outputPath
    ImageMagickAPI.add_command_string(exportParams.imageMagickHandle, command_string)

    ImageMagickAPI.execute_commands(exportParams.imageMagickHandle)
    
    return success, failures
end

function FaceLabelling.start()
    logger.writeLog(4, "FaceLabelling.start")
    local handle = ExifToolAPI.openSession(prefs_override)
    if not handle then
        logger.writeLog(0, "Failed to start exiftool")
        return
    else
        exportParams.exifToolHandle = handle
    end
    
    exportParams.imageMagickHandle = ImageMagickAPI.init(prefs_override)
end

function FaceLabelling.stop()
    logger.writeLog(4, "FaceLabelling.stop")
    ExifToolAPI.closeSession(exportParams.exifToolHandle)
    
    success = ImageMagickAPI.cleanup(exportParams.imageMagickHandle)
end

function FaceLabelling.getRegions(photo)
    logger.writeLog(2, 'Parse photo: ' .. photo:getRawMetadata('path'))
    exifToolHandle = exportParams.exifToolHandle
    local facesLr, photoDimension = ExifToolAPI.getFaceRegionsList(exifToolHandle, photo:getRawMetadata('path'))
    
    return facesLr, photoDimension
    
end

return FaceLabelling