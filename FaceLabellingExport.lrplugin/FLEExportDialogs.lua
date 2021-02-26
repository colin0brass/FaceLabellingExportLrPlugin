--[[----------------------------------------------------------------------------
FLEExportDialogs.lua
Dialog customization for Lightroom face labelling export plugin

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
local LrFileUtils       = import("LrFileUtils")
local LrPathUtils       = import("LrPathUtils")
local LrPrefs           = import("LrPrefs")
local LrView            = import("LrView")

--============================================================================--
-- Local imports
require("Utils.lua")

--============================================================================--
-- Local variables

FLEExportDialogs = {}

exiftool_url = "https://exiftool.org"
imagemagick_url = "https://imagemagick.org"

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

        if not file_present(propertyTable.exifToolApp) or
                not file_present(propertyTable.imageMagickApp) or
                not file_present(propertyTable.imageConvertApp) then
            message = "Helper apps not fully configured. Please check in Plug-in Manager."
            break
        end
        
        local success, path = getFullPath( propertyTable )
        if success then
            propertyTable.fullPath = path
        else
            message = "Failed to read export path."
        end
        
    until true -- only go through once

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

function FLEExportDialogs.startDialog( propertyTable )
    local prefs = LrPrefs.prefsForPlugin()
    
    -- Plug-in Manager configuration
    -- copy preferences from configuration in Lightroom Plug-in Manager
    -- Helper apps
    propertyTable.exifToolApp       = prefs.exifToolApp
    propertyTable.imageMagickApp    = prefs.imageMagickApp
    propertyTable.imageConvertApp   = prefs.imageConvertApp
    
    -- Export preferences
    propertyTable.label_image       = prefs.label_image
    propertyTable.draw_label_text   = prefs.draw_label_text
    propertyTable.draw_face_outlines= prefs.draw_face_outlines
    propertyTable.draw_label_boxes  = prefs.draw_label_boxes
    propertyTable.crop_image        = prefs.crop_image
    
    -- Obfuscation preferences
    propertyTable.obfuscate_labels   = prefs.obfuscate_labels
    propertyTable.obfuscate_image    = prefs.obfuscate_image
    propertyTable.remove_exif        = prefs.remove_exif
  
    -- Export thumbnails preferences
    propertyTable.export_thumbnails  = prefs.export_thumbnails
    propertyTable.thumbnails_filename_option = prefs.thumbnails_filename_option
    propertyTable.thumbnails_folder_option = prefs.thumbnails_folder_option

    propertyTable:addObserver( 'LR_export_destinationType', updateExportStatus )
    propertyTable:addObserver( 'LR_export_useSubfolder', updateExportStatus )
    propertyTable:addObserver( 'LR_export_destinationPathPrefix', updateExportStatus )
    propertyTable:addObserver( 'LR_export_destinationPathSuffix', updateExportStatus )
    
    propertyTable:addObserver( 'helperAppsPresent', updateExportStatus )

    updateExportStatus( propertyTable )
end

--------------------------------------------------------------------------------
-- end dialog

function FLEExportDialogs.endDialog( propertyTable )
    local prefs = LrPrefs.prefsForPlugin()
    
    -- Export preferences
    -- copy any updated preferences back for persistent storage
    prefs.label_image           = propertyTable.label_image
    prefs.draw_label_text       = propertyTable.draw_label_text
    prefs.draw_face_outlines    = propertyTable.draw_face_outlines
    prefs.draw_label_boxes      = propertyTable.draw_label_boxes
    prefs.crop_image            = propertyTable.crop_image
    -- Obfuscation preferences
    prefs.obfuscate_labels      = propertyTable.obfuscate_labels
    prefs.obfuscate_image       = propertyTable.obfuscate_image
    prefs.remove_exif           = propertyTable.remove_exif
    -- Export thumbnails preferences
    prefs.export_thumbnails     = propertyTable.export_thumbnails
    prefs.thumbnails_filename_option = propertyTable.thumbnails_filename_option
    prefs.thumbnails_folder_option = propertyTable.thumbnails_folder_option
    
end

--------------------------------------------------------------------------------
-- sections for top of dialog
function FLEExportDialogs.sectionsForTopOfDialog( f, propertyTable )
end

--------------------------------------------------------------------------------
-- dialog section for export status

function exportStatusView(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share
    
    result = f:group_box {
        title = "Export Status",
        fill_horizontal = 1,
        
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
            }, -- row
            
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
            }, -- row
        }, -- column
    }
    
    return result    
end

--------------------------------------------------------------------------------
-- sections for bottom of dialog

function FLEExportDialogs.sectionsForBottomOfDialog( f, propertyTable )
    local bind = LrView.bind
    local share = LrView.share
    
    local result = {
        {
            title = LOC "$$$/FaceLabelling/ExportDialog/FaceLabellingSettings=Face Labelling Options",
            
            synopsis = bind { key = 'fullPath', object = propertyTable },
            
            bind_to_object = propertyTable,
            
            f:group_box { -- export labeled image
                title = "Export labeled image",
                fill_horizontal = 1,
                
                f:row { -- general export configuration options
                    f:checkbox {
                        title = LOC "$$$/FaceLabelling/ExportDialog/ImageLabel=Label image",
                        value = bind 'label_image',
                    },
                    f:group_box {
                        title = LOC "$$$/FaceLabelling/ExportDialog/ImageLabelOptions=Image labeling options",
                        f:checkbox {
                                title = LOC "$$$/FaceLabelling/ExportDialog/ImageLabelText=Draw label text",
                                value = bind 'draw_label_text',
                                enabled = bind 'label_image',
                        },
                        f:checkbox {
                                title = LOC "$$$/FaceLabelling/ExportDialog/ImageLabelFaceOutlines=Draw face outlines",
                                value = bind 'draw_face_outlines',
                                enabled = bind 'label_image',
                        },
                        f:checkbox {
                                title = LOC "$$$/FaceLabelling/ExportDialog/ImageLabelBoxes=Draw label outlines",
                                value = bind 'draw_label_boxes',
                                enabled = bind 'label_image',
                        },
                    }, -- group_box
                    f:group_box {
                        title = LOC "$$$/FaceLabelling/ExportDialog/ImageFilenameOptions=Obfuscation options",
                        f:checkbox {
                                title = LOC "$$$/FaceLabelling/ExportDialog/obfuscate_labels=Obfuscate labels",
                                tooltip = "Randomise characters and digits in labels",
                                value = bind 'obfuscate_labels',
                                enabled = bind 'label_image',
                        },
                        f:checkbox {
                                title = LOC "$$$/FaceLabelling/ExportDialog/obfuscate_image=Obfuscate image",
                                tooltip = "Fade output image",
                                value = bind 'obfuscate_image',
                        },
                        f:checkbox {
                                title = LOC "$$$/FaceLabelling/ExportDialog/remove_exif=Remove exif",
                                tooltip = "Remove exif metadata",
                                value = bind 'remove_exif',
                        },
                    }, -- group_box
                    f:group_box {
                        title = LOC "$$$/FaceLabelling/ExportDialog/ImageOptions=Image options",
                        f:checkbox {
                                title = LOC "$$$/FaceLabelling/ExportDialog/ImageCrop=Apply crop",
                                tooltip = "Apply crop (if present) as per EXIF",
                                value = false, -- bind 'crop_image',
                                enabled = false, -- bind 'label_image', -- functionality not yet implemented
                        },
                    }, -- group_box
                }, -- row
            }, -- group_box
            
            f:group_box { -- export thumbnail images
                title = "Export thumbnail images",
                fill_horizontal = 1,
                f:row { -- config options
                    f:checkbox {
                        title = LOC "$$$/FaceLabelling/ExportDialog/drawLabelText=Export thumbnail images",
                            value = bind 'export_thumbnails',
                    },
                    f:group_box {
                        title = LOC "$$$/FaceLabelling/ExportDialog/thumbnailFilenameOptions=Thumbnail filename options",
                        f:radio_button {
                            title = 'Region name' ,
                            value = bind 'thumbnails_filename_option',
                            checked_value = 'RegionName',
                            enabled = bind 'export_thumbnails',
                        },
                        f:radio_button {
                            title = 'Filename + region number' ,
                            value = bind 'thumbnails_filename_option',
                            checked_value = 'RegionNumber',
                            enabled = bind 'export_thumbnails',
                        },
                        f:radio_button {
                            title = 'Filename uniquified' ,
                            value = bind 'thumbnails_filename_option',
                            checked_value = 'FileUnique',
                            enabled = bind 'export_thumbnails',
                        },
                    }, -- group_box
                    f:group_box {
                        title = LOC "$$$/FaceLabelling/ExportDialog/thumbnail_folder=Thumbnail sub-folder",
                        f:radio_button {
                            title = 'thumb sub-folder' ,
                            value = bind 'thumbnails_folder_option',
                            checked_value = 'ThumbnailsThumbFolder',
                            enabled = bind 'export_thumbnails',
                        },
                        f:radio_button {
                            title = 'no sub-folder' ,
                            value = bind 'thumbnails_folder_option',
                            checked_value = 'ThumbnailsNoFolder',
                            enabled = bind 'export_thumbnails',
                        },
                    }, -- group_box
                }, -- row
            }, -- group_box
            
            f:separator { fill_horizontal = 1 },
            f:view {
                fill_horizontal = 1,
                exportStatusView(f, propertyTable),
            }, -- view

        }, -- structure within result
    } -- result
    
    return result
end