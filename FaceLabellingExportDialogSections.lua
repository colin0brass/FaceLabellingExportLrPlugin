--[[----------------------------------------------------------------------------
FaceLabellingExportDialogSections.lua
Export dialog customization for Lightroom face labelling export plugin

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
local LrView = import('LrView')
local LrPathUtils = import("LrPathUtils")
local LrFileUtils 		= import 'LrFileUtils'

--============================================================================--
-- Local variables

FaceLabellingExportDialogSections = {}

if MAC_ENV then
    default_exiftool_app      = LrPathUtils.child(_PLUGIN.path, 'Mac/ExifTool/exiftool')
    default_imagemagick_app   = "/usr/local/bin/magick"
    default_image_convert_app = "/usr/local/bin/convert"
else
    default_exiftool_path     = "Please enter proper app location here"
    default_imagemagick_app   = "Please enter proper app location here"
    default_image_convert_app = "Please enter proper app location here"
end

--============================================================================--
-- Functions

--------------------------------------------------------------------------------
-- Get full export path

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

--------------------------------------------------------------------------------
-- Update export status

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
end

--------------------------------------------------------------------------------
-- start dialog

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

--------------------------------------------------------------------------------
-- sections for bottom of dialog

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
                        visible = bind 'hasNoError',
                    },
                    
                    f:static_text {
                        fill_horizontal = 1,
                        width_in_chars = 20,
                        title = bind 'fullPath',
                        visible = bind 'hasNoError',
                    },
                },
                
                f: row {
                    f:static_text {
                        title = 'Error:',
                        alignment = 'right',
                        width = share 'labelWidth',
                        visible = bind 'hasError',
                    },
                    
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

--------------------------------------------------------------------------------
-- Create export preset fields for persistent storage between sessions

FaceLabellingExportDialogSections.exportPresetFields = {
		{ key = 'exifToolApp',        default = default_exiftool_app},
		{ key = 'imageMagickApp',     default = default_imagemagick_app },
		{ key = "imageConvertApp",    default = default_image_convert_app },
		{ key = "draw_label_text",    default = true },
		{ key = "draw_face_outlines", default = false },
		{ key = "draw_label_boxes",   default = false },
	}