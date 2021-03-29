--[[----------------------------------------------------------------------------
FLEInitPlugin.lua
Plug-in initialisation for Lightroom face labelling export plugin

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
local LrPathUtils        = import("LrPathUtils")
local LrPrefs            = import("LrPrefs")

--============================================================================--
-- Imports
utils = require "Utils.lua"

-- Log export session to file for diagnostics & debug
logger = require("Logger.lua")

--require "strict"

--============================================================================--
-- Local variables

-- using prefs rather than exportPresetFields in order to configure
-- from Lightroom Plug-in Manager, before export
local prefs = LrPrefs.prefsForPlugin()

--============================================================================--
-- Preferences for Plug-in Manager dialog
--------------------------------------------------------------------------------

plugin_url = "https://github.com/colin0brass/FaceLabellingExportLrPlugin"
exiftool_url = "https://exiftool.org"
imagemagick_url = "https://imagemagick.org"

if MAC_ENV then
    default_exiftool_app      = LrPathUtils.child(_PLUGIN.path, 'Mac/ExifTool/exiftool')
    default_imagemagick_app   = "/usr/local/bin/magick"
    default_image_convert_app = "/usr/local/bin/convert"
else
    default_exiftool_app     = LrPathUtils.child(_PLUGIN.path, 'Win/ExifTool/exiftool.exe')
    default_imagemagick_app   = "C:/Program Files/ImageMagick-7.0.10-Q16-HDRI/magick.exe"
    default_image_convert_app = "C:/Program Files/ImageMagick-7.0.10-Q16-HDRI/convert.exe"
end

--============================================================================--
-- Preferences for Plug-in Manager dialog
--------------------------------------------------------------------------------
local temp_dir_path = LrPathUtils.getStandardFilePath("temp")
manager_table = {
    -- Plug-in details
    { key = 'FLEUrl',               default = plugin_url, fixed = true },
    
    -- Helper apps
    { key = 'exifToolApp',          default = default_exiftool_app },
    { key = 'imageMagickApp',       default = default_imagemagick_app },
    { key = 'imageConvertApp',      default = default_image_convert_app },
    
    -- Plug-in logs
    { key = 'logger_filename',      default = "FaceLabellingExport", fixed = true },
    { key = 'logger_verbosity',     default = 2 },
    
    -- ExifTool logs
    { key = 'exifLogFilePath',      default = temp_dir_path, fixed = true },
    { key = 'exifToolLogDelete',    default = true },
    
    -- ImageMagick Logs
    { key = 'imageMagickLogFilePath', default = temp_dir_path, fixed = true },
    { key = 'imageMagickLogDelete',   default = true },
}

--============================================================================--
-- Preferences for Export dialog
--------------------------------------------------------------------------------
preference_table = {
    -- Export preferences
	{ key = 'label_image', 	        default = true },
	{ key = 'draw_label_text', 	    default = true },
	{ key = 'draw_face_outlines', 	default = false },
	{ key = 'draw_label_boxes', 	default = false },
	{ key = 'crop_image', 	        default = true },

    -- Obfuscation preferences
    { key = 'obfuscate_labels', 	default = false },
	{ key = 'obfuscate_image', 	    default = false },
	{ key = 'remove_exif', 	        default = true },
	
    -- Labelling preferences - font
    { key = 'font_type', 	                      default = MAC_ENV and 'Courier' or 'Courier-New' },
	{ key = 'label_size_option', 	              default = 'LabelDynamicFontSize' },
	{ key = 'label_font_size_fixed', 	          default = 60 },
	{ key = 'font_colour', 	                      default = 'white' },
	{ key = 'label_undercolour',                  default = '#00000080' },
	{ key = 'font_line_width', 	                  default = 1 },
	{ key = 'test_label', 	                      default = 'Test Label' }, -- used to determine label font size
	{ key = 'label_width_to_region_ratio_small',  default = 1.5 },
	{ key = 'label_width_to_region_ratio_large',  default = 0.5 },
	{ key = 'image_width_to_region_ratio_small',  default = 20 },
	{ key = 'image_width_to_region_ratio_large',  default = 1 },
	
    -- Labelling preferences - labels
	{ key = 'label_auto_optimise', default = true },
	{ key = 'label_outline_colour', default = 'red' },
	{ key = 'face_outline_colour', default = 'blue' },
	{ key = 'label_outline_line_width', default = 1 },
	{ key = 'face_outline_line_width', default = 2 },
	{ key = 'image_margin', default = 5 },
	{ key = 'default_position', default = 'below' },
	{ key = 'default_num_rows', default = 3 },
	{ key = 'default_font_size_multiple', default = 1},
	{ key = 'default_align', default = 'center' },
	{ key = 'label_position_search', default = true },
	{ key = 'label_num_rows_search', default = true },
	{ key = 'label_font_size_search', default = true },
	{ key = 'format_experiment_list', default = nil },
	{ key = 'positions_experiment_list', default = nil },
	{ key = 'num_rows_experiment_list', default = nil },
	{ key = 'font_size_experiment_list', default = nil },
	{ key = 'experiment_loop_limit', default = 200, fixed = false},
	
    -- Export thumbnails preferences
	{ key = 'export_thumbnails', default = false },
	{ key = 'export_thumbnails_if_unnamed', default = false },
	{ key = 'thumbnails_filename_option', default = 'RegionNumber' },
	{ key = 'thumbnails_folder_option', default = 'ThumbnailsThumbFolder' },
}

experiment_definitions = {
    experiment_list = {
        list_value = {}, -- initial value
        prefs_var = 'format_experiment_list',
        dialog_var = nil, -- initial value
    },
    experiments = {
        {
            key = 'position',
            dialog_initial_var = nil, -- initial value
            list_value = {}, -- initial value
            is_enabled = nil, -- initial value
            default_enable = true,
            prefs_var = 'positions_experiment_list',
            dialog_var = nil, -- initial value
            options_list = {
                { key = 'below', default_enable = true, is_enabled = nil, dialog_var = nil },
                { key = 'above', default_enable = true, is_enabled = nil, dialog_var = nil },
                { key = 'left',  default_enable = true, is_enabled = nil, dialog_var = nil },
                { key = 'right', default_enable = true, is_enabled = nil, dialog_var = nil },
            },
        },
        {
            key = 'num_rows',
            dialog_initial_var = nil, -- initial value
            list_value = {}, -- initial value
            is_enabled = nil, -- initial value
            default_enable = true,
            prefs_var = 'num_rows_experiment_list',
            dialog_var = nil, -- initial value
            options_list = {
                { key = 1, default_enable = true, is_enabled = nil, dialog_var = nil },
                { key = 2, default_enable = true, is_enabled = nil, dialog_var = nil },
                { key = 3, default_enable = true, is_enabled = nil, dialog_var = nil },
                { key = 4, default_enable = true, is_enabled = nil, dialog_var = nil },
            },
        },
        {
            key = 'font_size',
            dialog_initial_var = nil, -- initial value
            list_value = {}, -- initial value
            is_enabled = nil, -- initial value
            default_enable = true,
            prefs_var = 'font_size_experiment_list',
            dialog_var = nil, -- initial value
            options_list = {
                { key = 1.0,  default_enable = true, is_enabled = nil, dialog_var = nil },
                { key = 0.75, default_enable = true, is_enabled = nil, dialog_var = nil },
                { key = 0.5,  default_enable = true, is_enabled = nil, dialog_var = nil },
                { key = 0.25, default_enable = true, is_enabled = nil, dialog_var = nil },
            },
        },
    },
}

function is_value_in_list(list, value)
    local is_found = false -- initial value
    if type(list)=='table' then
        for k, v in pairs(list) do
            if v == value then is_found = true end
        end
    end
    return is_found
end

function build_experiment_definitions(reset)
    reset = utils.ifnil(reset, false)
    
    logger.writeLog(5, "build_experiment_definitions: reset=" .. tostring(reset))
    
    local exp_list = {} -- initial value
    for exp_key, exp in pairs(experiment_definitions.experiments) do

        -- build experiment list from options
        local exp_opt_list = {} -- initial value
        if exp.options_list then
            for opt_key, opt in pairs(exp.options_list) do
                if reset or (prefs[exp.prefs_var]==nil) then
                    logger.writeLog(5, "build_experiment_definitions: reset " .. tostring(opt.key) .. " : " .. tostring(opt.default_enable))
                    opt.is_enabled = opt.default_enable
                else -- if reset
                    logger.writeLog(5, "build_experiment_definitions: restoring " .. tostring(opt.key) .. " : " .. tostring(opt.is_enabled))
                    opt.is_enabled = is_value_in_list(prefs[exp.prefs_var], opt.key)
                end
                if opt.is_enabled then exp_opt_list[#exp_opt_list+1] = opt.key end
            end -- for opt_key, opt
        end -- if exp.options_list

        if reset or (prefs[exp.prefs_var]==nil) then
            logger.writeLog(5, "build_experiment_definitions: reset " .. tostring(exp.key) .. " : " .. tostring(exp.default_enable))
            exp.is_enabled = exp.default_enable
        else -- if reset; else
            exp.is_enabled = is_value_in_list(prefs[experiment_definitions.experiment_list.prefs_var], exp.key)
            logger.writeLog(5, "build_experiment_definitions: restoring " .. tostring(exp.key) .. " : " .. tostring(exp.is_enabled))
        end -- if reset; else
        
        -- update individual experiment list & prefs
        exp.list_value = exp_opt_list -- update experiment list
        if exp.prefs_var and exp.list_value then
            prefs[exp.prefs_var] = exp.list_value -- update preferences experiment list
        end
        
        -- update overall experiment list
        if exp.is_enabled then exp_list[#exp_list+1] = exp.key end
        
    end -- for exp_key, exp
    
    -- update list & prefs
    experiment_definitions.experiment_list.list_value = exp_list
    if experiment_definitions.experiment_list.prefs_var and experiment_definitions.experiment_list.list_value then
        prefs[experiment_definitions.experiment_list.prefs_var] = experiment_definitions.experiment_list.list_value
    end
    
    return experiment_definitions
end

--============================================================================--
-- Initialise prefs from table definitions
--------------------------------------------------------------------------------

function prefs_init(prefs, prefs_definition, reset)
    logger.writeLog(5, "prefs_init:")
    reset = utils.ifnil(reset, false)
    for i, list_value in pairs(prefs_definition) do
        if ( list_value.fixed or (reset and (list_value.default~=nil)) ) then
            logger.writeLog(4, list_value.key .. ' reset to ' .. tostring(list_value.default))
            prefs[list_value.key] = list_value.default
        end -- if
    end -- for i, list_value
end

function prefs_update_from_property_table(propertyTable, prefs_definition, prefs)
    logger.writeLog(5, "prefs_update_from_property_table:")
    for i, list_value in pairs(prefs_definition) do
        logger.writeLog(4, tostring(list_value.key) .. ' saving as ' .. tostring(propertyTable[list_value.key]))
        prefs[list_value.key] = propertyTable[list_value.key]
    end -- for i, list_value
end


function property_table_init_from_prefs(propertyTable, prefs_definition, prefs, reset)
    reset = utils.ifnil(reset, false)
    logger.writeLog(5, "property_table_init_from_prefs: starting; reset=" .. tostring(reset))
    for i, list_value in pairs(prefs_definition) do
        if reset then
            if (list_value.default~=nil) then
                propertyTable[list_value.key] = utils.table_copy(list_value.default)
                --prefs[list_value.key] = list_value.default -- for some reason this stops the function working
                logger.writeLog(4, tostring(list_value.key) .. ' reset to ' .. tostring(list_value.default))
            end
        elseif prefs[list_value.key]~=nil then
            logger.writeLog(4, tostring(list_value.key) .. ' set to ' .. tostring(prefs[list_value.key]))
            propertyTable[list_value.key] = utils.table_copy(prefs[list_value.key])
        else
            logger.writeLog(5, 'nothing to copy for: ' .. tostring(list_value.key))
        end
    end
end

prefs_init(prefs, manager_table)

-- Initialise logger (after preferences from manager_table)
logger.init(prefs.logger_filename, prefs.logger_verbosity) -- arguments: log filename, log_level threshold (lowest is most significant)

prefs_init(prefs, preference_table)
