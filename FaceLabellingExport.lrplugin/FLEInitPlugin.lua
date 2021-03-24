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
-- Local imports
require "Utils.lua"

-- Log export session to file for diagnostics & debug
logger = require("Logger.lua")

--============================================================================--
-- Local variables

-- using prefs rather than exportPresetFields in order to configure
-- from Lightroom Plug-in Manager, before export
local prefs = LrPrefs.prefsForPlugin()


--============================================================================--
-- Preferences for Plug-in Manager dialog
--------------------------------------------------------------------------------
if MAC_ENV then
    default_exiftool_app      = LrPathUtils.child(_PLUGIN.path, 'Mac/ExifTool/exiftool')
    default_imagemagick_app   = "/usr/local/bin/magick"
    default_image_convert_app = "/usr/local/bin/convert"
else
    default_exiftool_app     = LrPathUtils.child(_PLUGIN.path, 'Win/ExifTool/exiftool.exe')
    default_imagemagick_app   = "C:/Program Files/ImageMagick-7.0.10-Q16-HDRI/magick.exe"
    default_image_convert_app = "C:/Program Files/ImageMagick-7.0.10-Q16-HDRI/convert.exe"
end

-- Log export session to file for diagnostics & debug
-- Generally saved to Documents/LrClassicLogs
--prefs.logger_filename    = "FaceLabellingExport"
--prefs.logger_verbosity   = ifnil(prefs.logger_verbosity,   2 ) -- 0 is nothing except errors; 2 is normally sensible; 5 for everything

-- Plug-in web URL
--prefs.FLEUrl = "https://github.com/colin0brass/FaceLabellingExportLrPlugin"

-- Helper apps
--prefs.exifToolApp        = ifnil(prefs.exifToolApp,     default_exiftool_app)
--prefs.imageMagickApp     = ifnil(prefs.imageMagickApp,  default_imagemagick_app)
--prefs.imageConvertApp    = ifnil(prefs.imageConvertApp, default_image_convert_app)

--prefs.exifToolLogFilePath= LrPathUtils.getStandardFilePath("temp")

--============================================================================--
-- Preferences for Plug-in Manager dialog
--------------------------------------------------------------------------------
local temp_dir_path = LrPathUtils.getStandardFilePath("temp")
manager_table = {
    -- Plug-in details
    { key = 'FLEUrl',               default = "https://github.com/colin0brass/FaceLabellingExportLrPlugin", fixed = true },
    
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
	{ key = 'image_width_to_region_ratio_large',  default = 5 },
	
    -- Labelling preferences - labels
	{ key = 'label_auto_optimise', default = true },
	{ key = 'label_outline_colour', default = 'red' },
	{ key = 'face_outline_colour', default = 'blue' },
	{ key = 'label_outline_line_width', default = 1 },
	{ key = 'face_outline_line_width', default = 2 },
	{ key = 'image_margin', default = 5 },
	{ key = 'default_position', default = 'below' },
	{ key = 'default_num_rows', default = 3 },
	{ key = 'default_align', default = 'center' },
	{ key = 'format_experiment_list', default = {'position', 'num_rows', 'font_size'}, fixed = true },
	{ key = 'positions_experiment_list', default = {'below', 'above', 'left', 'right'}, fixed = true },
	{ key = 'num_rows_experiment_list', default = {1, 2, 3, 4}, fixed = true },
	{ key = 'font_size_experiment_list', default = {1, 0.75, 0.5, 0.25}, fixed = true },
	{ key = 'experiment_loop_limit', default = 100, fixed = true},
	
    -- Export thumbnails preferences
	{ key = 'export_thumbnails', default = false },
	{ key = 'thumbnails_filename_option', default = 'RegionNumber' },
	{ key = 'thumbnails_folder_option', default = 'ThumbnailsThumbFolder' },
}

--============================================================================--
-- Initialise prefs from table definitions
--------------------------------------------------------------------------------
-- Plug-in Manager dialog preferences
for i, list_value in pairs(manager_table) do
    if list_value.fixed then -- use this to always initialise to default value
        prefs[list_value.key] = list_value.default
    else -- otherwise give option to preserve previous prefs value if already defined
        prefs[list_value.key] = ifnil(prefs[list_value.key], list_value.default)
    end
end

-- Export dialog preferences
for i, list_value in pairs(preference_table) do
    if list_value.fixed then -- use this to always initialise to default value
        prefs[list_value.key] = list_value.default
    else -- otherwise give option to preserve previous prefs value if already defined
        prefs[list_value.key] = ifnil(prefs[list_value.key], list_value.default)
    end
end

-- Initialise logger
logger.init(prefs.logger_filename, prefs.logger_verbosity) -- arguments: log filename, log_level threshold (lowest is most significant)