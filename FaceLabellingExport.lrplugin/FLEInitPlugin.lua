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

--============================================================================--
-- Local variables

-- using prefs rather than exportPresetFields in order to configure
-- from Lightroom Plug-in Manager, before export
local prefs = LrPrefs.prefsForPlugin()

if MAC_ENV then
    default_exiftool_app      = LrPathUtils.child(_PLUGIN.path, 'Mac/ExifTool/exiftool')
    default_imagemagick_app   = "/usr/local/bin/magick"
    default_image_convert_app = "/usr/local/bin/convert"
else
    default_exiftool_app     = LrPathUtils.child(_PLUGIN.path, 'Win/ExifTool/exiftool.exe')
    default_imagemagick_app   = "C:/Program Files/ImageMagick-7.0.10-Q16-HDRI/magick.exe"
    default_image_convert_app = "C:/Program Files/ImageMagick-7.0.10-Q16-HDRI/convert.exe"
end

local FLEUrl = "https://github.com/colin0brass/FaceLabellingExportLrPlugin"

--============================================================================--
-- Initialise preferences

-- Log export session to file for diagnostics & debug
-- Generally saved to Documents/LrClassicLogs
prefs.logger_filename    = "FaceLabellingExport"
prefs.logger_verbosity   = ifnil(prefs.logger_verbosity,   2 ) -- 0 is nothing except errors; 2 is normally sensible; 5 for everything

-- Plug-in web URL
prefs.FLEUrl = FLEUrl

-- Helper apps
prefs.exifToolApp        = ifnil(prefs.exifToolApp,     default_exiftool_app)
prefs.imageMagickApp     = ifnil(prefs.imageMagickApp,  default_imagemagick_app)
prefs.imageConvertApp    = ifnil(prefs.imageConvertApp, default_image_convert_app)

-- Export preferences to copy into ExportParams
prefs.label_image        = ifnil(prefs.label_image,         true )
prefs.draw_label_text    = ifnil(prefs.draw_label_text,     true )
prefs.draw_face_outlines = ifnil(prefs.draw_face_outlines,  false)
prefs.draw_label_boxes   = ifnil(prefs.draw_label_boxes,    false)
-- Obfuscation preferences to copy into ExportParams
prefs.obfuscate_labels   = ifnil(prefs.obfuscate_labels,    false)
prefs.obfuscate_image    = ifnil(prefs.obfuscate_image,     false)
prefs.remove_exif        = ifnil(prefs.remove_exif,         false)
-- Crop preferences to copy into ExportParams
prefs.crop_image         = ifnil(prefs.crop_image,          false)
-- Export thumbnails
prefs.export_thumbnails  = ifnil(prefs.export_thumbnails,   false)
prefs.thumbnails_filename_option = ifnil(prefs.thumbnails_filename_option, 'RegionNumber')
prefs.thumbnails_folder_option = ifnil(prefs.thumbnails_folder_option, 'ThumbnailsThumbFolder')

-- Preferences; not currently copied into ExportParams since not edited through UI
-- Label preferences; not yet configurable through UI
if MAC_ENV then -- unfortunately not all same fonts available on Mac & Win
    prefs.font_type                 = 'Courier'
else -- windows
    prefs.font_type                 = 'Courier-New'
end
prefs.font_colour               = 'white'
prefs.font_line_width           = 1
prefs.default_position          = 'below'
prefs.default_num_rows          = 3
prefs.default_align             = 'center'
-- Line drawing preferences; not yet configurable through UI
prefs.label_outline_colour      = 'red'
prefs.label_outline_line_width  = 1
prefs.face_outline_colour       = 'blue'
prefs.face_outline_line_width   = 2
-- Image handling preferences; not yet configurable through UI
prefs.image_margin              = 5 -- don't let labels go right to the edge of the image
-- Label size preferences; not yet configurable through UI
prefs.image_width_to_region_ratio_small = 20 -- to determine label text size for small images
prefs.image_width_to_region_ratio_large = 5 -- and larger images
prefs.label_width_to_region_ratio_small = 2 -- ratio of label width to region width for small regions
prefs.label_width_to_region_ratio_large = 0.5 -- and for larger regions
prefs.test_label                        = 'Test Label' -- used to determine label font size
