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
local LrRecursionGuard  = import 'LrRecursionGuard'

--============================================================================--
-- Local imports
require("Utils.lua")

--============================================================================--
-- Local variables

-- Plugin info, for access to VERSION
local Info              = require("Info.lua")
local versionString = (Info.VERSION.major or '0') .. '.' .. (Info.VERSION.minor or '0')

--local label_experiment_config = {} -- initial value
--local label_experiments_fully_defined = false -- initial value

FLEExportDialogs = {}


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

        if not utils.file_present(propertyTable.exifToolApp) or
                not utils.file_present(propertyTable.imageMagickApp) or
                not utils.file_present(propertyTable.imageConvertApp) then
            message = "Helper apps not fully configured. Please check in Plug-in Manager."
            break
        end
        
        local success, path = getFullPath( propertyTable )
        if success then
            propertyTable.fullPath = path
        else
            message = "Failed to read export path."
        end
        
        if not propertyTable.label_experiments_fully_defined then
            message = "Label format experiments were not fully initialised. Try re-loading plugin, or contact author."
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
local function roundOneDecimalPlace(propertyTable, key, value)
    propertyTable[key] = utils.round(propertyTable[key], 1)
end

--------------------------------------------------------------------------------
-- Observer function to update experiment list and ensure consistent with defaults
function update_experiment_list(propertyTable, key)
    local exp_list = {} -- initial value
    
    logger.writeLog(5, 'update_experiment_list: ' .. tostring(key))
    for exp_key, exp in pairs(propertyTable.label_experiment_config.experiments) do
        exp.is_enabled = propertyTable[exp.dialog_var] -- update status flags
        if exp.is_enabled then
            exp_list[#exp_list+1] = exp.key
        end
    end -- for exp_key, exp

    local e = experiment_definitions.experiment_list
    if e.dialog_string_var~=nil then propertyTable[e.dialog_string_var] = exp_list end
end

--------------------------------------------------------------------------------
-- Observer function to update experiment list and ensure consistent with defaults
function update_experiment_options_list(propertyTable, key)
    logger.writeLog(5, 'update_experiment_options_list: ' .. tostring(key))
    for exp_key, exp in pairs(propertyTable.label_experiment_config.experiments) do
    
        local default = propertyTable[exp.dialog_initial_var]
        
        local exp_opt_list = {} -- initial value
        for opt_key, opt in pairs(exp.options_list) do
            if opt.dialog_var~=nil then
                if opt.key == default then
                    logger.writeLog(5, 'update_experiment_options_list: ensure default option remains set: ' .. tostring(opt.dialog_var))
                    propertyTable[opt.dialog_var] = true -- ensure default option remains set
                end
                opt.is_enabled = propertyTable[opt.dialog_var] -- update status flags
                if opt.is_enabled then
                    exp_opt_list[#exp_opt_list+1] = opt.key
                end -- if opt.key == default
            else
                logger.writeLog(0, "update_experiment_options_list: unable to set for " .. tostring(key))
            end -- if opt.dialog_var~=nil
        end -- for opt_key, opt
        
        if exp.dialog_string_var~=nil then propertyTable[exp.dialog_string_var] = exp_opt_list end
        
    end -- for exp_key, exp
end

local function update_label_defaults(propertyTable, key, value)
    logger.writeLog(5, "update_label_defaults: " .. tostring(key) .. " : " .. tostring(value))
    local found = false -- initial value
    for exp_key, exp in pairs(propertyTable.label_experiment_config.experiments) do
        if exp.dialog_initial_var == key then
            found = true
            local default = propertyTable[exp.dialog_initial_var]
            
            for opt_key, opt in pairs(exp.options_list) do
                if opt.key == default then
                    if opt.dialog_var~=nil then
                        logger.writeLog(5, "setting: " .. tostring(opt.dialog_var))
                        propertyTable[opt.dialog_var] = true
                    else
                        logger.writeLog(0, "update_label_defaults: unable to set default for " .. tostring(key))
                    end -- if opt.dialog_var~=nil
                end -- if opt.key == default
            end -- for opt_key, opt
        end -- if exp.key == key
    end -- for exp_key, exp

    if not found then
        logger.writeLog(0, 'ensure_default_is_set: unknown key: ' .. tostring(key))
    end
    
    update_experiment_options_list(propertyTable, key)
end

--------------------------------------------------------------------------------
-- Reset Export Preset Fields to default values

function resetExportPresetFields( propertyTable )
    logger.writeLog(3, "resetExportPresetFields")
    
    local is_reset = true
    property_table_init_from_prefs(propertyTable, preference_table, prefs, is_reset)
    set_dialog_properties_for_experiment( propertyTable, is_reset )
end

function set_dialog_properties_for_experiment( propertyTable, reset )
    logger.writeLog(5, "set_dialog_properties_for_experiment:")
    reset = utils.ifnil(reset, false)

    local success = true -- initial value

    for exp_key, exp in pairs(propertyTable.label_experiment_config.experiments) do
        if reset then exp.is_enabled = exp.default_enable end
    
        for opt_key, opt in pairs(exp.options_list) do
            if reset then opt.is_enabled = opt.default_enable end
            
            if opt.is_enabled~=nil and opt.dialog_var~=nil then
                logger.writeLog(5, "set_dialog_properties_for_experiment: setting " .. tostring(opt.key) .. " : " .. tostring(opt.dialog_var) .. " to " .. tostring(opt.is_enabled))
                propertyTable[opt.dialog_var] = opt.is_enabled
            else -- not found
                success = false
                logger.writeLog(0, "set_dialog_properties_for_experiment: unknown opt.key: " .. tostring(opt.key))
            end
            
        end -- for opt_key, opt

        if exp.is_enabled~=nil and exp.dialog_var~=nil then
            logger.writeLog(5, "set_dialog_properties_for_experiment: setting " .. tostring(exp.key) .. " : " .. tostring(exp.dialog_var) .. " to " .. tostring(exp.is_enabled))
            propertyTable[exp.dialog_var] = exp.is_enabled
        else -- not found
            success = false
            logger.writeLog(0, "set_dialog_properties_for_experiment: unknown exp.key: " .. tostring(exp.key))
        end
        
    end -- for exp_key, exp
    
    return success
end

function init_experiment_structure( propertyTable )
    logger.writeLog(5, "init_experiment_structure")
    
    local success = true -- initial value
    local found_position = false -- initial value
    local found_num_rows = false -- initial value
    local found_font_size = false -- initial value
    
    propertyTable.label_experiment_config.experiment_list.dialog_var = nil -- not currently used
    propertyTable.label_experiment_config.experiment_list.dialog_string_var = 'format_experiment_list'
    
    for exp_key, exp in pairs(propertyTable.label_experiment_config.experiments) do
        for opt_key, opt in pairs(exp.options_list) do
            if exp.key == 'position' then
                found_position = true
                exp.dialog_var = 'label_position_search'
                exp.dialog_string_var = 'positions_experiment_list'
                exp.dialog_initial_var = 'default_position'
                if     opt.key == 'below' then opt.dialog_var = 'experiment_enable_position_below'
                elseif opt.key == 'above' then opt.dialog_var = 'experiment_enable_position_above'
                elseif opt.key == 'left' then opt.dialog_var = 'experiment_enable_position_left'
                elseif opt.key == 'right' then opt.dialog_var = 'experiment_enable_position_right'
                else opt.dialog_var = nil end
            elseif exp.key == 'num_rows' then
                found_num_rows = true
                exp.dialog_var = 'label_num_rows_search'
                exp.dialog_string_var = 'num_rows_experiment_list'
                exp.dialog_initial_var = 'default_num_rows'
                if     opt.key == 1 then opt.dialog_var = 'experiment_enable_num_rows_1'
                elseif opt.key == 2 then opt.dialog_var = 'experiment_enable_num_rows_2'
                elseif opt.key == 3 then opt.dialog_var = 'experiment_enable_num_rows_3'
                elseif opt.key == 4 then opt.dialog_var = 'experiment_enable_num_rows_4'
                else opt.dialog_var = nil end
            elseif exp.key == 'font_size' then
                found_font_size = true
                exp.dialog_var = 'label_font_size_search'
                exp.dialog_string_var = 'font_size_experiment_list'
                exp.dialog_initial_var = 'default_font_size_multiple'
                if opt.key == 1.0 then opt.dialog_var = 'experiment_enable_font_size_multiple_1'
                elseif opt.key == 0.75 then opt.dialog_var = 'experiment_enable_font_size_multiple_0_75'
                elseif opt.key == 0.5 then opt.dialog_var = 'experiment_enable_font_size_multiple_0_5'
                elseif opt.key == 0.25 then opt.dialog_var = 'experiment_enable_font_size_multiple_0_25'
                else opt.dialog_var = nil end
            else
                logger.writeLog(0, "init_experiment_structure: unknown exp.key: " .. tostring(exp.key))
                success = false
            end -- if exp.key
            
            if opt.dialog_var == nil then
                logger.writeLog(0, "init_experiment_structure: unknown opt.key: " .. tostring(opt.key))
                opt.dialog_var = nil
                success = false
            end -- if opt.key==nil
            
        end -- for opt_key, opt
    end -- for exp_key, exp
    
    success = success and (found_position and found_num_rows and found_font_size)
    
    return success
end

--------------------------------------------------------------------------------
-- start dialog

function FLEExportDialogs.startDialog( propertyTable )
    local prefs = LrPrefs.prefsForPlugin()
    local success = true -- initial value
    
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
    local is_reset = false
    -- first the preferences configured in Plug-in Manager dialog
    property_table_init_from_prefs(propertyTable, manager_table, prefs, is_reset)
    -- then the preferences configured in Export dialog
    property_table_init_from_prefs(propertyTable, preference_table, prefs, is_reset)
    
    -- initialise experiment structure
    propertyTable.label_experiment_config = {} -- initial value
    propertyTable.label_experiments_fully_defined = false -- initial value
    local is_reset = false
    propertyTable.label_experiment_config = build_experiment_definitions(is_reset)

    success = success and init_experiment_structure( propertyTable )
    if not success then logger.writeLog(0, "Failed to initialise experiment structure") end
    success = success and set_dialog_properties_for_experiment( propertyTable )
    if not success then logger.writeLog(0, "Failed to initialise dialog properties for experiments") end
    if success then propertyTable.label_experiments_fully_defined = true end
    
    propertyTable:addObserver( 'label_position_search',  update_experiment_list)
    propertyTable:addObserver( 'label_num_rows_search',  update_experiment_list)
    propertyTable:addObserver( 'label_font_size_search', update_experiment_list)

    propertyTable:addObserver( 'experiment_enable_position_below', update_experiment_options_list)
    propertyTable:addObserver( 'experiment_enable_position_above', update_experiment_options_list)
    propertyTable:addObserver( 'experiment_enable_position_left',  update_experiment_options_list)
    propertyTable:addObserver( 'experiment_enable_position_right', update_experiment_options_list)

    propertyTable:addObserver( 'experiment_enable_num_rows_1', update_experiment_options_list)
    propertyTable:addObserver( 'experiment_enable_num_rows_2', update_experiment_options_list)
    propertyTable:addObserver( 'experiment_enable_num_rows_3', update_experiment_options_list)
    propertyTable:addObserver( 'experiment_enable_num_rows_4', update_experiment_options_list)

    propertyTable:addObserver( 'experiment_enable_font_size_multiple_1',    update_experiment_options_list)
    propertyTable:addObserver( 'experiment_enable_font_size_multiple_0_75', update_experiment_options_list)
    propertyTable:addObserver( 'experiment_enable_font_size_multiple_0_5',  update_experiment_options_list)
    propertyTable:addObserver( 'experiment_enable_font_size_multiple_0_25', update_experiment_options_list)

    propertyTable:addObserver( 'default_position', update_label_defaults )
    propertyTable:addObserver( 'default_num_rows', update_label_defaults )

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
    prefs_update_from_property_table(propertyTable, preference_table, prefs)

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
                fill_horizontal = 1,
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
                fill_horizontal = 1,
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
                fill_horizontal = 1,
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
-- dialog section for export thumbnails

function exportThumbnailsView(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share
    
    result = f:group_box { -- export face thumbnail images
            title = "Export face thumbnail images",
            fill_horizontal = 1,
            f:row { -- config options
                f:checkbox {
                    title = LOC "$$$/FaceLabelling/ExportDialog/thumbnailExportEnable=Export thumbnails",
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
                f:column {
                    f:group_box {
                        title = LOC "$$$/FaceLabelling/ExportDialog/thumbnail_folder=Thumbnail sub-folder",
                        fill_horizontal = 1,
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
                    f:group_box {
                        title = LOC "$$$/FaceLabelling/ExportDialog/thumbnail_options=Thumbnail options",
                        fill_horizontal = 1,
                        f:checkbox {
                            title = LOC "$$$/FaceLabelling/ExportDialog/thumbnailExportIfUnnamed=Export thumbnails if unnamed",
                            tooltip = "Export thumbnails even if they don't have an identified name",
                            value = bind 'export_thumbnails_if_unnamed',
                            enabled = bind 'export_thumbnails', 
                        },
                    }, -- group_box
                }, -- column

            }, -- row
        } -- group_box; export thumbnail images
    
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
    
    result = f:group_box { -- labelling config
        title = "Label format options",
        f:row {
            fill_horizontal = 1,
            
            f:column {
                fill_horizontal = 0.3,
                f:static_text {
                    title = 'Label options:',
                    enabled = bind 'label_image',
                },
            }, -- column
            
            f:column {
                fill_horizontal = 0.3,
                f:group_box { -- Label options
                    title = "Label format options",
                    fill_horizontal = 1,
                    
                    f:static_text {
                        title = 'Face outline line width:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_face_outlines'),
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
                            enabled = LrBinding.andAllKeys( 'label_image', 'draw_face_outlines'),
                        },
                        f:slider {
                            min = 1,
                            max = 10,
                            integral = true,
                            value = bind('face_outline_line_width'),
                            enabled = true,
                            tooltip = 'Face outline line width',
                            place_vertical = 0.5,
                            enabled = LrBinding.andAllKeys( 'label_image', 'draw_face_outlines'),
                        },
                    }, -- row
                    f:static_text {
                        title = 'Face outline colour:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_face_outlines'),
                    },
                    f:popup_menu {
                        items = menu_colour_list,
                        value = bind 'face_outline_colour',
                        tooltip = "Face outline box colour (if enabled)",
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_face_outlines'),
                    },

                    f:static_text {
                        title = 'Label outline line width:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_boxes'),
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
                            enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_boxes'),
                        },
                        f:slider {
                            min = 1,
                            max = 10,
                            integral = true,
                            value = bind('label_outline_line_width'),
                            enabled = true,
                            tooltip = 'Label outline line width',
                            place_vertical = 0.5,
                            enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_boxes'),
                        },
                    }, -- row
                    f:static_text {
                        title = 'Label outline colour:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_boxes'),
                    },
                    f:popup_menu {
                        items = menu_colour_list,
                        value = bind 'label_outline_colour',
                        tooltip = "Label outline box colour (if enabled)",
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_boxes'),
                    },
                    
                    f:static_text {
                        title = 'Image margin:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text' ),
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
                            enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text' ),
                            tooltip = "Image margin, so labels don't go right to the edge",
                        },
                        f:slider {
                            min = 1,
                            max = 100,
                            integral = true,
                            value = bind('image_margin'),
                            enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text' ),
                            tooltip = "Image margin, so labels don't go right to the edge",
                            place_vertical = 0.5,
                        },
                    }, -- row
                }, -- group_box
            }, -- column
            
            f:column {
                f:group_box {
                    title = 'Label options',
                    f:static_text {
                        title = 'Label font line width:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
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
                            enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                            tooltip = 'Label font line width',
                        },
                        f:slider {
                            min = 1,
                            max = 10,
                            integral = true,
                            value = bind('font_line_width'),
                            enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                            tooltip = 'Label font line width',
                            place_vertical = 0.5,
                            width = 50,
                        },
                    }, -- row
                    f:static_text {
                        title = 'Label font colour:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                    },
                    f:popup_menu {
                        items = menu_colour_list,
                        value = bind 'font_colour',
                        place_horizontal = 0.5,
                        tooltip = "Label font colour",
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                    },
                    f:static_text {
                        title = 'Font type:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                    },
                    f:static_text {
                        title = bind 'font_type',
                        place_horizontal = 0.5,
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                    },
                    f:static_text {
                        title = 'Label undercolour:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                    },
                    f:static_text {
                        title = bind 'label_undercolour',
                        place_horizontal = 0.5,
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                    },
                }, -- group_box
            }, -- column
        }, -- row
    } -- group_box; labelling config
        
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
    
    -- expand simple list to list of tuples (title, value) for menu display
    local list = {'below', 'above', 'left', 'right'}
    local menu_positions_list = {}
    for i, list_value in pairs(list) do
        menu_positions_list[i] = {title=list_value, value=list_value}
    end
    
    local menu_experiment_limit_list = {
        { title = "Low", value = 50 },
        { title = "Medium", value = 100 },
        { title = "High", value = 500 },
        { title = "Very High", value = 1000 }
    }
    
    result = f:column { -- labelling config
        f:row {
            f:column {
                fill_horizontal = 0.25,
                f:group_box {
                    title = LOC "$$$/FaceLabelling/ExportDialog/LabelPositionOptions=Label position options",
                    f:radio_button {
                        title = 'Fixed label positions',
                        value = bind 'label_auto_optimise',
                        checked_value = false,
                        tooltip = "Fixed label positions",
                        enabled = bind 'label_image',
                    },
                    f:radio_button {
                        title = 'Dynamic label positions',
                        height_in_lines = 2,
                        value = bind 'label_auto_optimise',
                        checked_value = true,
                        tooltip = "Dynamic label positions",
                        enabled = bind 'label_image',
                    },
                },
    
                f:group_box {
                    title = LOC "$$$/FaceLabelling/ExportDialog/DynamicLabellingSearch=Dynamic labelling search",
                    f:checkbox {
                        title = LOC "$$$/FaceLabelling/ExportDialog/DynamicLabelPosition=Position search",
                        value = bind 'label_position_search',
                        enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise' ),
                    },
                    f:checkbox {
                        title = LOC "$$$/FaceLabelling/ExportDialog/DynamicLabelNumRows=Num rows search",
                        value = bind 'label_num_rows_search',
                        enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise' ),
                    },
                    f:checkbox {
                        title = LOC "$$$/FaceLabelling/ExportDialog/DynamicLabelFontSize=Font size search",
                        value = bind 'label_font_size_search',
                        enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise' ),
                    },
                }, -- group_box
            }, -- column
            
            f:column {
                fill_horizontal = 0.25,
                f:group_box {
                    title = "Label settings or initial values",
                    f:static_text {
                        title = 'Label position:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                    },
                    f:popup_menu {
                        items = menu_positions_list,
                        value = bind 'default_position',
                        tooltip = "Label position (or initial position if dynamic)",
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                        place_horizontal = 0.1,
                    },
                    f:static_text {
                        title = 'Label number of rows:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                    },
                    f:row {
                        f:edit_field {
                            width_in_digits = 1,
                            place_horizontal = 0.1,
                            min = 1,
                            max = 4,
                            precision = 0,
                            increment = 1,
                            value = bind('default_num_rows'),
                            enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                            tooltip = "Number of text lines for label (or initial value if dynamic)",
                        },
                        f:slider {
                            min = 1,
                            max = 4,
                            integral = true,
                            value = bind('default_num_rows'),
                            enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                            tooltip = "Number of text lines for label (or initial value if dynamic)",
                            place_vertical = 0.5,
                            width = 50
                        },
                    }, -- row
                    f:static_text {
                        title = 'Label font size:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                    },
                    f:row {
                        f:edit_field {
                            width_in_digits = 3,
                            place_horizontal = 0.1,
                            min = 1,
                            max = 100,
                            precision = 0,
                            increment = 1,
                            value = bind('label_font_size_fixed'),
                            enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                            tooltip = "Label font size",
                        },
                        f:slider {
                            min = 1,
                            max = 100,
                            integral = true,
                            value = bind('label_font_size_fixed'),
                            enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                            tooltip = "Label font size",
                            place_vertical = 0.5,
                            width = 50
                        },
                    }, -- row
                }, -- group_box
            }, -- column
            
            f:column {
                fill_horizontal = 0.6,
                f:group_box {
                    f:static_text {
                        title = 'Positions to try:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_position_search'),
                    },
                    f:row {
                        f:checkbox {
                            title = 'below',
                            enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_position_search'),
                            value = bind 'experiment_enable_position_below',
                            tooltip = 'try label below image; (default position can not be disabled)',
                        },
                        f:checkbox {
                            title = 'above',
                            enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_position_search'),
                            value = bind 'experiment_enable_position_above',
                            tooltip = 'try label above image; (default position can not be disabled)',
                        },
                        f:checkbox {
                            title = 'left',
                            enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_position_search'),
                            value = bind 'experiment_enable_position_left',
                            tooltip = 'try label left of image; (default position can not be disabled)',
                        },
                        f:checkbox {
                            title = 'right',
                            enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_position_search'),
                            value = bind 'experiment_enable_position_right',
                            tooltip = 'try label right of image; (default position can not be disabled)',
                        },
                    }, -- row
                    f:static_text {
                        title = 'Number of text rows to try:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_num_rows_search'),
                    },
                    f:row {
                        f:checkbox {
                            title = '1',
                            enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_num_rows_search'),
                            value = bind 'experiment_enable_num_rows_1',
                            tooltip = 'try 1 row of text; (default num_rows can not be disabled)',
                        },
                        f:checkbox {
                            title = '2',
                            enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_num_rows_search'),
                            value = bind 'experiment_enable_num_rows_2',
                            tooltip = 'try 2 rows of text; (default num_rows can not be disabled)',
                        },
                        f:checkbox {
                            title = '3',
                            enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_num_rows_search'),
                            value = bind 'experiment_enable_num_rows_3',
                            tooltip = 'try 2 rows of text; (default num_rows can not be disabled)',
                        },
                        f:checkbox {
                            title = '4',
                            enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_num_rows_search'),
                            value = bind 'experiment_enable_num_rows_4',
                            tooltip = 'try 4 rows of text; (default num_rows can not be disabled)',
                        },
                    }, -- row
                    f:static_text {
                        title = 'Font size multiples to try:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_font_size_search'),
                    },
                    f:row {
                        f:checkbox {
                            title = '1',
                            enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_font_size_search'),
                            value = bind 'experiment_enable_font_size_multiple_1',
                        },
                        f:checkbox {
                            title = '0.75',
                            enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_font_size_search'),
                            value = bind 'experiment_enable_font_size_multiple_0_75',
                        },
                        f:checkbox {
                            title = '0.5',
                            enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_font_size_search'),
                            value = bind 'experiment_enable_font_size_multiple_0_5',
                        },
                        f:checkbox {
                            title = '0.25',
                            enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise', 'label_font_size_search'),
                            value = bind 'experiment_enable_font_size_multiple_0_25',
                        },
                    }, -- row
                    f:static_text {
                        title = 'Experiment loop limit:',
                        enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise'),
                    },
                    --f:static_text {
                    --    title = '\t' .. tostring(propertyTable.experiment_loop_limit),
                    --    enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise'),
                    --},
                    f:popup_menu {
                        items = menu_experiment_limit_list,
                        value = bind 'experiment_loop_limit',
                        tooltip = "Safety limit on the number of experiments to try for dynamic labelling",
                        enabled = LrBinding.andAllKeys( 'label_image', 'label_auto_optimise'),
                        place_horizontal = 0.1,
                    },
                }, -- group_box
            }, -- column
        }, -- row
        
    } -- column; labelling config
        
    return result
end
    
--------------------------------------------------------------------------------
-- dialog section for label size options

function exportLabelSettingsView(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share
    
    result = f:row { -- labelling config
        f:column {
            f:group_box {
                title = LOC "$$$/FaceLabelling/ExportDialog/LabelSizeOptions=Label font size",
                f:radio_button {
                    title = 'Fixed font size',
                    value = bind 'label_size_option',
                    checked_value = 'LabelFixedFontSize',
                    tooltip = "Fixed font size",
                    enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                },
                f:radio_button {
                    title = 'Dynamic font size',
                    value = bind 'label_size_option',
                    checked_value = 'LabelDynamicFontSize',
                    tooltip = "Dynamic font size",
                    enabled = LrBinding.andAllKeys( 'label_image', 'draw_label_text'),
                },
            },
        }, -- column
        
        f:column {
            f:group_box {
                title = LOC "$$$/FaceLabelling/ExportDialog/LabelFontSizeDynamic=Desired label width",
                fill_horizontal = 1,
                f:static_text {
                    title = 'For each image, \ncheck face region sizes, \nand choose label font size:',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                },
                fill_horizontal = 1,
                f:static_text {
                    title = 'Desired label width:',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                },
                f:static_text {
                    title = 'For small face regions:',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                },
                f:static_text {
                    title='label width up to',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                    place_horizontal = 0.1,
                },
                f:row {
                    f:edit_field {
                        width_in_digits = 4,
                        place_horizontal = 0.1,
                        min = 0.1,
                        max = 10,
                        precision = 1,
                        increment = 0.1,
                        value = bind('label_width_to_region_ratio_small'),
                        enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                               operation = function(binding, values, fromTable)
                                                   return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                               end },
                        tooltip = 'Desired size of label (as multiple of average region width) for small face regions (e.g. 2x)',
                    },
                    f:slider {
                        min = 0.1,
                        max = 10,
                        integral = false,
                        value = bind('label_width_to_region_ratio_small'),
                        enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                               operation = function(binding, values, fromTable)
                                                   return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                               end },
                        tooltip = 'Desired size of label (as multiple of average region width) for small face regions (e.g. 2x)',
                        place_vertical = 0.5,
                        width = 50,
                    },
                }, -- row
                f:static_text {
                    title = 'x average face region size',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                    place_horizontal = 0.1,
                },
                f:static_text {
                    title = 'For large face regions:',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                },
                f:static_text {
                    title='label width down to',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                    place_horizontal = 0.1,
                },
                f:row {
                    f:edit_field {
                        width_in_digits = 4,
                        place_horizontal = 0.1,
                        min = 0.1,
                        max = 10,
                        precision = 1,
                        increment = 0.1,
                        value = bind('label_width_to_region_ratio_large'),
                        enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                               operation = function(binding, values, fromTable)
                                                   return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                               end },
                        tooltip = 'Desired size of label (as multiple of average region width) for large face regions (e.g. 0.5x)',
                    },
                    f:slider {
                        min = 0.1,
                        max = 10,
                        integral = false,
                        value = bind('label_width_to_region_ratio_large'),
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                        tooltip = 'Desired size of label (as multiple of average region width) for large face regions (e.g. 0.5x)',
                        place_vertical = 0.5,
                        width = 50,
                    },
                }, -- row
                f:static_text {
                    title = 'x average face region size',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                    place_horizontal = 0.1,
                },
                f:static_text {
                    title = 'Linear and clipped within that range',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                },
            }, -- group_box
        }, -- column
        
        f:column {
            f:group_box {
                title = LOC "$$$/FaceLabelling/ExportDialog/LabelFontSizeDynamicRegionDefinition=Region size definitions",
                --show_title = false,
                f:static_text {
                    title = "Where thresholds for \nface region size \nare as follows:",
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                },
                f:static_text {
                    title = 'Small face region:',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                },
                f:static_text {
                    title='if at least',
                    place_horizontal = 0.1,
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                },
                f:row {
                    f:edit_field {
                        width_in_digits = 4,
                        place_horizontal = 0.1,
                        min = 0.5,
                        max = 20,
                        precision = 1,
                        increment = 0.1,
                        value = bind('image_width_to_region_ratio_small'),
                        enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                               operation = function(binding, values, fromTable)
                                                   return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                               end },
                        tooltip = 'Region size (as fraction if image width) that counts as small (as fraction of image size) (e.g. /20)',
                    },
                    f:slider {
                        min = 0.5,
                        max = 20,
                        integral = false,
                        value = bind('image_width_to_region_ratio_small'),
                        enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                               operation = function(binding, values, fromTable)
                                                   return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                               end },
                        tooltip = 'Region size (as fraction if image width) that counts as small (as fraction of image size) (e.g. /20)',
                        place_vertical = 0.5,
                        width = 50,
                    },
                }, -- row
                f:static_text {
                    title = 'regions across image width',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                    place_horizontal = 0.1,
                },
                f:static_text {
                    title = 'Large face region:',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                },
                f:static_text {
                    title='if as few as',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                    place_horizontal = 0.1,
                },
                f:row {
                    f:edit_field {
                        width_in_digits = 3,
                        place_horizontal = 0.1,
                        min = 0.1,
                        max = 5,
                        precision = 1,
                        increment = 0.1,
                        value = bind('image_width_to_region_ratio_large'),
                        enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                               operation = function(binding, values, fromTable)
                                                   return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                               end },
                        tooltip = 'Region size (as fraction if image width) that counts as large (as fraction of image size) (e.g. /5)',
                    },
                    f:slider {
                        min = 0.1,
                        max = 5,
                        integral = false,
                        value = bind('image_width_to_region_ratio_large'),
                        enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                               operation = function(binding, values, fromTable)
                                                   return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                               end },
                        tooltip = 'Region size (as fraction if image width) that counts as large (as fraction of image size) (e.g. /5)',
                        place_vertical = 0.5,
                        width = 50,
                    },
                }, -- row
                f:static_text {
                    title = 'regions across image width',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                    place_horizontal = 0.1,
                },
            }, -- group_box
            f:group_box {
                show_title = false,
                fill_horizontal = 1,
                f:static_text {
                    title = 'Based on test string:',
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                },
                f:static_text {
                    title = bind('test_label'),
                    enabled = LrView.bind { keys = {'label_image', 'label_size_option'}, 
                                           operation = function(binding, values, fromTable)
                                               return values.label_image and (values.label_size_option == 'LabelDynamicFontSize')
                                           end },
                    place_horizontal = 0.1,
                },
            }, -- group_box
        }, -- column
    } -- row; general export configuration options
            
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
-- dialog section for label experiment config summary

function exportLabelExperimentSummaryView(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share
    
    result = f:row {
        f:column {
            f:group_box {
                title = LOC "$$$/FaceLabelling/ExportDialog/DynamicLabellingExperiments=Dynamic labelling experiments",
                f:static_text {
                    title = 'Experiment list:',
                },
                f:static_text {
                    title = LrView.bind { key = 'format_experiment_list',
                        transform = function( value, fromTable )
                            if fromTable then return list_to_text(propertyTable, value) end
                            return LrBinding.kUnsupportedDirection -- to avoid updating the property table
                        end,
                    },
                    place_horizontal = 0.1,
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
                    title = LrView.bind { key = 'positions_experiment_list',
                        transform = function( value, fromTable )
                            if fromTable then return list_to_text(propertyTable, value) end
                            return LrBinding.kUnsupportedDirection -- to avoid updating the property table
                        end,
                    },
                    place_horizontal = 0.1,
                },
                f:static_text {
                    title = 'Num rows:',
                },
                f:static_text {
                    title = LrView.bind { key = 'num_rows_experiment_list',
                        transform = function( value, fromTable )
                            if fromTable then return list_to_text(propertyTable, value) end
                            return LrBinding.kUnsupportedDirection -- to avoid updating the property table
                        end,
                    },
                    place_horizontal = 0.1,
                },
                f:static_text {
                    title = 'Font size (multiples):',
                },
                f:static_text {
                    title = LrView.bind { key = 'font_size_experiment_list',
                        transform = function( value, fromTable )
                            if fromTable then return list_to_text(propertyTable, value) end
                            return LrBinding.kUnsupportedDirection -- to avoid updating the property table
                        end,
                    },
                    place_horizontal = 0.1,
                },
            }, -- group_box
        }, -- column
    } -- row
        
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
                exportThumbnailsView(f, propertyTable),
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
                exportStatusView(f, propertyTable),
                exportLabelExperimentSummaryView(f, propertyTable),
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