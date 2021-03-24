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
local LrBinding         = import("LrBinding")

--============================================================================--
-- Local imports
require("Utils.lua")

--============================================================================--
-- Local variables

-- Plugin info, for access to VERSION
local Info              = require("Info.lua")
local versionString = (Info.VERSION.major or '0') .. '.' .. (Info.VERSION.minor or '0')

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
-- Check sliders for desired label width for large vs small face regions
-- and ensure ratio settings never cross-over
-- so ratio for small images is never smaller than ratio for large images and vice versa
local function coupleSliders_ratioSmallAdjusted( propertyTable )
    if propertyTable.label_width_to_region_ratio_small < propertyTable.label_width_to_region_ratio_large then
        propertyTable.label_width_to_region_ratio_large = propertyTable.label_width_to_region_ratio_small
    end
end
local function coupleSliders_ratioLargeAdjusted( propertyTable )
    if propertyTable.label_width_to_region_ratio_large > propertyTable.label_width_to_region_ratio_small then
        propertyTable.label_width_to_region_ratio_small = propertyTable.label_width_to_region_ratio_large
    end
end

--------------------------------------------------------------------------------
-- Check sliders for thresholds for large vs small face region definitions
-- and ensure ratio settings never cross-over
-- so ratio for small regions is never smaller than ratio for large regions and vice versa
local function coupleSliders_regionSmallAdjusted( propertyTable )
    if propertyTable.image_width_to_region_ratio_small < propertyTable.image_width_to_region_ratio_large then
        propertyTable.image_width_to_region_ratio_large = propertyTable.image_width_to_region_ratio_small
    end
end
local function coupleSliders_regionLargeAdjusted( propertyTable )
    if propertyTable.image_width_to_region_ratio_large > propertyTable.image_width_to_region_ratio_small then
        propertyTable.image_width_to_region_ratio_small = propertyTable.image_width_to_region_ratio_large
    end
end

--------------------------------------------------------------------------------
-- Observer function to round slider value to specified number of decimal places
local function roundOneDecimalPlace(properties, key, value)
    properties[key] = round(properties[key], 1)
end

--------------------------------------------------------------------------------
-- Reset Export Preset Fields to default values

function resetExportPresetFields( propertyTable )
    logger.writeLog(3, "resetExportPresetFields")
    for i, list_value in pairs(preference_table) do
        propertyTable[list_value.key] = list_value.default
        logger.writeLog(4, list_value.key .. ' reset to ' .. tostring(list_value.default))
    end
end

--------------------------------------------------------------------------------
-- start dialog

function FLEExportDialogs.startDialog( propertyTable )
    local prefs = LrPrefs.prefsForPlugin()
    
    logger.writeLog(0, "Plugin name: " .. Info.LrPluginName)
    logger.writeLog(0, "Plugin version: " .. versionString)
    logger.writeLog(0, "Logging level: " .. tostring(logger.get_log_level()))

    -- Plug-in Manager configuration
    -- copy preferences from configuration in Lightroom Plug-in Manager
    -- Helper apps
    propertyTable.exifToolApp       = prefs.exifToolApp
    propertyTable.imageMagickApp    = prefs.imageMagickApp
    propertyTable.imageConvertApp   = prefs.imageConvertApp
    
    -- using prefs rather than exportPresetFields in order to configure
    -- from Lightroom Plug-in Manager, before export
    -- first the preferences configured in Plug-in Manager dialog
    for i, list_value in pairs(manager_table) do
        propertyTable[list_value.key] = prefs[list_value.key]
    end
    -- then the preferences configured in Export dialog
    for i, list_value in pairs(preference_table) do
        propertyTable[list_value.key] = prefs[list_value.key]
    end
    
    propertyTable:addObserver( 'LR_export_destinationType', updateExportStatus )
    propertyTable:addObserver( 'LR_export_useSubfolder', updateExportStatus )
    propertyTable:addObserver( 'LR_export_destinationPathPrefix', updateExportStatus )
    propertyTable:addObserver( 'LR_export_destinationPathSuffix', updateExportStatus )
    
    propertyTable:addObserver( 'helperAppsPresent', updateExportStatus )
    
    -- couple sliders to ensure relationship between values
     propertyTable:addObserver( 'label_width_to_region_ratio_small', coupleSliders_ratioSmallAdjusted )
     propertyTable:addObserver( 'label_width_to_region_ratio_large', coupleSliders_ratioLargeAdjusted )
     propertyTable:addObserver( 'image_width_to_region_ratio_small', coupleSliders_regionSmallAdjusted )
     propertyTable:addObserver( 'image_width_to_region_ratio_large', coupleSliders_regionLargeAdjusted )

     -- limit precision on slider values
     propertyTable:addObserver( 'label_width_to_region_ratio_small', roundOneDecimalPlace )
     propertyTable:addObserver( 'label_width_to_region_ratio_large', roundOneDecimalPlace )
     propertyTable:addObserver( 'image_width_to_region_ratio_small', roundOneDecimalPlace )
     propertyTable:addObserver( 'image_width_to_region_ratio_large', roundOneDecimalPlace )

     updateExportStatus( propertyTable )
end

--------------------------------------------------------------------------------
-- end dialog

function FLEExportDialogs.endDialog( propertyTable )
    local prefs = LrPrefs.prefsForPlugin()
    
    -- using prefs rather than exportPresetFields in order to configure
    -- from Lightroom Plug-in Manager, before export
    for i, list_value in pairs(preference_table) do
        prefs[list_value.key] = propertyTable[list_value.key]
    end

end

--------------------------------------------------------------------------------
-- sections for top of dialog
function FLEExportDialogs.sectionsForTopOfDialog( f, propertyTable )
end

--------------------------------------------------------------------------------
-- dialog section for export labeled image config

function exportLabeledImageView(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share
    
    result = f:group_box { -- export labeled image
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
                        value = bind 'crop_image',
                        enabled = bind 'label_image', -- functionality not yet implemented
                },
            }, -- group_box
        }, -- row; general export configuration options
    } -- group_box; export labeled image
        
    return result
end

--------------------------------------------------------------------------------
-- dialog section for export labeled image labelling config

function exportLabellingView(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share
    
    -- expand simple list to list of tuples (title, value) for menu display
    local list = { 'white', 'black', 'blue', 'red', 'green', 'grey' }
    local menu_colour_list = {}
    for i, list_value in pairs(list) do
        menu_colour_list[i] = {title=list_value, value=list_value}
    end
    
    local list = {'below', 'above', 'left', 'right'}
    local menu_positions_list = {}
    for i, list_value in pairs(list) do
        menu_positions_list[i] = {title=list_value, value=list_value}
    end
    
    --local list = {'center', 'left', 'right'}
    --local menu_align_list = {}
    --for i, list_value in pairs(list) do
    --    menu_align_list[i] = {title=list_value, value=list_value}
    --end
 
    result = f:row { -- labelling config
        f:column {
            f:group_box {
                title = LOC "$$$/FaceLabelling/ExportDialog/LabelPositionOptions=Label position options",
                f:radio_button {
                    title = 'Fixed label positions',
                    value = bind 'label_auto_optimise',
                    checked_value = false,
                    tooltip = "Fixed font size",
                },
                f:radio_button {
                    title = 'Dynamic label positions',
                    height_in_lines = 2,
                    value = bind 'label_auto_optimise',
                    checked_value = true,
                    tooltip = "Dynamic label positions",
                },
            },
        }, -- column
        f:column {
            f:group_box { -- Label options
                title = "Label options",
                f:column {
                    f:static_text {
                        title = 'Label outline line width:',
                    },
                    f:row {
                        f:edit_field {
                            width_in_digits = 2,
                            place_horizontal = 0.5,
                            min = 1,
                            max = 10,
                            precision = 0,
                            increment = 1,
                            value = bind('label_outline_line_width'),
                            enabled = true,
                            tooltip = 'Label outline line width',
                        },
                        f:slider {
                            min = 1,
                            max = 10,
                            integral = true,
                            value = bind('label_outline_line_width'),
                            enabled = true,
                            tooltip = 'Label outline line width',
                            place_vertical = 0.5,
                        },
                    }, -- row
                    f:static_text {
                        title = 'Face outline line width:',
                    },
                    f:row {
                        f:edit_field {
                            width_in_digits = 2,
                            place_horizontal = 0.5,
                            min = 1,
                            max = 10,
                            precision = 0,
                            increment = 1,
                            value = bind('face_outline_line_width'),
                            enabled = true,
                            tooltip = 'Face outline line width',
                        },
                        f:slider {
                            min = 1,
                            max = 10,
                            integral = true,
                            value = bind('face_outline_line_width'),
                            enabled = true,
                            tooltip = 'Face outline line width',
                            place_vertical = 0.5,
                        },
                    }, -- row
                    f:static_text {
                        title = 'Face outline colour:',
                    },
                    f:popup_menu {
                        items = menu_colour_list,
                        value = bind 'face_outline_colour',
                        tooltip = "Face outline box colour (if enabled)",
                        enabled = bind 'draw_face_outlines',
                    },
                    f:static_text {
                        title = 'Label outline colour:',
                    },
                    f:popup_menu {
                        items = menu_colour_list,
                        value = bind 'label_outline_colour',
                        tooltip = "Label outline box colour (if enabled)",
                        enabled = bind 'draw_label_boxes',
                    },
                }, -- column
            }, -- group_box
        }, -- column
        f:column {
            f:group_box { -- Label options
                title = "Label settings (or initial values if dynamic)",
                f:column {
                    f:static_text {
                        title = 'Label position:',
                    },
                    f:popup_menu {
                        items = menu_positions_list,
                        value = bind 'default_position',
                        tooltip = "Label position (or initial position if dynamic)",
                        enabled = bind 'draw_label_text',
                    },
                    --f:static_text {
                    --    title = 'Label alignment:',
                    --},
                    --f:popup_menu {
                    --    items = menu_align_list,
                    --    value = bind 'default_align',
                    --    tooltip = "Label alignment (or initial alignment if dynamic)",
                    --    enabled = bind 'draw_label_text',
                    --},
                    f:static_text {
                        title = 'Label number of rows:',
                    },
                    f:row {
                        f:edit_field {
                            width_in_digits = 1,
                            place_horizontal = 0.5,
                            min = 1,
                            max = 4,
                            precision = 0,
                            increment = 1,
                            value = bind('default_num_rows'),
                            enabled = bind('draw_label_text'),
                            tooltip = "Number of text lines for label (or initial value if dynamic)",
                        },
                        f:slider {
                            min = 1,
                            max = 4,
                            integral = true,
                            value = bind('default_num_rows'),
                            enabled = bind('draw_label_text'),
                            tooltip = "Number of text lines for label (or initial value if dynamic)",
                            place_vertical = 0.5,
                        },
                    }, -- row
                }, -- column
            }, -- group_box
            f:group_box { -- Label options
                show_title = false,
                f:static_text {
                    title = 'Image margin:',
                },
                f:row {
                    f:edit_field {
                        width_in_digits = 3,
                        place_horizontal = 0.5,
                        min = 1,
                        max = 100,
                        precision = 0,
                        increment = 1,
                        value = bind('image_margin'),
                        enabled = bind('label_auto_optimise'),
                        tooltip = "Image margin, so labels don't go right to the edge",
                    },
                    f:slider {
                        min = 1,
                        max = 100,
                        integral = true,
                        value = bind('image_margin'),
                        enabled = bind('label_auto_optimise'),
                        tooltip = "Image margin, so labels don't go right to the edge",
                        place_vertical = 0.5,
                    },
                }, -- row
            }, -- group_box
        }, -- column
    } -- row; labelling config
        
    return result
end

function list_to_text(propertyTable, list)
    local string = '' -- initial value
    for i, entry in pairs(list) do
        if i ~= 1 then string = string .. ', ' end
        string = string .. tostring(entry)
    end
    return string
end

--------------------------------------------------------------------------------
-- dialog section for dynamic label options

function exportDynamicLabellingView(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share
    
    result = f:row { -- labelling config
        f:column {
            f:group_box {
                title = LOC "$$$/FaceLabelling/ExportDialog/DynamicLabellingExperiments=Dynamic labelling experiments",
                f:static_text {
                    title = 'Experiment list:',
                },
                f:static_text {
                    title = '\t' .. list_to_text(propertyTable, propertyTable.format_experiment_list),
                },
                f:static_text {
                    title = 'Experiment loop limit:',
                },
                f:static_text {
                    title = '\t' .. tostring(propertyTable.experiment_loop_limit),
                },
            }, -- group_box
        }, -- column
        f:column {
            f:group_box {
                title = LOC "$$$/FaceLabelling/ExportDialog/ExperimentOptions=Experiment options",
                f:static_text {
                    title = 'Positions:',
                },
                f:static_text {
                    title = '\t' .. list_to_text(propertyTable, propertyTable.positions_experiment_list),
                },
                f:static_text {
                    title = 'Num rows:',
                },
                f:static_text {
                    title = '\t' .. list_to_text(propertyTable, propertyTable.num_rows_experiment_list),
                },
                f:static_text {
                    title = 'Font size (multiples):',
                },
                f:static_text {
                    title = '\t' .. list_to_text(propertyTable, propertyTable.font_size_experiment_list),
                },
            }, -- group_box
        }, -- column
    } -- row; labelling config
        
    return result
end
    
--------------------------------------------------------------------------------
-- dialog section for label size options

function exportLabelSettingsView(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share
    
    -- expand simple list to list of tuples (title, value) for menu display
    local list = { 'white', 'black', 'blue', 'red', 'green', 'grey' }
    local menu_colour_list = {}
    for i, list_value in pairs(list) do
        menu_colour_list[i] = {title=list_value, value=list_value}
    end
    
    result = f:row { -- labelling config
        f:column {
            f:group_box {
                title = LOC "$$$/FaceLabelling/ExportDialog/LabelSizeOptions=Label size options",
                f:radio_button {
                    title = 'Fixed font size',
                    value = bind 'label_size_option',
                    checked_value = 'LabelFixedFontSize',
                    tooltip = "Fixed font size",
                },
                f:radio_button {
                    title = 'Dynamic font size',
                    value = bind 'label_size_option',
                    checked_value = 'LabelDynamicFontSize',
                    tooltip = "Dynamic font size",
                },
            },
            f:group_box {
                show_title = false,
                f:static_text {
                    title = 'Label font size (if fixed):',
                },
                f:row {
                    f:edit_field {
                        width_in_digits = 3,
                        place_horizontal = 0.5,
                        min = 1,
                        max = 100,
                        precision = 0,
                        increment = 1,
                        value = bind('label_font_size_fixed'),
                        enabled = LrBinding.keyEquals('label_size_option', 'LabelFixedFontSize'),
                        tooltip = "Label font size (if fixed)",
                    },
                    f:slider {
                        min = 1,
                        max = 100,
                        integral = true,
                        value = bind('label_font_size_fixed'),
                        enabled = LrBinding.keyEquals('label_size_option', 'LabelFixedFontSize'),
                        tooltip = "Label font size (if fixed)",
                        place_vertical = 0.5,
                    },
                }, -- row
                f:static_text {
                    title = 'Label font line width:',
                },
                f:row {
                    f:edit_field {
                        width_in_digits = 2,
                        place_horizontal = 0.5,
                        min = 1,
                        max = 10,
                        precision = 0,
                        increment = 1,
                        value = bind('font_line_width'),
                        enabled = true,
                        tooltip = 'Label font line width',
                    },
                    f:slider {
                        min = 1,
                        max = 10,
                        integral = true,
                        value = bind('font_line_width'),
                        enabled = true,
                        tooltip = 'Label font line width',
                        place_vertical = 0.5,
                    },
                }, -- row
                f:static_text {
                    title = 'Label font colour:',
                },
                f:popup_menu {
                    items = menu_colour_list,
                    value = bind 'font_colour',
                    tooltip = "Label font colour",
                    enabled = bind 'draw_label_text',
                },
                f:static_text {
                    title = 'Font type:',
                },
                f:static_text {
                    title = bind 'font_type',
                },
                f:static_text {
                    title = 'Label undercolour:',
                },
                f:static_text {
                    title = bind 'label_undercolour',
                },
            }, -- group_box
        }, -- column
        f:column {
            f:group_box {
                title = LOC "$$$/FaceLabelling/ExportDialog/LabelFontSizeDynamic=Label dynamic font size options",
                f:static_text {
                    title = 'For each image, check face region sizes, \nand choose label font size',
                },
            }, -- group_box
            f:group_box {
                show_title = false,
                f:static_text {
                    title = 'Desired label width:',
                },
                f:static_text {
                    title = 'For small face regions:',
                },
                f:static_text {
                    title='\tlabel width up to',
                },
                f:row {
                    f:edit_field {
                        width_in_digits = 4,
                        place_horizontal = 0.5,
                        min = 0.1,
                        max = 10,
                        precision = 1,
                        increment = 0.1,
                        value = bind('label_width_to_region_ratio_small'),
                        enabled = LrBinding.keyEquals('label_size_option', 'LabelDynamicFontSize'),
                        tooltip = 'Desired size of label (as multiple of average region width) for small face regions (e.g. 2x)',
                    },
                    f:slider {
                        min = 0.1,
                        max = 10,
                        integral = false,
                        value = bind('label_width_to_region_ratio_small'),
                        enabled = LrBinding.keyEquals('label_size_option', 'LabelDynamicFontSize'),
                        tooltip = 'Desired size of label (as multiple of average region width) for small face regions (e.g. 2x)',
                        place_vertical = 0.5,
                    },
                }, -- row
                f:static_text {
                    title = '\tx average face region size',
                },
                f:static_text {
                    title = 'For large face regions:',
                },
                f:static_text {
                    title='\tlabel width down to',
                },
                f:row {
                    f:edit_field {
                        width_in_digits = 4,
                        place_horizontal = 0.5,
                        min = 0.1,
                        max = 10,
                        precision = 1,
                        increment = 0.1,
                        value = bind('label_width_to_region_ratio_large'),
                        enabled = LrBinding.keyEquals('label_size_option', 'LabelDynamicFontSize'),
                        tooltip = 'Desired size of label (as multiple of average region width) for large face regions (e.g. 0.5x)',
                    },
                    f:slider {
                        min = 0.1,
                        max = 10,
                        integral = false,
                        value = bind('label_width_to_region_ratio_large'),
                        enabled = LrBinding.keyEquals('label_size_option', 'LabelDynamicFontSize'),
                        tooltip = 'Desired size of label (as multiple of average region width) for large face regions (e.g. 0.5x)',
                        place_vertical = 0.5,
                    },
                }, -- row
                f:static_text {
                    title = '\tx average face region size',
                },
                f:static_text {
                    title = 'Linear and clipped within that range',
                },
            }, -- group_box
            f:group_box {
                --title = LOC "$$$/FaceLabelling/ExportDialog/LabelFontSizeDynamic=Dynamic font size",
                show_title = false,
                f:static_text {
                    title = "Where thresholds for face region size is as follows:",
                },
                f:static_text {
                    title = 'Small face region:',
                },
                f:static_text {
                    title='\tif at least',
                },
                f:row {
                    f:edit_field {
                        width_in_digits = 4,
                        place_horizontal = 0.5,
                        min = 0.5,
                        max = 20,
                        precision = 1,
                        increment = 0.1,
                        value = bind('image_width_to_region_ratio_small'),
                        enabled = LrBinding.keyEquals('label_size_option', 'LabelDynamicFontSize'),
                        tooltip = 'Region size (as fraction if image width) that counts as small (as fraction of image size) (e.g. /20)',
                    },
                    f:slider {
                        min = 0.5,
                        max = 20,
                        integral = false,
                        value = bind('image_width_to_region_ratio_small'),
                        enabled = LrBinding.keyEquals('label_size_option', 'LabelDynamicFontSize'),
                        tooltip = 'Region size (as fraction if image width) that counts as small (as fraction of image size) (e.g. /20)',
                        place_vertical = 0.5,
                    },
                }, -- row
                f:static_text {
                    title = '\tregions across image width',
                },
                f:static_text {
                    title = 'Large face region:',
                },
                f:static_text {
                    title='\tif as few as',
                },
                f:row {
                    f:edit_field {
                        width_in_digits = 3,
                        place_horizontal = 0.5,
                        min = 0.1,
                        max = 5,
                        precision = 1,
                        increment = 0.1,
                        value = bind('image_width_to_region_ratio_large'),
                        enabled = LrBinding.keyEquals('label_size_option', 'LabelDynamicFontSize'),
                        tooltip = 'Region size (as fraction if image width) that counts as large (as fraction of image size) (e.g. /5)',
                    },
                    f:slider {
                        min = 0.1,
                        max = 5,
                        integral = false,
                        value = bind('image_width_to_region_ratio_large'),
                        enabled = LrBinding.keyEquals('label_size_option', 'LabelDynamicFontSize'),
                        tooltip = 'Region size (as fraction if image width) that counts as large (as fraction of image size) (e.g. /5)',
                        place_vertical = 0.5,
                    },
                }, -- row
                f:static_text {
                    title = '\tregions across image width',
                },
            }, -- group_box
            f:group_box {
                show_title = false,
                f:static_text {
                    title = 'Based on label font-sizing test string:',
                },
                f:static_text {
                    title = bind('test_label'),
                },
            }, -- group_box
        }, -- column
    } -- row; general export configuration options
            
    return result
end

--------------------------------------------------------------------------------
-- dialog section for export thumbnails

function exportThumbnailsView(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share
    
    result = f:group_box { -- export thumbnail images
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
        } -- group_box; export thumbnail images
    
    return result
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
            title = LOC "$$$/FaceLabelling/ExportDialog/FaceLabellingSettings=Face Labeling Options",
            
            synopsis = bind { key = 'fullPath', object = propertyTable },
            
            bind_to_object = propertyTable,
            
            f:separator { fill_horizontal = 1 },
            f:view {
                fill_horizontal = 1,
                exportLabeledImageView(f, propertyTable),
            }, -- view
            
            f:separator { fill_horizontal = 1 },
            f:view {
                fill_horizontal = 1,
                exportLabellingView(f, propertyTable),
            }, -- view
            
            f:separator { fill_horizontal = 1 },
            f:view {
                fill_horizontal = 1,
                exportDynamicLabellingView(f, propertyTable),
            }, -- view
            
            f:separator { fill_horizontal = 1 },
            f:view {
                fill_horizontal = 1,
                exportLabelSettingsView(f, propertyTable),
            }, -- view
            
            f:separator { fill_horizontal = 1 },
            f:view {
                fill_horizontal = 1,
                exportThumbnailsView(f, propertyTable),
            }, -- view
            
            f:separator { fill_horizontal = 1 },
            f:view {
                fill_horizontal = 1,
                exportStatusView(f, propertyTable),
            }, -- view
            
            f:push_button {
                title = 'Reset to default settings',
                action = function()
                    resetExportPresetFields(propertyTable)
                end,
            },

        }, -- structure within result
    } -- result
    
    return result
end