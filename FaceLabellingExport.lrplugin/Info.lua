--[[----------------------------------------------------------------------------
Info.lua
Summary information for Lightroom face labelling export plugin

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

return {

	LrSdkVersion = 6,
	LrSdkMinimumVersion = 6, -- not checked minimum compatible version

	LrPluginName = "Face Labelling Export",
	LrToolkitIdentifier = 'com.facelabellingexport',
	
	LrInitPlugin = "FLEInitPlugin.lua",
	
	LrPluginInfoProvider = 'FLEInfoProvider.lua',

	LrExportServiceProvider = {
		title = "Face Labelling Export",
		file = 'FLEExportServiceProvider.lua',
	},
	
	VERSION = { major=1, minor=4, revision=0, build=0, },

}