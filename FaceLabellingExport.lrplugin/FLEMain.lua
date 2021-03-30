--[[----------------------------------------------------------------------------
FLEMain.lua
Main face labelling functions for Lightroom face labelling export plugin

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
local LrDate            = import("LrDate")
local LrFileUtils       = import("LrFileUtils")
local LrPathUtils       = import("LrPathUtils")

--============================================================================--
-- Local imports
require "Utils.lua"
FLEExifToolAPI          = require("FLEExifToolAPI.lua")
FLEImageMagickAPI       = require("FLEImageMagickAPI.lua")

--============================================================================--
-- Local variables
local FLEMain = {}

-- exportParams are configured through the plug-in Export UI
local local_exportParams = {}

-- initialised later in init function
local label_config = {}
local photo_config = {}
local labelling_context = {}

--============================================================================--
-- Functions

--------------------------------------------------------------------------------
-- Init of exportParams from prefs, to ensure they are set even if dialogs are bypassed
-- for example if "export with previous" menu option is used

function FLEMain.init_params_from_prefs(exportParams, prefs)
    -- using prefs rather than exportPresetFields in order to configure
    -- from Lightroom Plug-in Manager, before export
    -- first the preferences configured in Plug-in Manager dialog
    for i, list_value in pairs(manager_table) do
        exportParams[list_value.key] = prefs[list_value.key]
    end
    -- then the preferences configured in Export dialog
    for i, list_value in pairs(preference_table) do
        exportParams[list_value.key] = prefs[list_value.key]
    end
end

--------------------------------------------------------------------------------
-- Session handling, start session

function FLEMain.start(exportParams)
    logger.writeLog(4, "FLEMain.start")

    labelling_context.status_ok = false -- initial value
    local handle = FLEExifToolAPI.openSession(exportParams)
    if not handle then
        logger.writeLog(0, "Failed to start exiftool")
        return
    else
        labelling_context.exifToolHandle = handle
        labelling_context.status_ok = true
    end
    
    labelling_context.imageMagickHandle = FLEImageMagickAPI.init(exportParams)
    
    local_exportParams = exportParams
end

--------------------------------------------------------------------------------
-- Session handling, stop session

function FLEMain.stop()
    logger.writeLog(4, "FLEMain.stop")
    FLEExifToolAPI.closeSession(labelling_context.exifToolHandle)
    
    success = FLEImageMagickAPI.cleanup(labelling_context.imageMagickHandle)
end

--------------------------------------------------------------------------------
-- Main photo render function, which reads exif and tries to optimise face labels

function FLEMain.renderPhoto(srcPath, renderedPath)
    local success = true
    local failures = {}
    local photoDimensions = {}
    local people = {}
    local labels = {}
    
    if labelling_context.status_ok then
    
        -- initialise context for new photo
        init()
        
        -- create summary of people from regions
        face_regions, photoDimension = getRegions(renderedPath)
    
        logger.writeTable(4, face_regions) -- write to log for debug
        people = get_people(photoDimension, face_regions)
    
        -- save cropped thumbnails first, before exported image is modified by the labelling
        if local_exportParams.export_thumbnails then
            FLEMain.export_thumbnail_images(people, photoDimension, renderedPath)
        end
        -- label the exported image (after saving cropped thumbnails)
        FLEMain.export_labeled_image(people, photoDimension, renderedPath)
        
    end -- if labelling_context.status_ok
    
    return success, failures
end

--------------------------------------------------------------------------------
-- Export thumbanil images

function FLEMain.export_thumbnail_images(people, photoDimension, photoPath)
    logger.writeLog(2, "Export thumbnail images")

    logger.writeLog(3, "Create ImageMagick script command file for image labelling")

    for i, person in pairs(people) do
    
        local person_is_named = string.len(person.name) > 0
        if person_is_named or local_exportParams.export_thumbnails_if_unnamed then
        
            -- input file
            exported_file = '"' .. photoPath .. '"'
            command_string = '# Input file'
            FLEImageMagickAPI.start_new_command(labelling_context.imageMagickHandle)
            FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
            command_string = exported_file
            FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
        
            -- crop thumbnail
            command_string = '# Person thumbnail images'
            FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
            command_string = string.format('-crop %dx%d+%d+%d',
                    person['w'], person['h'], person['x'], person['y'])
            FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
    
            -- derive output path and create directory if not already existing
            local exported_path = LrPathUtils.parent(photoPath)
            if local_exportParams.thumbnails_folder_option == 'ThumbnailsThumbFolder' then
                outputPath = LrPathUtils.child(exported_path, 'thumb')
                if not LrFileUtils.exists(outputPath) then
                    LrFileUtils.createDirectory(outputPath)
                end
            else -- not 'thumb' folder
                outputPath = exported_path
            end
            
            -- derive output file name
            local filename = LrPathUtils.leafName(photoPath)
            local filename_no_extension = LrPathUtils.removeExtension(filename)
            local file_extension = LrPathUtils.extension(filename)
            if local_exportParams.thumbnails_filename_option == 'RegionNumber' then
                filename_no_extension = filename_no_extension .. string.format('_%02d', i)
            elseif local_exportParams.thumbnails_filename_option == 'FileUnique' then
                filename_no_extension = filename
            else -- region name
                if person_is_named then
                    filename_no_extension = person.name
                else
                    filename_no_extension = 'Unknown'
                end
            end
            filename = LrPathUtils.addExtension(filename_no_extension, file_extension)
            
            -- combine path and filename, and ensure unique
            local output_file_with_path = LrPathUtils.child(outputPath, filename)
            output_file_with_path = LrFileUtils.chooseUniqueFileName(output_file_with_path)
            
            -- output file
            command_string = "-write " .. '"' .. output_file_with_path .. '"'
            FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
        
            -- execute ImageMagick commands
            FLEImageMagickAPI.execute_commands(labelling_context.imageMagickHandle)
            
        end -- if person_is_named or local_exportParams.export_thumbnails_if_unnamed
        
    end -- for i, person in pairs(people)
end

--------------------------------------------------------------------------------
-- Export labeled image

function FLEMain.export_labeled_image(people, photoDimension, photoPath)

    logger.writeLog(2, "Export labeled image")
    
    labelling_context.people = people
    labelling_context.photo_dimensions = photoDimension
    
    label_config.font_size = determine_label_font_size()
    logger.writeLog(3, "Chosen font size: " .. label_config.font_size)
                                                                                         
    -- create labels
    logger.writeLog(3, "Create labels")
    labels = get_labels()
    labelling_context.labels = labels
    
    -- check and optimise positions
    if not local_exportParams.label_auto_optimise then
        logger.writeLog(3, "Label positions set to fixed")
    else
        logger.writeLog(3, "Label positions check and optimisation")
        check_for_label_position_clashes()
        local is_clash = false -- initial value
        local recommended_config = nil -- initial value
        is_clash, recommended_config = optimise_labels()
        logger.writeLog(4, "Label positions optimised; is_clash=" .. tostring(is_clash))
        if not recommended_config then
            logger.writeLog(0, "Label position optimisation - no resulting recommended config found")
        else
            logger.writeLog(3, "Label positions - applying recommended config")
            logger.writeTable(5, recommended_config)
            labelling_context.labels, label_config.font_size = copy_config_to_labels(recommended_config)
        end
    end
    
    logger.writeLog(3, "Create ImageMagick script command file for image labelling")

    -- input file
    exported_file = '"' .. photoPath .. '"'
    command_string = '# Input file'
    FLEImageMagickAPI.start_new_command(labelling_context.imageMagickHandle)
    FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
    command_string = exported_file
    if local_exportParams.obfuscate_image then -- fade image
        command_string = command_string .. ' -fill white -colorize 95%'
    end
    if local_exportParams.remove_exif then -- remove exif
        command_string = command_string .. ' -strip'
    end
    FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)

    -- label image
    if local_exportParams.label_image then
        
        -- person face outlines
        if local_exportParams.draw_face_outlines then
            command_string = '# Person face outlines'
            FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
            command_string = string.format('-strokewidth %d -stroke %s -fill "rgba( 255, 255, 255, 0.0)"',
                                            local_exportParams.face_outline_line_width,
                                            local_exportParams.face_outline_colour)
            FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
            for i, person in pairs(people) do -- is this robust for zero length?
                command_string = string.format('-draw "rectangle %d,%d %d,%d"',
                        person['x'], person['y'], person['x']+person['w'], person['y']+person['h'])
                FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
            end
        end
        
        -- label boxes
        if local_exportParams.draw_label_boxes then
            command_string = '# Label box outlines'
            FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
            command_string = string.format('-strokewidth %d -stroke %s -fill "rgba( 255, 255, 255, 0.0)"',
                                            local_exportParams.label_outline_line_width,
                                            local_exportParams.label_outline_colour)
            FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
            for i, label in pairs(labels) do -- is this robust for zero length?
                command_string = string.format('-draw "rectangle %d,%d %d,%d"',
                        label['x'], label['y'], label['x']+label['w'], label['y']+label['h'])
                FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
            end
        end
        
        -- label text
        if local_exportParams.draw_label_text then
            command_string = '# Face labels'
            FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
            for i, label in pairs(labels) do -- is this robust for zero length?
                logger.writeLog(3, "Face label: " .. label.text)
                command_string = string.format('-font %s -pointsize %d -stroke %s -strokewidth %d -fill %s -undercolor "%s"',
                                               local_exportParams.font_type,
                                               label.font_size,
                                               local_exportParams.font_colour,
                                               local_exportParams.font_line_width,
                                               local_exportParams.font_colour,
                                               local_exportParams.label_undercolour)
                FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
                text = utils.text_line_wrap(label.text, label.num_rows)
                gravity = translate_align_to_gravity(label.text_align)
                command_string = string.format('-background none -size %dx -gravity %s caption:"%s"',
                                               label.w, gravity, text)
                FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
                command_string = string.format('-gravity NorthWest -geometry +%d+%d -composite',
                                               label.x, label.y)
                FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
            end
        end
        
    end -- label_image
        
    -- label image
    if local_exportParams.crop_image and photoDimension.HasCrop then
        command_string = string.format('-crop %dx%d+%d+%d',
                photoDimension.CropW, photoDimension.CropH, photoDimension.CropX, photoDimension.CropY)
        logger.writeLog(3, "Crop image: " .. command_string)
        FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
    else
        logger.writeLog(3, "No crop selected")
    end -- if crop

    -- output file
    local filename = LrPathUtils.leafName( photoPath )
    exported_path = LrPathUtils.parent(photoPath)
    outputPath = '"' .. LrPathUtils.child(exported_path, filename) .. '"'
    command_string = "-write " .. outputPath
    FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)

    -- execute ImageMagick commands
    FLEImageMagickAPI.execute_commands(labelling_context.imageMagickHandle)
end

--------------------------------------------------------------------------------
-- Initialisation

function init()
    labelling_context.people = nil
    labelling_context.labels = nil
    labelling_context.photo_dimensions = nil
    
    label_config.font_size = local_exportParams.label_font_size_fixed
    label_config.format_experiment_list = local_exportParams.format_experiment_list
    label_config.num_experiments = #label_config.format_experiment_list
    label_config.positions_experiment_list = local_exportParams.positions_experiment_list
    label_config.num_rows_experiment_list = local_exportParams.num_rows_experiment_list
    label_config.font_size_experiment_list = local_exportParams.font_size_experiment_list
end

--------------------------------------------------------------------------------
-- Get people from exif label information

function get_person(photoDimension, region)
    local name = utils.ifnil(region.name, 'Unknown')
    
    x = region.x
    y = region.y
    w = region.w
    h = region.h
    
    logger.writeLog(4, string.format("Name '%s', x:%d y:%d, w:%d, h:%d", 
        name, x, y, w, h))
    
    if local_exportParams.obfuscate_labels then
        name = utils.randomise_string(name)
    end
    
    person = {}
    person.x = x
    person.y = y
    person.w = w
    person.h = h
    person.name = name
    
    return person
end

function get_people(photoDimension, face_regions)
    local people = {}
    logger.writeLog(3, "get_people")
    if face_regions and #face_regions > 0 then
        for i, region in pairs(face_regions) do
            logger.writeLog(3, "get_people: num " .. i)
            people[i] = get_person(photoDimension, region)
        end -- for i, region in pairs(face_regions)
    end -- if face_regions and #face_regions > 0
    
    return people
end

--------------------------------------------------------------------------------
-- Adjust position to keep object within image bounds

function keep_within_image(x, y, w, h)
    photoDimension = labelling_context.photo_dimensions
    
    local X = utils.ifnil(photoDimension.CropX, 0)
    local Y = utils.ifnil(photoDimension.CropY, 0)
    local W = utils.ifnil(photoDimension.CropW, photoDimension.width)
    local H = utils.ifnil(photoDimension.CropH, photoDimension.height)
    local margin = local_exportParams.image_margin
    
    if x < X + margin then -- ensure not negative
        x = X + margin
    end
    if y < Y + margin then
        y = Y + margin
    end
    
    if (x + w) > (W - margin) then -- ensure not exceeding image dimensions
        x = W - margin - w
    end
    if (y + h) > (H - margin) then
        y = H - margin - h
    end
    
    return x,y
end

--------------------------------------------------------------------------------
-- Label positioning

function get_label_position_and_size(label)
    local success = true
    
    person = label.person
    text = utils.text_line_wrap(label.text, label.num_rows)
    
    if label.w ~= nil then -- check if label size already known, to save time
        label_w = label.w
        label_h = label.h
    else
        success, label_w, label_h = get_label_size(text, 
                                      local_exportParams.font_type,
                                      label.font_size,
                                      local_exportParams.font_line_width)
    end
                                      
    if label.position == 'below' then
        x = person.x + math.floor(person.w / 2) - math.floor(label_w / 2)
        y = person.y + person.h -- should probably add some margin
        align = 'center'
    elseif label.position == 'above' then
        x = person.x + math.floor(person.w / 2) - math.floor(label_w / 2)
        y = person.y - label_h -- should probably add some margin
        align = 'center'
    elseif label.position == 'left' then
        x = person.x - label_w -- should probably add some margin
        y = person.y + math.floor(person.h / 2) - math.floor(label_h / 2)
        align = 'right'
    elseif label.position == 'right' then
        x = person.x + person.w -- should probably add some margin
        y = person.y + math.floor(person.h / 2) - math.floor(label_h / 2)
        align = 'left'
    else
        logger.writeLog(0, "Unknown label position: " .. label.position)
        x, y  = person.x, person.y
        align = 'center'
    end
    
    x, y = keep_within_image(x, y, label_w, label_h)
    
    return x, y, label_w, label_h, align
end

--------------------------------------------------------------------------------
-- Set label position

function set_label_position(label, position, num_rows, text_align, font_size)
    -- if something changed that will affect label size then zap size to ensure it is re-calculated when needed
    if (num_rows ~= label.num_rows) or (font_size ~= label.font_size) then
        label.w = nil
        label.h = nil
    end
    
    if position   then label.position   = position   end
    if num_rows   then label.num_rows   = num_rows   end
    if text_align then label.text_align = text_align end
    if font_size  then label.font_size  = font_size  end
    
    label.x, label.y, label.w, label.h, label.text_align = get_label_position_and_size(label)
    
    return label
end

--------------------------------------------------------------------------------
-- Create labels from exif face information

function get_labels()
    local labels = {} -- initial value
    local people = labelling_context.people
    if people and #people > 0 then
        for i, person in pairs(people) do
            if string.len(person.name)>0 then -- only create label if person has a name string
                local label = {} -- initial value
                label.text = person.name
                label.position_clash = false -- initial value
                label.person = person
                logger.writeLog(3, "- set_label_position: " .. label.text)
                label = set_label_position(label, 
                                           local_exportParams.default_position,
                                           local_exportParams.default_num_rows,
                                           local_exportParams.default_align,
                                           label_config.font_size)
                labels[#labels+1] = label -- append label to end of list
            end -- if person.name
        end
    else
        logger.writeLog(0, "get_labels: no people found")
    end
    return labels
end

--------------------------------------------------------------------------------
-- Get average region size, to help with algorithm to choose font size

function get_average_region_size(people)
    local average_size = nil
    if people and #people > 0 then
        local dimensions_sum = 0
        for i, person in pairs(people) do
            dimensions_sum = dimensions_sum + person['w'] + person['h']
        end
        average_size = dimensions_sum / (#people*2) -- sum of dimensions / num people * 2 dimensions each (x & y)
    end
    return average_size
end

--------------------------------------------------------------------------------
-- Get label size

function get_label_size(text, font, size, line_width)
    local escaped_text = text:gsub('\n', [[\n]])--([[\n]], '\n')
    command_string = '-font ' .. font .. 
                     ' -pointsize ' .. size .. 
                     ' -strokewidth ' .. line_width .. 
                     ' label:' .. '"' .. escaped_text .. '"' ..
                     ' -format "%wx%h" info:'
    success, output = FLEImageMagickAPI.execute_convert_get_output(labelling_context.imageMagickHandle, command_string)
    if success then
        w, h = string.match(output, "(%d+)x(%d+)")
        if (w == nil) or (h == nil) then
            success = false
            w,h = 0,0
            logger.writeLog(0, "get_label_size: Failed to get label size")
        else
            w = tonumber(w)
            h = tonumber(h)
            logger.writeLog(5, "Size: " .. w .. " x " .. h)
        end
    end
    return success, w, h
end

--------------------------------------------------------------------------------
-- Algorithm to determine label font size according to picture aspect ratio

function determine_label_font_size()
    local success = true
    
    if local_exportParams.label_size_option == 'LabelFixedFontSize' then
        font_size = local_exportParams.label_font_size_fixed
        logger.writeLog(5, "determine_label_font_size: fixed font size " .. font_size)
    else
        local people = labelling_context.people
        local photoDimension = labelling_context.photo_dimensions
        
        local image_width = utils.ifnil(photoDimension.CropW, photoDimension.width)

        average_region_size = get_average_region_size(people)
        font_size = label_config.font_size
        if average_region_size and average_region_size > 0 then
            image_to_region_width_ratio = image_width / average_region_size
            logger.writeLog(5, "determine_label_font_size: image_to_region_width_ratio: " .. image_to_region_width_ratio)
            logger.writeLog(5, "determine_label_font_size: image_width_to_region_ratio_large: " .. local_exportParams.image_width_to_region_ratio_large)
            logger.writeLog(5, "determine_label_font_size: image_width_to_region_ratio_small: " .. local_exportParams.image_width_to_region_ratio_small)
            image_to_region_width_ratio_normalised = (image_to_region_width_ratio - local_exportParams.image_width_to_region_ratio_large)
                                        / (local_exportParams.image_width_to_region_ratio_small - local_exportParams.image_width_to_region_ratio_large)
            logger.writeLog(5, "determine_label_font_size: image_to_region_width_ratio_normalised " .. image_to_region_width_ratio_normalised .. " before clipping")
            if image_to_region_width_ratio_normalised > 1 then
                image_to_region_width_ratio_normalised = 1
            elseif image_to_region_width_ratio_normalised < 0 then
                image_to_region_width_ratio_normalised = 0
            end
            
            logger.writeLog(5, "determine_label_font_size: image_to_region_width_ratio_normalised " .. image_to_region_width_ratio_normalised)
            label_size_ratio = image_to_region_width_ratio_normalised * (local_exportParams.label_width_to_region_ratio_small - local_exportParams.label_width_to_region_ratio_large) + local_exportParams.label_width_to_region_ratio_large
            logger.writeLog(5, "determine_label_font_size: label_size_ratio " .. label_size_ratio)
            target_width = math.min(average_region_size * label_size_ratio, image_width)
            logger.writeLog(5, "target_width " .. target_width)
            
            local search_phase = 'start' -- initial value
            local success = true -- initial value
            local secondary_iterations = 0 -- initial value
            local font_size_delta = 0 -- initial value
            local font_size_delta_limit = 2 -- using limit as defence against infinite loop due to rounding
            local secondary_iteration_limit = 10 -- using iteration limit as defence against infinute loop due to rounding
            local search_increasing = true -- initial value

            while ( (search_phase ~= 'end') and success ) do
                local search_increasing_update = true -- initial value
                local direction_change = false -- initial value
                
                if search_phase == 'primary_coarse_search' then
                    if search_increasing then
                        font_size_delta = font_size -- doubling on the way up
                    else
                        font_size_delta = -math.floor(font_size/2) -- halving on the way down
                    end
                elseif search_phase == 'secondary_refinement' then
                    if search_increasing then delta_multiple = 0.5 else delta_multiple = -0.5 end
                    font_size_delta = math.floor(math.abs(font_size_delta) * delta_multiple)
                end
                
                if search_phase ~= 'start' then
                    font_size = font_size + font_size_delta
                end
                
                success, test_label_w, test_label_h = get_label_size(local_exportParams.test_label, 
                                                            local_exportParams.font_type,
                                                            font_size,
                                                            local_exportParams.font_line_width)
                if search_phase ~= 'start' then
                    search_increasing_update = (test_label_w < target_width)
                    direction_change = (search_increasing_update ~= search_increasing)
                    logger.writeLog(5, search_phase .. '; search_increasing:' .. tostring(search_increasing) .. '; font_size_delta:' .. tostring(font_size_delta) .. '; test_label_w:' .. test_label_w .. ' ; target_width:' .. target_width)
                end
                
                if search_phase == 'start' then
                    search_increasing_update = (test_label_w < target_width)
                    search_phase = 'primary_coarse_search'
                elseif search_phase == 'primary_coarse_search' then
                    if direction_change then search_phase = 'secondary_refinement' end
                elseif search_phase == 'secondary_refinement' then
                    if ( (math.abs(font_size_delta) < font_size_delta_limit) or (secondary_iterations > secondary_iteration_limit) ) then
                        search_phase = 'end'
                    end
                    secondary_iterations = secondary_iterations + 1 -- increment loop count as defence against infinute loop due to rounding
                else
                    logger.writeLog(0, "determine_label_font_size: unknown search phase: " .. search_phase)
                    search_phase = 'end'
                end
                
                search_increasing = search_increasing_update
                
            end -- while search_phase
        end -- if average_region_size and average_region_size > 0
    end -- if

    logger.writeLog(3, "determine_label_font_size: font size " .. font_size)
    return font_size
end

--------------------------------------------------------------------------------
-- Express text alignment as 'gravity' for talking to ImageMagick

function translate_align_to_gravity(text_align)
    if text_align=='left' then
        gravity = 'west'
    elseif text_align=='right' then
        gravity = 'east'
    elseif text_align=='center' then
        gravity = 'center'
    else
        logger.writeLog(0, "Unknown text align: " .. text_align)
        gravity = 'center'
    end
    
    return gravity
end

--------------------------------------------------------------------------------
-- Determine if two rectangles overlap

--function check_clash(x1, y1, w1, h1,  x2, y2, w2, h2)
--    non_overlapping = ((x1+w1)<=x2) or (x1>=(x2+w2)) or ((y1+h1)<=y2) or (y1>=(y2+h2))
--    return not non_overlapping
--end

function check_clash_area(x1, y1, w1, h1,  x2, y2, w2, h2)
    local non_overlapping = ((x1+w1)<=x2) or (x1>=(x2+w2)) or ((y1+h1)<=y2) or (y1>=(y2+h2))
    local is_overlap = not non_overlapping
    local overlap_area = 0 -- initial value
    if is_overlap then
        local x_size = math.min(x1+w1, x2+w2) - math.max(x1, x2)
        local y_size = math.min(y1+h1, y2+h2) - math.max(y1, y2)
        if x_size>0 and y_size>0 then
            overlap_area = x_size * y_size
        else
            logger.writeLog(0, "check_clash_area: negative x_size or y_size:" .. x_size .. ', ' .. y_size)
        end
    end
    
    return is_overlap, overlap_area
end

--------------------------------------------------------------------------------
-- Check if label clashes with anything else in image

function check_label_clash_area(label)
    local overall_clash = false -- initial value
    local clash_area = 0 -- initial value
    local label_clash_area = 0 -- initial value
    
    -- check for clash with other labels
    labels = labelling_context.labels
    for i, other in pairs(labels) do
        if other ~= label then -- skip comparing self
            clash, clash_area = check_clash_area(label.x, label.y, label.w, label.h,
                                other.x, other.y, other.w, other.h)
            if clash then
                overall_clash = true
                label_clash_area = label_clash_area + clash_area
                logger.writeLog(4, "- label " .. label.text .. " clash with label:" .. other.text .. "; clash_area: " .. tostring(clash_area))
            end
        end
    end
    
    -- check for clash with face outlines
    people = labelling_context.people
    for i, person in pairs(people) do
        clash, clash_area = check_clash_area(label.x, label.y, label.w, label.h,
                                person.x, person.y, person.w, person.h)
        if clash then
            overall_clash = true
            label_clash_area = label_clash_area + clash_area
            logger.writeLog(4, "- label " .. label.text .. " clash with person:" .. person.name)
        end
    end
    
    return overall_clash, label_clash_area
end

--------------------------------------------------------------------------------
-- Check all labels to see if any clash with anything else in image

function check_for_label_position_clashes()
    local labels = labelling_context.labels
    local label_clash_area = 0 -- initial value
    for i, label in pairs(labels) do -- is this robust for zero length?
        clash, label_clash_area = check_label_clash_area(label)
        label.position_clash = clash
    end
end

--------------------------------------------------------------------------------
-- Optimise single label position to try to avoid clashes

function optimise_single_label(label, experiment_list)
    local local_experiment_list = utils.table_copy(experiment_list)
    local clash = true -- initial value
    local photoDimension = labelling_context.photo_dimensions
    local image_width = utils.ifnil(photoDimension.CropW, photoDimension.width)
    local label_clash_area = 0 -- initial value
    
    if local_experiment_list and #local_experiment_list>0 then
        local experiment = table.remove(local_experiment_list)
        logger.writeLog(4, "- optimise_single_label - experiment: " .. experiment)
        
        if experiment == 'num_rows' then options_list = label_config.num_rows_experiment_list
        elseif experiment == 'position' then options_list = label_config.positions_experiment_list
        elseif experiment == 'revert_to_default_position' then options_list = {local_exportParams.default_position}
        else
            logger.writeLog(0, "optimise_single_label - unknown experiment type: " .. experiment)
        end
        
        for i, option in pairs(options_list) do
            if local_experiment_list and #local_experiment_list>0 then -- iterating - depth-first
                clash = optimise_single_label(label, local_experiment_list)
            end
            
            clash = label.position_clash
            if clash then -- still a clash from depth-first experiment, so work to do ...
                logger.writeLog(4, "- - experiment trying:" .. experiment .. " option: " .. option)
                try_position = nil
                try_num_rows = nil -- initial value
                if experiment == 'num_rows' then try_num_rows = option
                elseif experiment == 'position' then try_position = option
                elseif experiment == 'revert_to_default_position' then
                    try_position = local_exportParams.default_position
                    try_num_rows = local_exportParams.default_num_rows
                else
                    logger.writeLog(0, "optimise_single_label - unknown experiment type: " .. experiment)
                end
                
                label = set_label_position(label, 
                                           try_position,
                                           try_num_rows,
                                           nil,
                                           nil)
                if label.w > image_width then -- label is wider than the image
                    clash = true
                else
                    clash, label_clash_area = check_label_clash_area(label)
                    label.position_clash = clash
                    if not clash then
                        logger.writeLog(4, "- - successful experiment: " .. label.position .. ", rows=" .. label.num_rows)
                        break -- stop optimising when found a working configuration
                    end
                end -- if label.w > image_width; else
            end -- if clash
        end -- for i, option in pairs(options_list)
        
    end -- if local_experiment_list and #local_experiment_list>0
    
    return clash
end

--------------------------------------------------------------------------------
-- copy & restore label config for optimise function
function copy_labels_to_config(labels, font_size)
    logger.writeLog(5, "copy_labels_to_config")

    local dest_config = {} -- initial value
    dest_config.labels = {} -- initial value
    dest_config.font_size = font_size
    for i, label in pairs(labels) do
        dest_config.labels[i] = {} -- initial value
        dest_config.labels[i].position = label.position
        dest_config.labels[i].num_rows = label.num_rows
    end -- for i, label in pairs(labels)
    
    return dest_config
end

function copy_config_to_labels(source_config)
    logger.writeLog(5, "copy_config_to_labels")

    for i, label in pairs(source_config.labels) do
        labelling_context.labels[i].position = label.position
        labelling_context.labels[i].num_rows = label.num_rows
    end -- for i, label in pairs(source_config.labels)
    
    label_config.font_size = source_config.font_size
    for i, label in pairs(labelling_context.labels) do
        label = set_label_position(label, nil, nil, nil, source_config.font_size)
    end
end

function get_position_clash_lookup(labels, exclusion_lookup)
    local position_clash_lookup = {} -- initial value
    
    for i, label in pairs(labels) do
        if not exclusion_lookup[i] then
            position_clash_lookup[i] = label.position_clash
        end -- if not exclusion_lookup[i]
    end -- for i, label in pairs(labels)
    
    return position_clash_lookup
end

--------------------------------------------------------------------------------
-- helper functions for boolean lists
function combine_boolean_lists(list1, list2)
    local new_list = {} -- initial value
    local local_list1 = list1 -- initial value
    local local_list2 = list2 -- initial value
    if not local_list1 then local_list1 = list2 end -- handle case if list1 is not defined
    if not local_list2 then local_list2 = list1 end -- handle case if list2 is not defined
    if local_list1 then
        for i, is_true in pairs(local_list1) do
            new_list[i] = local_list1[i] or local_list2[i]
        end -- for i, is_true in pairs(local_list1)
    end
    
    return new_list
end

function mask_boolean_list(list, mask)
    local new_list = {} -- initial value
    
    for i, is_true in pairs(list) do
        if mask then
            new_list[i] = list[i] and not mask[i]
        else
            new_list[i] = list[i]
        end
    end -- for i, is_true in pairs(list)
    
    return new_list
end

function len_boolean_list(list)
    local len = 0 -- initial value
    for i, is_true in pairs(list) do
        if is_true then len = len + 1 end
    end -- for i, is_true in pairs(list)
    
    return len
end

--------------------------------------------------------------------------------
function list_move_to_front(list, first_value)
    local new_list = {first_value} -- initial value
    for i, value in pairs(list) do
        if value ~= first_value then new_list[#new_list+1] = value end
    end
    return new_list
end

function get_experiment_details(exp_name)
    local exp_details = {} -- initial value
    local found = false -- initial value
    
    if exp_name == 'position' then
        exp_details.options = list_move_to_front(label_config.positions_experiment_list, local_exportParams.default_position)
        exp_details.scope = 'per_label'
        found = true
    elseif exp_name == 'num_rows' then
        exp_details.options = list_move_to_front(label_config.num_rows_experiment_list, local_exportParams.default_num_rows)
        exp_details.scope = 'per_label'
        found = true
    elseif exp_name == 'font_size' then
        exp_details.options = label_config.font_size_experiment_list
        exp_details.scope = 'global'
        exp_details.original_font_size = label_config.font_size
        found = true
    else
        logger.writeLog(0, "get_experiment_details: unknown experiment name: " .. exp_name)
    end
    
    if found then
        exp_details.name = exp_name
        exp_details.len = #exp_details.options
        exp_details.num = math.min(1, exp_details.len)
    end
    
    return exp_details
end

function get_global_experiment_values(global_experiments)
    local font_size = nil -- default value
    for i, exp in pairs(global_experiments) do
        if exp.is_included then
            if (not exp.num) or (exp.num > exp.len) then
                logger.writeLog(0, "get_global_experiment_values: unknown experiment number: " .. exp.num)
            else
                if exp.name == 'font_size' then
                    font_size = exp.options[exp.num] -- actually treated as ratio, not absolute
                    font_size = font_size * exp.original_font_size -- multiply config font_size * ratio
                    logger.writeLog(5, "get_global_experiment_values: font_size = " .. tostring(font_size))
                else
                    logger.writeLog(0, "get_global_experiment_values: unknown experiment name: " .. exp.name)
                end
            end
        end
    end
    
    return font_size
end

function get_per_label_experiment_values(per_label_experiments)
    local position = nil -- default value
    local num_rows = nil -- default value
    for i, exp in pairs(per_label_experiments) do
        if exp.is_included then
            if (not exp.num) or (exp.num > exp.len) then
                logger.writeLog(0, "get_per_label_experiment_value: unknown experiment number: " .. exp.num)
            else
                if exp.scope == 'per_label' then
                    if exp.name == 'position' then
                        position = exp.options[exp.num]
                    elseif exp.name == 'num_rows' then
                        num_rows = exp.options[exp.num]
                    else
                        logger.writeLog(0, "get_per_label_experiment_value: unknown experiment name: " .. exp.name)
                    end
                end
            end
        end
    end
    
    return position, num_rows
end

function print_experiment_summary(experiment_list)
    logger.writeLog(3, "print_experiment_summary:")
    for i, per_label in pairs(experiment_list.per_label) do
        local exp_summary = ""
        if per_label.is_included then
            for j, exp in pairs(per_label.experiment) do
                exp_summary = exp_summary .. "; exp:" .. tostring(j) .. " " .. exp.name .. " " .. tostring(exp.num) .. " of " .. tostring(exp.len)
            end
        end
        logger.writeLog(3, "Label: " .. tostring(i) .. " is_included:" .. tostring(per_label.is_included) .. " " .. exp_summary)
    end
    for i, exp in pairs(experiment_list.global.experiment) do
        local exp_summary = ""
        if exp.is_included then
            exp_summary = exp_summary .. "; exp:" .. tostring(j) .. " " .. exp.name .. " " .. tostring(exp.num) .. " of " .. tostring(exp.len)
        end
        logger.writeLog(3, "Global: " .. tostring(i) .. " is_included:" .. tostring(exp.is_included) .. " " .. exp_summary)
    end
end

function build_experiment_list(labels_in_this_experiment)
    local experiment_list = {} -- initial value
    experiment_list.per_label = {} -- initial value
    experiment_list.global = {} -- initial value
    experiment_list.global.experiment = {} -- initial value

    if #label_config.format_experiment_list==0 then -- only build experiment if there are some experiments enabled
        logger.writeLog(5, "build_experiment_list: no experiment list found")
    else
        logger.writeLog(5, "build_experiment_list: experiment list found")
        for i, is_included in pairs(labels_in_this_experiment) do
            experiment_list.per_label[i] = {} -- initial value
            experiment_list.per_label[i].is_included = is_included
            if is_included then
                experiment_list.per_label[i].experiment = {} -- initial value
                for exp_num, exp_name in pairs(label_config.format_experiment_list) do
                    experiment_list.per_label[i].experiment[exp_num] = {} -- initial value
                    exp_details = get_experiment_details(exp_name)
                    experiment_list.per_label[i].experiment[exp_num].name = exp_details.name
                    experiment_list.per_label[i].experiment[exp_num].scope = exp_details.scope
                    if exp_details.scope == 'per_label' then -- sparse entries for per_label only
                        experiment_list.per_label[i].experiment[exp_num].is_included = true
                        experiment_list.per_label[i].experiment[exp_num].options = exp_details.options
                        experiment_list.per_label[i].experiment[exp_num].len = exp_details.len
                        experiment_list.per_label[i].experiment[exp_num].num = exp_details.num
                    else -- global, sparse table
                        experiment_list.global.experiment[exp_num] = {} -- initial value
                        experiment_list.global.experiment[exp_num].is_included = true
                        experiment_list.global.experiment[exp_num].name = exp_details.name
                        experiment_list.global.experiment[exp_num].options = exp_details.options
                        experiment_list.global.experiment[exp_num].len = exp_details.len
                        experiment_list.global.experiment[exp_num].num = exp_details.num
                        -- TO DO: find a better way to copy this; suggest to use a for loop to copy all items in exp_details
                        experiment_list.global.experiment[exp_num].original_font_size = exp_details.original_font_size
                    end
                end
            end
        end -- for i, is_included in pairs(labels_in_this_experiment)
        
    end -- if format_experiment_list
    
    return experiment_list
end

function find_next_label_in_experiment(experiment_list, current_label)
    local label_num = utils.ifnil(current_label, 1) -- initial value
    local is_found = false -- initial value
    local num_labels = #experiment_list.per_label
    while not is_found and label_num<=num_labels do
        logger.writeLog(5, "--- find_next_label_in_experiment: label_num:" .. label_num .. "; is_included:" .. tostring(experiment_list.per_label[label_num].is_included))
        if experiment_list.per_label[label_num].is_included then
            is_found = true
        else
            label_num = label_num + 1
        end
    end
    return is_found, label_num
end

function apply_global_experiments(experiment_list)
    logger.writeLog(5, "apply_global_experiments")
    font_size = get_global_experiment_values(experiment_list.global.experiment)
    if not font_size then
        logger.writeLog(0, "apply_global_experiments: no font_size found in experiment")
    else
        if font_size ~= label_config.font_size then
            logger.writeLog(5, "apply_global_experiments: setting font size to: " .. tostring(font_size))
            for i, label in pairs(labelling_context.labels) do
                label.position_clash = true -- set to re-try all labels
                label = set_label_position(label, nil, nil, nil, font_size)
            end
            label_config.font_size = font_size -- update overall config with this experiment
        else
            logger.writeLog(5, "apply_global_experiments: no change in font size: " .. tostring(font_size))
        end
    end
end

function apply_label_experiments(experiment_list)
    logger.writeLog(5, "apply_label_experiments")
    local photoDimension = labelling_context.photo_dimensions
    local image_width = utils.ifnil(photoDimension.CropW, photoDimension.width)
    for i, per_label_experiments in pairs(experiment_list.per_label) do
        if per_label_experiments.is_included then
            try_position, try_num_rows = get_per_label_experiment_values(per_label_experiments.experiment)
            if not (try_position or try_num_rows) then
                logger.writeLog(0, "apply_label_experiments: no position or num_rows found in experiment")
            else
                label = set_label_position(labelling_context.labels[i], 
                                           try_position,
                                           try_num_rows,
                                           nil,
                                           nil)
                if label.w > image_width then -- label is wider than the image
                    clash = true
                else
                    clash, label_clash_area = check_label_clash_area(label)
                    label.position_clash = clash
                    if not clash then
                        logger.writeLog(4, "- - successful experiment: " .. label.position .. ", rows=" .. label.num_rows)
                        break -- stop optimising when found a working configuration
                    end
                end -- if label.w > image_width; else
            end
        end
    end
end

function increment_and_apply_experiment(experiment_list)
    local overflow = false -- initial value
    local finished = false -- initial value
    
    local label_num = 1 -- initial value
    local first_label_num = 1 -- initial value
    local experiment_level = 1 -- initial value
    local is_found = false -- initial value
    
    local reset_experiment_labels_list = false -- initial value
    
    is_found, first_label_num = find_next_label_in_experiment(experiment_list, nil)
    label_num = first_label_num
    
    while not finished do

        if not is_found then
            overflow = true
            finished = true
            logger.writeLog(0, "increment_and_apply_experiment: no labels found in experiment")
        else -- if not is_found; else
        
            logger.writeLog(5, "increment_and_apply_experiment: experiment_level:" .. tostring(experiment_level) .. '; label_num:' .. label_num)
            
            local scope = experiment_list.per_label[label_num].experiment[experiment_level].scope
            local name = experiment_list.per_label[label_num].experiment[experiment_level].name
            if scope == 'per_label' then
                local num = experiment_list.per_label[label_num].experiment[experiment_level].num
                local len = experiment_list.per_label[label_num].experiment[experiment_level].len
                logger.writeLog(5, "increment_and_apply_experiment: per_label label_num:" .. tostring(label_num) .. "; exp name:" .. name .. '; exp num:' .. tostring(num) .. '; exp len:' .. tostring(len))
                if num < len then -- more experiment options to try
                    experiment_list.per_label[label_num].experiment[experiment_level].num = num+1
                    finished = true
                    logger.writeLog(5, "increment_and_apply_experiment: increment experiment_level:" .. tostring(experiment_level) .. "; num to " .. tostring(num+1))
                else -- if num < len; wrap-around to first option again and ripple overflow onwards
                    experiment_list.per_label[label_num].experiment[experiment_level].num = 1
                    is_found, label_num = find_next_label_in_experiment(experiment_list, label_num+1)
                    if not is_found then -- tried all labels, so now check if another experiment in list
                        logger.writeLog(5, "increment_and_apply_experiment: experiment_level:" .. experiment_level .. "; num_experiments:" .. label_config.num_experiments .. "; is_found:" .. tostring(is_found) .. '; label_num:' .. tostring(label_num))
                        if experiment_level < label_config.num_experiments then
                            label_num = 1 -- wrap around to first label and ripple to next experiment
                            experiment_level = experiment_level + 1
                            logger.writeLog(5, "increment_and_apply_experiment: increment to experiment_level:" .. tostring(experiment_level) .. '; finished:' .. tostring(finished))
                            label_num = first_label_num -- start back on first label
                            is_found = true -- reset flag
                        else -- no more experiments
                            logger.writeLog(5, "increment_and_apply_experiment: no more experiments:" .. experiment_level .. "; is_found:" .. tostring(is_found) .. '; label_num:' .. tostring(label_num))
                            overflow = true
                            finished = true
                        end -- if experiment_level < label_config.num_experiments
                    else
                        logger.writeLog(5, "increment_and_apply_experiment: experiment_level:" .. experiment_level .. "; is_found:" .. tostring(is_found) .. '; label_num:' .. tostring(label_num))
                    end
                end -- if num < len

            elseif scope == 'global' then
                local num = experiment_list.global.experiment[experiment_level].num
                local len = experiment_list.global.experiment[experiment_level].len
                reset_experiment_labels_list = true
                logger.writeLog(5, "increment_and_apply_experiment: global - name:" .. name .. '; num:' .. tostring(num) .. '; len:' .. tostring(len))
                if num < len then -- more experiment options to try
                    experiment_list.global.experiment[experiment_level].num = num+1
                    finished = true
                    logger.writeLog(5, "increment_and_apply_experiment: increment experiment_level:" .. tostring(experiment_level) .. "; num to " .. tostring(num+1))
                else -- if num < len; wrap-around to first option again and ripple overflow onwards
                    experiment_list.global.experiment[experiment_level].num = 1
                    if experiment_level < label_config.num_experiments then
                        label_num = 1 -- wrap around to first label and ripple to next experiment
                        experiment_level = experiment_level + 1
                        logger.writeLog(5, "increment_and_apply_experiment: increment to experiment_level:" .. tostring(experiment_level) .. '; finished:' .. tostring(finished))
                        label_num = first_label_num -- start back on first label
                    else -- no more experiments
                        logger.writeLog(5, "increment_and_apply_experiment: no more experiments:" .. experiment_level .. "; is_found:" .. tostring(is_found) .. '; label_num:' .. tostring(label_num))
                        overflow = true
                        finished = true
                    end -- if experiment_level < label_config.num_experiments
                end -- if num < len
                
            else -- if scope == 'per_label'; elseif scope == 'global'
                logger.writeLog(0, "increment_and_apply_experiment: unknown scope: " .. tostring(scope))
                finished = true
            end -- if scope == 'per_label'
            
        end -- if not is_found
    end -- while not finished

    local is_new_experiment = not overflow

    logger.writeLog(5, "increment_and_apply_experiment: applying experiment settings")
    apply_global_experiments(experiment_list)
    apply_label_experiments(experiment_list)
    
    return is_new_experiment, reset_experiment_labels_list
end

function test_label_positions()
    local labels = labelling_context.labels
    local is_clash = false -- initial value
    local label_clash = false -- initial value
    local clashing_labels_lookup = {} -- initial value
    local photoDimension = labelling_context.photo_dimensions
    local image_width = utils.ifnil(photoDimension.CropW, photoDimension.width)
    local label_clash_area = 0 -- initial value
    local total_clash_area = 0 -- initial value
    
    for i, label in pairs(labels) do
        if label.w > image_width then -- label is wider than the image
            is_clash = true
        else
            label_clash, label_clash_area = check_label_clash_area(label)
            label.position_clash = label_clash
            logger.writeLog(5, "- - test_label_positions: label " .. tostring(i) .. ' label_clash:' .. tostring(label_clash) .. ' clash area:' .. tostring(label_clash_area))
            
            if label_clash then
                is_clash = true
                total_clash_area = total_clash_area + label_clash_area
            end
        end -- if label.w > image_width; else
        clashing_labels_lookup[i] = label.position_clash
    end -- for i, label in pairs(labels)

    return is_clash, clashing_labels_lookup, total_clash_area
end

--------------------------------------------------------------------------------
-- Go through all labels and try to optimise positions to avoid clashes
function optimise_labels(labels_in_higher_level_experiments,
                         labels_in_this_experiment,
                         best_config,
                         minumum_overlap,
                         experiment_loop_count)

    local is_finished = false -- initial value
    local is_clash = false -- initial value
    local is_error = false -- initial value
    local experiment_list = nil -- initial value
    local reset_experiment_labels_list = false -- initial value
    
    local best_config = nil -- initial value

    experiment_loop_count = utils.ifnil(experiment_loop_count, 1)
    
    logger.writeLog(3, "- optimise_labels: starting")
    while not is_finished do
        logger.writeLog(4, " - test_label_positions")
        is_clash, clashing_labels, amount_of_overlap = test_label_positions()

        if not is_clash then
            logger.writeLog(4, "- optimise_labels: is_finished")
            is_finished = true
        else -- if not is_clash
            logger.writeLog(4, "- optimise_labels: is_clash")
            if (not minimum_overlap) or (amount_of_overlap < minimum_overlap) then
                logger.writeLog(3, "- optimise_labels: updating best_config with amount_of_overlap: " .. tostring(amount_of_overlap))
                best_config = copy_labels_to_config(labelling_context.labels, label_config.font_size)
                minimum_overlap = amount_of_overlap
            end
            
            local delta_clash_list = {} -- initial value
            if not labels_in_this_experiment or not experiment_list or reset_experiment_labels_list then
                logger.writeLog(4, "- optimise_labels: update labels_in_this_experiment")
                labels_in_this_experiment = mask_boolean_list(clashing_labels, labels_in_higher_level_experiments)
                reset_experiment_labels_list = false -- reset flag after use
                
                if len_boolean_list(labels_in_this_experiment) == 0 then
                    is_error = true
                    is_finished = true
                else -- if len_boolean_list(labels_in_this_experiment) == 0
                    experiment_list = build_experiment_list(labels_in_this_experiment)
                    if next(experiment_list)==nil then -- check for empty table
                        is_finished = true
                        logger.writeLog(4, "- optimise_labels: no experiment list found")
                    else
                        logger.writeLog(4, "- optimise_labels: experiment list found")
                    end
                    logger.writeTable(5, experiment_list)
                end
            end
            
            logger.writeLog(4, "- optimise_labels: generate delta_clash_list")
            local combined_experiment_list = combine_boolean_lists(labels_in_higher_level_experiments, labels_in_this_experiment)
            delta_clash_list = mask_boolean_list(clashing_labels, combined_experiment_list)
        
            if len_boolean_list(delta_clash_list)>0 then
                logger.writeLog(4, "- optimise_labels: recurse into optimise_labels to try experiments on newly discovered delta_clash_list")
                local local_labels_in_this_experiment = utils.table_copy(labels_in_this_experiment)
                local local_delta_clash_list = utils.table_copy(delta_clash_list)
                is_clash, recommended_config, experiment_loop_count = optimise_labels(local_labels_in_this_experiment,
                    local_delta_clash_list, best_config, minimum_overlap, experiment_loop_count)
                --is_clash, recommended_config, experiment_loop_count = optimise_labels(labels_in_this_experiment,
                --    delta_clash_list, best_config, minimum_overlap, experiment_loop_count)
            else -- if delta_clash_list
                logger.writeLog(4, "- optimise_labels: clash but not with new labels, so continue with this set of experiments")
                if not is_finished then
                    logger.writeLog(4, "- optimise_labels: increment_and_apply_experiment")
                    is_new_experiment, reset_experiment_labels_list = increment_and_apply_experiment(experiment_list)
                    logger.writeLog(4, "- optimise_labels: increment_and_apply_experiment; done")

                    print_experiment_summary(experiment_list)
                    
                    if not is_new_experiment then -- exhausted all the experiment options
                        logger.writeLog(4, "- optimise_labels: exhausted all the experiment options")
                        is_finished=true
                    end -- if not is_new_experiment
                else
                   logger.writeLog(4, "- optimise_labels: delta but is_finished=" .. tostring(is_finished) .. '; is_error = ' .. tostring(is_error))
                end -- if not is_finished
            end -- if delta_clash_list
            
        end -- if not is_clash; else
        
        if experiment_loop_count < local_exportParams.experiment_loop_limit then
            if math.floor((experiment_loop_count + 1)/100) ~= math.floor(experiment_loop_count/100) then
                logger.writeLog(1, "optimise_labels is taking a while; experiment_loop_count reached: " .. experiment_loop_count+1 .. " ; limit is: " .. local_exportParams.experiment_loop_limit)
            else
                logger.writeLog(3, "- optimise_labels: experiment_loop_count:" .. experiment_loop_count+1)
            end
            experiment_loop_count = experiment_loop_count + 1
        else
            logger.writeLog(1, "optimise_labels: reached loop count limit, so exiting optimisation with best config found")
            is_finished = true
        end
    end -- while not is_finished
    
    if (is_finished and not is_clash) then
        recommended_config = copy_labels_to_config(labelling_context.labels, label_config.font_size)
    else
        recommended_config = best_config
    end

    logger.writeLog(3, "- optimise_labels: finishing")
    return is_clash, recommended_config, experiment_loop_count
end

--------------------------------------------------------------------------------
-- Get face regions from photo file exif data

function getRegions(photoPath)
    logger.writeLog(4, 'Parse photo: ' .. photoPath)
    exifToolHandle = labelling_context.exifToolHandle
    local facesLr, photoDimension = FLEExifToolAPI.getFaceRegionsList(exifToolHandle, photoPath)

    return facesLr, photoDimension
end

return FLEMain