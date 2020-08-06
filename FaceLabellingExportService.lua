--[[----------------------------------------------------------------------------
FaceLabellingExportService.lua
Export service provider description for Lightroom face labelling export plugin
--------------------------------------------------------------------------------
Colin Osborne
August 2020
------------------------------------------------------------------------------]]

--============================================================================--
-- Lightroom imports
local LrPathUtils = import("LrPathUtils")
local LrFileUtils = import("LrFileUtils")
local LrDialogs   = import('LrDialogs')
local LrTasks     = import("LrTasks")

--============================================================================--
-- Local imports

logger = require("Logger.lua")
logger.init("FaceLabelling", 3) -- arguments: log filename, log_level threshold (lowest is most significant)

FaceLabelling = require "FaceLabelling.lua"

-------------------------------------------------------------------------------

function processRenderedPhotos( functionContext, exportContext )

    logger.writeLog(2, "processRenderedPhotos")
    
    -- Make a local reference to the export parameters.
    
    local exportSession = exportContext.exportSession
    local exportParams = exportContext.propertyTable
    
    -- Set progress title.

    local nPhotos = exportSession:countRenditions()

    local progressScope = exportContext:configureProgress {
                        title = nPhotos > 1
                               and LOC( "$$$/FaceLabelling/Progress=Exporting ^1 labelled photos", nPhotos )
                               or LOC "$$$/FaceLabelling/Progress/One=Exporting one labelled photo",
                    }

    FaceLabelling.start() -- start ExifTool service
    
    level=1; tableName='exportParams'; compact=true
    logger.writeTable(level, tableName, exportParams, compact)
    
    path = ''
    if (exportParams.LR_export_destinationType == "desktop" or 
        exportParams.LR_export_destinationType == "documents" or 
        exportParams.LR_export_destinationType == "home" or 
        exportParams.LR_export_destinationType == "pictures") then
        path = LrPathUtils.getStandardFilePath(exportParams.LR_export_destinationType)
    elseif exportParams.LR_export_destinationType == "specificFolder" then
        path = exportParams.LR_export_destinationPathPrefix
    else
        success = false
    end
    
    if exportParams.LR_export_useSubfolder then
        path = LrPathUtils.child(path, exportParams.LR_export_destinationPathSuffix)
    end
    
    -- not sure if path variable extracted above is needed to be used here
    -- after 'waitForRender' then the export path is included in 'pathOrMessage'
    
    logger.writeLog(3, 'path: ' .. path)
    
    -- Iterate through photo renditions.
    local failures = {}
    for _, rendition in exportContext:renditions{ stopIfCanceled = true } do
    
        -- Wait for next photo to render.

        local success, pathOrMessage = rendition:waitForRender() -- this does the export
        
        -- Check for cancellation again after photo has been rendered.
        
        if progressScope:isCanceled() then break end    
        
        if success then
            local photo = rendition.photo
            
            logger.writeLog(2,  'Exporting: ' .. "'" .. pathOrMessage .. "'" )

            success, failures = FaceLabelling.renderPhoto(photo, pathOrMessage)

            logger.writeLog(2, 'Delete file: ' .. pathOrMessage)

            --if not LrFileUtils.delete( pathOrMessage ) then -- delete temp file
            --    logger.writeLog(0, "Failed to delete file: " .. pathOrMessage)
            --end
                    
        end
    end
    
    FaceLabelling.stop() -- stop ExifTool service

    
    if #failures > 0 then
        local message
        if #failures == 1 then
            message = LOC "$$$/FaceLabelling/Errors/OneFileFailed=1 labelled photo failed to export correctly."
        else
            message = LOC ( "$$$/FaceLabelling/Errors/SomeFileFailed=^1 labelled photos failed to export correctly.", #failures )
        end
        LrDialogs.message( message, table.concat( failures, "\n" ) )
    end
end

-------------------------------------------------------------------------------

-- return {
    -- 
    -- hideSections = { 'exportLocation' },
-- 
    -- allowFileFormats = nil, -- nil equates to all available formats
    -- 
    -- allowColorSpaces = nil, -- nil equates to all color spaces
-- 
    -- exportPresetFields = {
        -- { key = 'putInSubfolder', default = false },
        -- { key = 'path', default = 'photos' },
        -- { key = "fullPath", default = nil },
    -- },
-- 
    -- startDialog = ThumbnailExportService.startDialog,
    -- sectionsForBottomOfDialog = ThumbnailExportService.sectionsForBottomOfDialog,
    -- 
    -- processRenderedPhotos = ThumbnailExportService.processRenderedPhotos,
    -- 
-- }

return {
    hideSections = { 'fileNaming', 'fileSettings', 'imageSettings', 
        'outputSharpening', 'metadata', 'video', 'watermarking' },
    --allowFileFormats = nil, -- nil equates to all available formats
    --allowColorSpaces = nil, -- nil equates to all color spaces
    --startDialog = startDialog,
    processRenderedPhotos = processRenderedPhotos,
}