--[[----------------------------------------------------------------------------
FLEInfoProvider.lua
Plugin info service provider for Lightroom face labelling export plugin

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
local LrDialogs         = import("LrDialogs")
local LrFileUtils       = import("LrFileUtils")
local LrHttp            = import("LrHttp")
local LrPrefs           = import("LrPrefs")
local LrView            = import("LrView")
local LrShell           = import("LrShell")

--============================================================================--
-- Local imports
require("Utils.lua")

--============================================================================--
-- Local variables

local FLEInfoProvider = {}

--============================================================================--
-- Functions

--------------------------------------------------------------------------------
-- Reset Export Preset Fields to default values

function resetPluginManagerPresetFields( propertyTable )
    logger.writeLog(3, "resetExportPresetFields")
    for i, list_value in pairs(manager_table) do
        propertyTable[list_value.key] = list_value.default
        logger.writeLog(4, list_value.key .. ' reset to ' .. tostring(list_value.default))
    end
end

--------------------------------------------------------------------------------
-- Update export status

local function updatePluginStatus( propertyTable )
    local message = nil
    
    repeat -- only goes through once, but using this as easy way to 'break' out

        if not file_present(propertyTable.exifToolApp) then
            message = "Failed to find ExifTool app"
            propertyTable.exifToolAppFoundStatus = "Not-Found"
        else
            propertyTable.exifToolAppFoundStatus = "Found"
        end
        
        if not file_present(propertyTable.imageMagickApp) then
            message = "Failed to find ImageMagick main app"
            propertyTable.imageMagickAppFoundStatus = "Not-Found"
        else
            propertyTable.imageMagickAppFoundStatus = "Found"
        end
        
        if not file_present(propertyTable.imageConvertApp) then
            message = "Failed to find ImageMagick convert app"
            propertyTable.imageConvertAppFoundStatus = "Not-Found"
        else
            propertyTable.imageConvertAppFoundStatus = "Found"
        end
        
    until true -- only go through once
    
    -- Update from latest properties
    logger.set_log_level(propertyTable.logger_verbosity)
        
    if message then
        propertyTable.message = message
        propertyTable.hasError = true
        propertyTable.hasNoError = false
        propertyTable.LR_cantExportBecause = message
        propertyTable.synopsis = "Settings not yet complete."
    else
        propertyTable.message = nil
        propertyTable.hasError = false
        propertyTable.hasNoError = true
        propertyTable.LR_cantExportBecause = nil
        propertyTable.synopsis = "Settings configured."
    end
    
end

--------------------------------------------------------------------------------
-- start dialog

function FLEInfoProvider.startDialog( propertyTable )
    local prefs = LrPrefs.prefsForPlugin()
    
    -- copy preferences
    -- using prefs rather than exportPresetFields in order to configure
    -- from Lightroom Plug-in Manager, before export
    for i, list_value in pairs(manager_table) do
        propertyTable[list_value.key] = prefs[list_value.key]
    end

    -- copy log file path for use in dialog
    propertyTable.logFilePath         = logger.logFilePath
    
    propertyTable:addObserver( 'exifToolApp',           updatePluginStatus )
    propertyTable:addObserver( 'imageMagickApp',        updatePluginStatus )
    propertyTable:addObserver( 'imageConvertApp',       updatePluginStatus )
    propertyTable:addObserver( 'logger_verbosity',      updatePluginStatus )
    propertyTable:addObserver( 'exifToolLogDelete',     updatePluginStatus )
    propertyTable:addObserver( 'imageMagickLogDelete',  updatePluginStatus )
    
    updatePluginStatus( propertyTable )
end
--------------------------------------------------------------------------------
-- end dialog

function FLEInfoProvider.endDialog( propertyTable )
    local prefs = LrPrefs.prefsForPlugin()

    -- copy any updated preferences back for persistent storage
    -- using prefs rather than exportPresetFields in order to configure
    -- from Lightroom Plug-in Manager, before export
    for i, list_value in pairs(manager_table) do
        prefs[list_value.key] = propertyTable[list_value.key]
    end

end

--------------------------------------------------------------------------------
-- dialog view for helper app configuration

function helperAppConfigView(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share
    
    result = f:group_box {
        title = "Helper apps",
        fill_horizontal = 1,
        
        f:row { -- ExifTool app check
            f:static_text {
                title = LOC "$$$/FaceLabelling/PluginDialog/ExifToolProg=ExifTool program:",
                alignment = 'right',
                width = share 'labelWidth',
            },
            
            f:edit_field {
                value = bind 'exifToolApp',
                height_in_lines = 2,
                width = share 'valueFieldWidth',
                width_in_chars = 30,
            },
            
            f:static_text {
                title = bind 'exifToolAppFoundStatus',
                width = share 'statusFieldWidth',
            },
        }, -- row
        
        f:row { -- ExifTool helper buttons
             f:static_text { -- spacing
                 width = share 'labelWidth',
             },
             f:push_button { -- set default
                title = LOC "$$$/FaceLabelling/PluginDialog/AppDefault=Default",
                tooltip = LOC "$$$/FaceLabelling/PluginDialog/AppDefaultTip=Set back to default value",
                alignment = 'center',
                fill_horizontal = 0,
                action = function() propertyTable.exifToolApp = default_exiftool_app end,
            },
            f:push_button { -- go to provider's website
                title = LOC "$$$/FaceLabelling/PluginDialog/AppDownload=Open app website",
                tooltip = LOC "$$$/FaceLabelling/PluginDialog/AppDownloadTip=Open app provider's website",
                alignment = 'center',
                fill_horizontal = 0,
                action = function() LrHttp.openUrlInBrowser(exiftool_url) end,
            },
            f:push_button { -- Show in file browser
                title = "Show file",
                tooltip = LOC "Show file",
                alignment = 'center',
                fill_horizontal = 0,
                action = function() LrShell.revealInShell(propertyTable.exifToolApp) end,
            },
        }, -- row
        
        f:row { -- ImageMagick main program
            f:static_text {
                title = LOC "$$$/FaceLabelling/PluginDialog/ImageMagickProg=ImageMagick main program:",
                alignment = 'right',
                width = share 'labelWidth',
            },
            
            f:edit_field {
                value = bind 'imageMagickApp',
                height_in_lines = 2,
                width = share 'valueFieldWidth',
            },
            
            f:static_text {
                title = bind 'imageMagickAppFoundStatus',
                width = share 'statusFieldWidth',
                width_in_chars = 10,
            },
        }, -- row
        
        f:row { -- ImageMagick main program helper buttons
             f:static_text { -- spacing
                 width = share 'labelWidth',
             },
             f:push_button { -- set default
                title = LOC "$$$/FaceLabelling/PluginDialog/AppDefault=Default",
                tooltip = LOC "$$$/FaceLabelling/PluginDialog/AppDefaultTip=Set back to default value",
                alignment = 'center',
                fill_horizontal = 0,
                action = function() propertyTable.imageMagickApp = default_imagemagick_app end,
            },
            f:push_button { -- go to provider's website
                title = LOC "$$$/FaceLabelling/PluginDialog/AppDownload=Open app website",
                tooltip = LOC "$$$/FaceLabelling/PluginDialog/AppDownloadTip=Open app provider's website",
                alignment = 'center',
                fill_horizontal = 0,
                action = function() LrHttp.openUrlInBrowser(imagemagick_url) end,
            },
            f:push_button { -- Show in file browser
                title = "Show file",
                tooltip = LOC "Show file",
                alignment = 'center',
                fill_horizontal = 0,
                action = function() LrShell.revealInShell(propertyTable.imageMagickApp) end,
            },
        }, -- row
        
        f:row { -- ImageMagick convert
            f:static_text {
                title = LOC "$$$/FaceLabelling/PluginDialog/ImageMagickConvertProg=ImageMagick convert program:",
                alignment = 'right',
                width = share 'labelWidth',
            },
            
            f:edit_field {
                value = bind 'imageConvertApp',
                height_in_lines = 2,
                width = share 'valueFieldWidth',
            },
           
            f:static_text {
                title = bind 'imageConvertAppFoundStatus',
                width = share 'statusFieldWidth',
            },
        }, -- row
        
        f:row { -- ImageMagick convert program helper buttons
             f:static_text { -- spacing
                 width = share 'labelWidth',
             },
             f:push_button { -- set default
                title = LOC "$$$/FaceLabelling/PluginDialog/AppDefault=Default",
                tooltip = LOC "$$$/FaceLabelling/PluginDialog/AppDefaultTip=Set back to default value",
                alignment = 'center',
                fill_horizontal = 0,
                action = function() propertyTable.imageConvertApp = default_image_convert_app end,
            },
            f:push_button { -- go to provider's website
                title = LOC "$$$/FaceLabelling/PluginDialog/AppDownload=Open app website",
                tooltip = LOC "$$$/FaceLabelling/PluginDialog/AppDownloadTip=Open app provider's website",
                alignment = 'center',
                fill_horizontal = 0,
                action = function() LrHttp.openUrlInBrowser(imagemagick_url) end,
            },
            f:push_button { -- Show in file browser
                title = "Show file",
                tooltip = LOC "Show file",
                alignment = 'center',
                fill_horizontal = 0,
                action = function() LrShell.revealInShell(propertyTable.imageConvertApp) end,
            },
        }, -- row
        
    } -- f:group_box
    
    return result
end

--------------------------------------------------------------------------------
-- dialog view for log files status

function logFilesView(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share
    
    result = f:group_box {
        title = "Log files",
        fill_horizontal = 1,
        
        f:row { -- Plug-in log file information
            title = LOC "$$$/FaceLabelling/PluginDialog/LogFileOptions=Plugin log file options",
            f:static_text {
                title = LOC "$$$/FaceLabelling/PluginDialog/LogFile=Plug-in log file:",
                alignment = 'left',
                width = share 'labelWidth'
            }, -- static_text
            
            f:static_text {
                title = bind 'logFilePath',
                height_in_lines = 2,
                width = share 'valueFieldWidth',
                width_in_chars = 30,
            }, -- static_text
        }, -- row
        f: row { -- Plug-in log file options
             f:static_text { -- spacing
                 width = share 'labelWidth',
             }, -- static_text
            f:push_button { -- Show in file browser
                title = "Show file",
                tooltip = LOC "Show file",
                alignment = 'center',
                fill_horizontal = 0,
                action = function() LrShell.revealInShell(logger.logFilePath) end,
            }, -- push_button
            f:static_text {
                title = "Log level:",
            }, -- static_text
            f:popup_menu {
                tooltip = LOC "$$$/FaceLabelling/PluginDialog/LogLevelTip=The level of log details",
                items   = {
                    { title	= LOC "Nothing",    value = 0 },
                    { title	= LOC "Errors",     value = 1 },
                    { title	= LOC "Normal",     value = 2 },
                    { title	= LOC "Trace",      value = 3 },
                    { title	= LOC "Debug",      value = 4 },
                    { title	= LOC "X-Debug",    value = 5 },
                },
                fill_horizontal = 0,
                value = bind 'logger_verbosity',
            }, -- popup_menu
        }, -- row
        
        f:row { -- ExifTool log file information
            title = LOC "$$$/FaceLabelling/PluginDialog/ExifToolLogFileOptions=ExifTool log options",
            f:static_text {
                title = LOC "$$$/FaceLabelling/PluginDialog/ExifToolLogFile=ExifTool log path:",
                alignment = 'left',
                width = share 'labelWidth'
            }, -- static_text
            
            f:static_text {
                title = bind 'exifLogFilePath',
                height_in_lines = 2,
                width = share 'valueFieldWidth',
                width_in_chars = 30,
            }, -- static_text
        }, -- row
        f: row { -- ExifTool log file options
             f:static_text { -- spacing
                 width = share 'labelWidth',
             }, -- static_text
            f:push_button { -- Show in file browser
                title = "Show folder",
                tooltip = LOC "Show folder",
                alignment = 'center',
                fill_horizontal = 0,
                action = function() LrShell.revealInShell(propertyTable.exifLogFilePath) end,
            }, -- push_button
            f:checkbox {
                title = LOC "$$$/FaceLabelling/PluginDialog/ExifToolDeleteLogs=Delete logs after export",
                value = bind 'exifToolLogDelete',
            }, -- checkbox
        }, -- row
        
        f:row { -- ImageMagick log file information
            title = LOC "$$$/FaceLabelling/PluginDialog/ImageMagickLogFileOptions=ImageMagick log options",
            f:static_text {
                title = LOC "$$$/FaceLabelling/PluginDialog/ImageMagickLogFile=ImageMagick log path:",
                alignment = 'left',
                width = share 'labelWidth'
            }, -- static_text
            
            f:static_text {
                title = bind 'imageMagickLogFilePath',
                height_in_lines = 2,
                width = share 'valueFieldWidth',
                width_in_chars = 30,
            }, -- static_text
        }, -- row
        f: row { -- ImageMagick log file options
             f:static_text { -- spacing
                 width = share 'labelWidth',
             }, -- static_text
            f:push_button { -- Show in file browser
                title = "Show folder",
                tooltip = LOC "Show folder",
                alignment = 'center',
                fill_horizontal = 0,
                action = function() LrShell.revealInShell(propertyTable.imageMagickLogFilePath) end,
            }, -- push_button
            f:checkbox {
                title = LOC "$$$/FaceLabelling/PluginDialog/ImageMagickDeleteLogs=Delete logs after export",
                value = bind 'imageMagickLogDelete',
            }, -- checkbox
        }, -- row
 
        f:push_button {
            title = 'Reset to default settings',
            action = function()
                resetPluginManagerPresetFields(propertyTable)
            end,
        }, -- push_button

    } -- result, group_box
    
    return result    
end

--------------------------------------------------------------------------------
-- dialog view for config status

function configStatusView(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share
    
    result = f:group_box {
        title = "Config Status",
        fill_horizontal = 1,
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
    } -- result, group_box
    
    return result    
end

--------------------------------------------------------------------------------
-- sections for top of dialog
function FLEInfoProvider.sectionsForTopOfDialog(f, propertyTable )
    local prefs = LrPrefs.prefsForPlugin()
    local bind = LrView.bind
    
    local result = {
        {
            title = LOC "$$$/FaceLabelling/PluginDialog/Header=FaceLabellingExport",
            
            bind_to_object = propertyTable,
            
            f:row {
                f:static_text {
                    title = LOC "$$$/FaceLabelling/PluginDialog/Header/Online=Click here to open plug-in home-page on GitHub, e.g. to check for updates",
                    tooltip = "Click to open in browser",
                    alignment = "left",
                    mouse_down = function()
                        LrHttp.openUrlInBrowser(prefs.FLEUrl)
                    end,
                }, -- f:static_text
            }, -- f:row
        }
    } -- result
    
    return result
end

function FLEInfoProvider.sectionsForBottomOfDialog(f, propertyTable )
    local bind = LrView.bind
    
    local result = {
        {
            title = LOC "$$$/FaceLabelling/PluginDialog/FaceLabellingSettings=Overall Settings",
            synopsis = bind 'synopsis',
            
            bind_to_object = propertyTable,
            
            f:view {
                fill_horizontal = 1,
                helperAppConfigView(f, propertyTable),
                logFilesView(f, propertyTable),
                configStatusView(f, propertyTable),
            } -- f:view
        }
    } -- result
    
    return result
end

--------------------------------------------------------------------------------
-- Return table

return FLEInfoProvider