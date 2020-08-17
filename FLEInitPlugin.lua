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
    default_exiftool_path     = LrPathUtils.child(_PLUGIN.path, 'Win/ExifTool/exiftool.exe')
    default_imagemagick_app   = "Please enter proper app location here"
    default_image_convert_app = "Please enter proper app location here"
end

--============================================================================--
-- Initialise preferences

-- exiftool app
if not prefs.exifToolApp then
    prefs.exifToolApp = default_exiftool_app
end

--ImageMagick main program
if not prefs.imageMagickApp then
    prefs.imageMagickApp = default_imagemagick_app
end

--ImageMagick convert app
if not prefs.imageConvertApp then
    prefs.imageConvertApp = default_image_convert_app
end

if not prefs.draw_label_text then
    prefs.draw_label_text = true
end

if not prefs.draw_face_outlines then
    prefs.draw_face_outlines = false
end

if not draw_label_boxes then
    prefs.draw_label_boxes = false
end