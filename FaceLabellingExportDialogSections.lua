--[[----------------------------------------------------------------------------
FaceLabellingExportDialogSections.lua
Export dialog customization for Lightroom face labelling export plugin
--------------------------------------------------------------------------------
Colin Osborne
August 2020
------------------------------------------------------------------------------]]

--============================================================================--
-- Lightroom imports
local LrView = import('LrView')
local LrPathUtils = import("LrPathUtils")
local LrFileUtils 		= import 'LrFileUtils'

--============================================================================--

FaceLabellingExportDialogSections = {}

-------------------------------------------------------------------------------

local function getFullPath( propertyTable )
    success = true
    path = ''
    if (propertyTable.LR_export_destinationType == "desktop" or 
        propertyTable.LR_export_destinationType == "documents" or 
        propertyTable.LR_export_destinationType == "home" or 
        propertyTable.LR_export_destinationType == "pictures") then
        path = LrPathUtils.getStandardFilePath(propertyTable.LR_export_destinationType)
    elseif propertyTable.LR_export_destinationType == "specificFolder" then
        path = propertyTable.LR_export_destinationPathPrefix
    else
        success = false
    end
    
    if propertyTable.LR_export_useSubfolder then
        path = LrPathUtils.child(path, propertyTable.LR_export_destinationPathSuffix)
    end
    
    return success, path
end

local function updateExportStatus( propertyTable )
    local message = nil
    
    repeat -- only goes through once, but using this as easy way to 'break' out

        local success, path = getFullPath( propertyTable )
        if success then
            propertyTable.fullPath = path
        else
            message = "Failed to read export path"
        end
        
        if propertyTable.exifToolApp then
            local found = LrFileUtils.exists(propertyTable.exifToolApp)
            propertyTable.exifToolAppFound = found
            if not found then
                message = "Failed to find ExifTool app"
            end
        end
        
        if propertyTable.imageMagickApp then
            local found = LrFileUtils.exists(propertyTable.imageMagickApp)
            propertyTable.imageMagickAppFound = found
            if not found then
                message = "Failed to find ImageMagick app"
            end
        end
        
        if propertyTable.imageConvertApp then
            local found = LrFileUtils.exists(propertyTable.imageConvertApp)
            propertyTable.imageConvertAppFound = found
            if not found then
                message = "Failed to find ImageMagick convert app"
            end
        end
        
    until true -- only go through once

    propertyTable.exifToolAppFoundStatus = iif(propertyTable.exifToolAppFound, "Found", "Not-found")
    propertyTable.imageMagickAppFoundStatus = iif(propertyTable.imageMagickAppFound, "Found", "Not-found")
    propertyTable.imageConvertAppFoundStatus = iif(propertyTable.imageConvertAppFound, "Found", "Not-found")

    if message then
        propertyTable.message = message
        propertyTable.hasError = true
        propertyTable.hasNoError = false
        propertyTable.LR_cantExportBecause = message
    else
        propertyTable.message = nil
        propertyTable.hasError = false
        propertyTable.hasNoError = true
        propertyTable.LR_cantExportBecause = nil
    end
    
    --propertyTable.hasError = true -- for debug to avoid creating lots of orphan Exif threads
end

function FaceLabellingExportDialogSections.startDialog( propertyTable )
    propertyTable:addObserver( 'exifToolApp', updateExportStatus )
    propertyTable:addObserver( 'imageMagickApp', updateExportStatus )
    propertyTable:addObserver( 'imageConvertApp', updateExportStatus )
    
    propertyTable:addObserver( 'LR_export_destinationType', updateExportStatus )
    propertyTable:addObserver( 'LR_export_useSubfolder', updateExportStatus )
    propertyTable:addObserver( 'LR_export_destinationPathPrefix', updateExportStatus )
    propertyTable:addObserver( 'LR_export_destinationPathSuffix', updateExportStatus )
    
    updateExportStatus( propertyTable )
end

function FaceLabellingExportDialogSections.sectionsForBottomOfDialog( _, propertyTable )
    local f = LrView.osFactory()
    local bind = LrView.bind
    local share = LrView.share
    
    local result = {
        {
            title = LOC "$$$/FaceLabelling/ExportDialog/FaceLabellingSettings=Face Labelling",
            
            synopsis = bind { key = 'fullPath', object = propertyTable },
            
            f:row {
                f:checkbox {
                        title = LOC "$$$/FaceLabelling/ExportDialog/drawLabelText=Draw label text:",
                        value = bind 'draw_label_text',
                },
                f:checkbox {
                        title = LOC "$$$/FaceLabelling/ExportDialog/drawFaceOutlines=Draw face outlines:",
                        value = bind 'draw_face_outlines',
                },
                f:checkbox {
                        title = LOC "$$$/FaceLabelling/ExportDialog/drawLabelBoxes=Draw label outlines:",
                        value = bind 'draw_label_boxes',
                },
            },
            
            f:separator { fill_horizontal = 1 },
            
            f:row {
                    f:static_text {
                        title = LOC "$$$/FaceLabelling/ExportDialog/ExifToolProg=ExifTool program:",
                        alignment = 'right',
                        width = share 'labelWidth'
                    },
                    
                    f:edit_field {
                        value = bind 'exifToolApp',
                        height_in_lines = 2,
                        width = share 'valueFieldWidth',
                        width_in_chars = 30
                    },
                    
                    f:static_text {
                        title = bind 'exifToolAppFoundStatus',
                        width = share 'statusFieldWidth',
                    },
            },
            
            f:row {
                    f:static_text {
                        title = LOC "$$$/FaceLabelling/ExportDialog/ImageMagickProg=ImageMagick main program:",
                        alignment = 'right',
                        width = share 'labelWidth'
                    },
                    
                    f:edit_field {
                        value = bind 'imageMagickApp',
                        height_in_lines = 2,
                        width = share 'valueFieldWidth'
                    },
                    
                    f:static_text {
                        title = bind 'imageMagickAppFoundStatus',
                        width = share 'statusFieldWidth',
                        width_in_chars = 10
                    },
            },
            
            f:row {
                    f:static_text {
                        title = LOC "$$$/FaceLabelling/ExportDialog/ImageMagickConvertProg=ImageMagick convert program:",
                        alignment = 'right',
                        width = share 'labelWidth'
                    },
                    
                    f:edit_field {
                        value = bind 'imageConvertApp',
                        height_in_lines = 2,
                        width = share 'valueFieldWidth'
                    },
                   
                    f:static_text {
                        title = bind 'imageConvertAppFoundStatus',
                        width = share 'statusFieldWidth',
                    }
            },
            
            f: column {
                place = 'overlapping',
                fill_horizontal = 1,
                
                f:row {
                    f:static_text {
                        title = LOC "$$$/FaceLabelling/ExportDialog/FullPath=Export Path:",
                        alignment = 'right',
                        width = share 'labelWidth',
                        visible = true,
                    },
                    
                    f:static_text {
                        fill_horizontal = 1,
                        width_in_chars = 20,
                        title = bind 'fullPath',
                        visible = true,
                    },
                },
                
                f: row {
                    f:static_text {
                        fill_horizontal = 1,
                        title = bind 'message',
                        visible = bind 'hasError',
                    },
                },
            },

        },
    }
    
    return result
end

FaceLabellingExportDialogSections.exportPresetFields = {
		{ key = 'exifToolApp', default = LrPathUtils.child(_PLUGIN.path, 'ExifTool/exiftool') },
		{ key = 'imageMagickApp', default = "/usr/local/bin/magick" },
		{ key = "imageConvertApp", default = "/usr/local/bin/convert" },
		{ key = "draw_label_text", default = true },
		{ key = "draw_face_outlines", default = false },
		{ key = "draw_label_boxes", default = false },
	}