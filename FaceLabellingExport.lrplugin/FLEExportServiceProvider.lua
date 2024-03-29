--[[----------------------------------------------------------------------------
FLEExportServiceProvider.lua
Export service provider description for Lightroom face labelling export plugin

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
local LrDialogs         = import("LrDialogs")
local LrFileUtils       = import("LrFileUtils")
local LrPathUtils       = import("LrPathUtils")
local LrPrefs           = import("LrPrefs")

--============================================================================--
-- Local imports

-- persistent plug-in preferences
local prefs = LrPrefs.prefsForPlugin()

require "FLEExportDialogs.lua"

FLEMain = require "FLEMain.lua"

--============================================================================--
-- Local variables

--============================================================================--
-- Functions

--------------------------------------------------------------------------------
-- processRenderedPhotos

function processRenderedPhotos( functionContext, exportContext )

    -- Update from latest config
    --logger.set_log_level(prefs.logger_verbosity)
    
    logger.writeLog(2, "processRenderedPhotos")
    
    -- Make a local reference to the export parameters.
    local exportSession = exportContext.exportSession
    local exportParams = exportContext.propertyTable
    
    -- Initialise export params from prefs, to ensure set even if dialogs have been bypassed (e.g. "export with previous" menu option)
    FLEMain.init_params_from_prefs(exportParams, prefs)
    
    -- Set progress title.
    local nPhotos = exportSession:countRenditions()
    local progressScope = exportContext:configureProgress {
                        title = nPhotos > 1
                               and LOC("$$$/FaceLabelling/Progress/Several=Exporting ^1 labelled photos", nPhotos)
                               or  LOC("$$$/FaceLabelling/Progress/One=Exporting one labelled photo"),
                    }

    -- Configure export params and start ExifTool service
    logger.writeTable(5, exportParams) -- write to log for debug
    FLEMain.start(exportParams)
        
    -- Iterate through photo renditions
    local failures = {}
    for _, rendition in exportContext:renditions{ stopIfCanceled = true } do
    
        -- Wait for next photo to render
        local success, pathOrMessage = rendition:waitForRender() -- this does the export
        
        -- Check for cancellation again after photo has been rendered
        if progressScope:isCanceled() then break end    
        
        if success then
            logger.writeLog(2,  'Exporting to: ' .. "'" .. pathOrMessage .. "'" )

            local srcPhoto = rendition.photo
            local srcPath  = srcPhoto:getRawMetadata("path")
            local renderedPath = pathOrMessage
            
            -- Render photo with face labels
            success, failures = FLEMain.renderPhoto(srcPath, renderedPath)

        end -- if success
    end -- for _, rendition
    
     -- Stop ExifTool service
    FLEMain.stop()

    -- Display summary failures message if needed
    if #failures > 0 then
        local message
        if #failures == 1 then
            message = LOC("$$$/FaceLabelling/Errors/One=1 labelled photo failed to export correctly")
        else
            message = LOC("$$$/FaceLabelling/Errors/Several=^1 labelled photos failed to export correctly", #failures)
        end
        LrDialogs.message( message, table.concat( failures, "\n" ) )
    end -- if #failures > 0
        
end

--------------------------------------------------------------------------------
-- updateExportSettings

function updateExportSettings ( exportSettings )
    exportSettings.LR_removeFaceMetadata = false -- ensure face meta-data included in file export
    exportSettings.LR_removeLocationMetadata = false -- include location data in export
end

--------------------------------------------------------------------------------
-- Return export service table

return {
    hideSections = { -- 'fileNaming', 'imageSettings',  'fileSettings', 
        'metadata', 'outputSharpening', 'video', 'watermarking' },
    -- chose to hide metadata section since it could cause problems with users disabling metadata export and breaking plugin
    -- see specific override in 'updateExportSettings' function above to enable location meta-data export
        
    --allowFileFormats = nil, -- nil equates to all available formats
    --allowColorSpaces = nil, -- nil equates to all color spaces
    
    startDialog                 = FLEExportDialogs.startDialog,
    endDialog                   = FLEExportDialogs.endDialog,
    sectionsForTopOfDialog      = FLEExportDialogs.sectionsForTopOfDialog,
    sectionsForBottomOfDialog   = FLEExportDialogs.sectionsForBottomOfDialog,
    
    updateExportSettings        = updateExportSettings,
    
    processRenderedPhotos       = processRenderedPhotos,
}