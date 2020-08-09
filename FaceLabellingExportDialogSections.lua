--[[----------------------------------------------------------------------------
FaceLabellingExportDialogSections.lua
Export dialog customization for Lightroom face labelling export plugin
--------------------------------------------------------------------------------
Colin Osborne
August 2020
------------------------------------------------------------------------------]]

--============================================================================--
-- Lightroom imports
local LrView = import('LrView')
local LrPathUtils = import("LrPathUtils")

--============================================================================--

FaceLabellingExportDialogSections = {}

-------------------------------------------------------------------------------

local function updateExportStatus( propertyTable )
    local message = nil
    
--[[
    repeat -- only goes through once, but using this as easy way to 'break' out
 		if propertyTable.exiftoolprog and ( propertyTable.path == "" or propertyTable.path == nil ) then
			message = LOC "$$$/FaceLabelling/ExportDialog/Messages/EnterSubPath=Enter a destination path"
			break
		end
    until true -- only go through once
]]
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

function FaceLabellingExportDialogSections.startDialog( propertyTable )
    propertyTable:addObserver( 'exiftoolprog', updateExportStatus )
    propertyTable:addObserver( 'imageMagicApp', updateExportStatus )
    
    propertyTable.exiftoolprog  = LrPathUtils.child(_PLUGIN.path, 'ExifTool/exiftool')
    propertyTable.imageMagicApp = "/usr/local/bin/magick"
    propertyTable.convertApp    = "/usr/local/bin/convert"
    
    propertyTable.draw_label_text    = true
    propertyTable.draw_face_outlines = false
    propertyTable.draw_label_boxes   = false
    
    updateExportStatus( propertyTable )
end

function FaceLabellingExportDialogSections.sectionsForBottomOfDialog( _, propertyTable )
    local f = LrView.osFactory()
    local bind = LrView.bind
    local share = LrView.share
    
    local result = {
        {
            title = LOC "$$$/FaceLabelling/ExportDialog/FaceLabellingSettings=Face Labelling",
            
            --synopsis = bind { key = 'fullPath', object = propertyTable },
            
            f:row {
                f:checkbox {
                        title = LOC "$$$/FaceLabelling/ExportDialog/drawLabelText=Draw label text:",
                        value = bind 'draw_label_text',
                },
                f:checkbox {
                        title = LOC "$$$/FaceLabelling/ExportDialog/drawFaceOutlines=Draw face outlines:",
                        value = bind 'draw_face_outlines',
                },
                f:checkbox {
                        title = LOC "$$$/FaceLabelling/ExportDialog/drawLabelBoxes=Draw label outlines:",
                        value = bind 'draw_label_boxes',
                },
            },
            
            f:row {
                    f:static_text {
                        title = LOC "$$$/FaceLabelling/ExportDialog/ExifToolProg=ExifTool program:",
                        alignment = 'right',
                        width = share 'labelWidth'
                    },
                    
                    f:edit_field {
                        value = bind 'exiftoolprog',
                        --validate = -- should add a validator that app file exists at path
                        height_in_lines = 2,
                        width = share 'valueFieldWidth',
                        width_in_chars = 30
                    }
            },
            
            f:row {
                    f:static_text {
                        title = LOC "$$$/FaceLabelling/ExportDialog/ImageMagickProg=ImageMagick main program:",
                        alignment = 'right',
                        width = share 'labelWidth'
                    },
                    
                    f:edit_field {
                        value = bind 'imageMagicApp',
                        --validate = -- should add a validator that app file exists at path
                        height_in_lines = 2,
                        width = share 'valueFieldWidth'
                    }
            },
            
            f:row {
                    f:static_text {
                        title = LOC "$$$/FaceLabelling/ExportDialog/ImageMagickConvertProg=ImageMagick convert program:",
                        alignment = 'right',
                        width = share 'labelWidth'
                    },
                    
                    f:edit_field {
                        value = bind 'convertApp',
                        --validate = -- should add a validator that app file exists at path
                        height_in_lines = 2,
                        width = share 'valueFieldWidth'
                    }
            },

        }
    }
    
    return result
end