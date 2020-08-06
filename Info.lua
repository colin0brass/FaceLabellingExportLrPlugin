--[[----------------------------------------------------------------------------
Info.lua
Summary information for Lightroom face labelling export plugin
--------------------------------------------------------------------------------
Colin Osborne
August 2020
------------------------------------------------------------------------------]]

return {

	LrSdkVersion = 6,
	LrSdkMinimumVersion = 6,

	LrPluginName = "Face Labelling Export",
	LrToolkitIdentifier = 'com.facelabellingexport',
	
	LrExportServiceProvider = {
		title = "Face Labelling Export",
		file = 'FaceLabellingExportService.lua',
	},
	
	VERSION = { major=0, minor=0, revision=0, build=0, },

}