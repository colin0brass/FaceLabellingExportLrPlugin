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
local LrPrefs           = import("LrPrefs")
local LrTasks           = import("LrTasks")

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
-- prefs are direct from InitPlugin, and not configured through export UI
local prefs = LrPrefs.prefsForPlugin()

-- initialised later in init function
local label_config = {}
local photo_config = {}
local labelling_context = {}

--============================================================================--
-- Functions

--------------------------------------------------------------------------------
-- Session handling, start session

function FLEMain.start(exportParams)
    logger.writeLog(4, "FLEMain.start")

     local handle = FLEExifToolAPI.openSession(exportParams)
    if not handle then
        logger.writeLog(0, "Failed to start exiftool")
        return
    else
        labelling_context.exifToolHandle = handle
    end
    
    labelling_context.imageMagickHandle = FLEImageMagickAPI.init(exportParams)
    
    local_exportParams = exportParams
end

--------------------------------------------------------------------------------
-- Session handling, stop session

function FLEMain.stop()
    logger.writeLog(4, "FLEMain.stop")
    FLEExifToolAPI.closeSession(labelling_context.exifToolHandle)
    
    success = FLEImageMagickAPI.cleanup(labelling_context.imageMagickHandle, false)
end

--------------------------------------------------------------------------------
-- Main photo render function, which reads exif and tries to optimise face labels

function FLEMain.renderPhoto(srcPath, renderedPath)
    local success = true
    local failures = {}
    local photoDimensions = {}
    local people = {}
    local labels = {}
    
    -- initialise context for new photo
    init()
    
    -- create summary of people from regions
    
    -- ==============================================================================
    -- == this version processes from the *source* photo, not the *exported* photo ==
    -- ==============================================================================
    --face_regions, photoDimension = getRegions(srcPath)
    -- ======================================================================================
    -- == this version processes from the *exported* photo which should be the 'right' way ==
    -- ======================================================================================
    face_regions, photoDimension = getRegions(renderedPath)

    logger.writeTable(4, face_regions) -- write to log for debug
    people = get_people(photoDimension, face_regions)

    -- save cropped thumbnails first, before exported image is modified by the labelling
    if local_exportParams.export_thumbnails then
        FLEMain.export_thumbnail_images(people, photoDimension, renderedPath)
    end
    -- label the exported image (after saving cropped thumbnails)
    FLEMain.export_labeled_image(people, photoDimension, renderedPath)
    
    return success, failures
end

--------------------------------------------------------------------------------
-- Export thumbanil images

function FLEMain.export_thumbnail_images(people, photoDimension, photoPath)
    logger.writeLog(2, "Export thumbnail images")

    logger.writeLog(3, "Create ImageMagick script command file for image labelling")

    for i, person in pairs(people) do -- is this robust for zero length?
        -- input file
        exported_file = '"' .. photoPath .. '"'
        command_string = '# Input file'
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
            filename_no_extension = person.name
        end
        filename = LrPathUtils.addExtension(filename_no_extension, file_extension)
        
        -- combine path and filename, and ensure unique
        local output_file_with_path = LrPathUtils.child(outputPath, filename)
        output_file_with_path = LrFileUtils.chooseUniqueFileName(output_file_with_path)
        
        -- output file
        command_string = "-write " .. '"' .. output_file_with_path .. '"'
        --command_string = "-outfile " .. '"' .. output_file_with_path .. '"'
        FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
    
        -- execute ImageMagick commands
        FLEImageMagickAPI.execute_commands(labelling_context.imageMagickHandle)
    end
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
    logger.writeLog(3, "Check and optimise positions")
    check_for_label_position_clashes()
    optimise_labels()
    
    logger.writeLog(3, "Create ImageMagick script command file for image labelling")

    -- input file
    exported_file = '"' .. photoPath .. '"'
    command_string = '# Input file'
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
                                            prefs.face_outline_line_width,
                                            prefs.face_outline_colour)
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
                                            prefs.label_outline_line_width,
                                            prefs.label_outline_colour)
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
                command_string = string.format('-font %s -pointsize %d -stroke %s -strokewidth %d -fill white -undercolor "#00000080"',
                                               prefs.font_type,
                                               label.font_size, 
                                               prefs.font_colour,
                                               prefs.font_line_width)
                FLEImageMagickAPI.add_command_string(labelling_context.imageMagickHandle, command_string)
                --text = label.text
                text = text_line_wrap(label.text, label.num_rows)
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
    
    label_config.font_size = 40 -- initial value
    label_config.format_experiment_list = {'position', 'num_rows', 'revert_to_default_position'}
    label_config.positions_experiment_list = {'below', 'above', 'left', 'right'}
    label_config.num_rows_experiment_list = {1,2,3,4,5}
end

--------------------------------------------------------------------------------
-- Get people from exif label information

function get_person(photoDimension, region)
    local name = ifnil(region.name, 'Unknown')
    
    x = region.x
    y = region.y
    w = region.w
    h = region.h
    
    logger.writeLog(4, string.format("Name '%s', x:%d y:%d, w:%d, h:%d", 
        name, x, y, w, h))
    
    if local_exportParams.obfuscate_labels then
        name = randomise_string(name)
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
    
    if x < prefs.image_margin then -- ensure not negative
        x = prefs.image_margin
    end
    if y < prefs.image_margin then
        y = prefs.image_margin
    end
    
    if (x + w) > (photoDimension.width - prefs.image_margin) then -- ensure not exceeding image dimensions
        x = photoDimension.width - prefs.image_margin - w
    end
    if (y + h) > (photoDimension.height - prefs.image_margin) then
        y = photoDimension.height - prefs.image_margin - h
    end
    
    return x,y
end

--------------------------------------------------------------------------------
-- Label positioning

function get_label_position_and_size(label)
    local success = true
    
    person = label.person
    text = text_line_wrap(label.text, label.num_rows)
    
    success, label_w, label_h = get_label_size(text, 
                                      prefs.font_type,
                                      label.font_size,
                                      prefs.font_line_width)
                                      
    if label.position == 'below' then
        x = person.x + math.floor(person.w / 2) - math.floor(label_w / 2)
        y = person.y + person.h -- should probably add some margin
        align = 'center'
    elseif label.position == 'above' then
        x = person.x + math.floor(person.w / 2) - math.floor(label_w / 2)
        y = person.y - label.h -- should probably add some margin
        align = 'center'
    elseif label.position == 'left' then
        x = person.x - person.w -- should probably add some margin
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
    if position then label.position = position end
    if num_rows then label.num_rows = num_rows end
    if text_align then label.text_align = text_align end
    if font_size then label.font_size = font_size end
    
    label.x, label.y, label.w, label.h, label.text_align = get_label_position_and_size(label)
    
    return label
end

--------------------------------------------------------------------------------
-- Create labels from exif face information

function get_labels()
    labels = {}
    people = labelling_context.people
    if people and #people > 0 then
        for i, person in pairs(people) do
            label = {}
            label.text = person.name
            label.position_clash = false -- initial value
            label.person = person
            logger.writeLog(3, "- set_label_position: " .. label.text)
            label = set_label_position(label, 
                                       prefs.default_position,
                                       prefs.default_num_rows,
                                       prefs.default_align,
                                       label_config.font_size)
            labels[i] = label
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
        dimensions_sum = 0
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
    
    people = labelling_context.people
    photoDimension = labelling_context.photo_dimensions
    
    average_region_size = get_average_region_size(people)
    font_size = label_config.font_size
    if average_region_size and average_region_size > 0 then
        if average_region_size < (photoDimension.width / prefs.image_width_to_region_ratio_small) then
            target_width = average_region_size * prefs.label_width_to_region_ratio_small
        elseif average_region_size > (photoDimension.width / prefs.image_width_to_region_ratio_large) then
            target_width = average_region_size * prefs.label_width_to_region_ratio_large
        else
            target_width = average_region_size
        end
        
        success, test_label_w, test_label_h = get_label_size(prefs.test_label, 
                                                    prefs.font_type,
                                                    font_size,
                                                    prefs.font_line_width)
        if success then
            if test_label_w < target_width then -- smaller than target
                while (test_label_w < target_width) do
                    font_size = font_size + 2
                    success, test_label_w, test_label_h = get_label_size(prefs.test_label, 
                                                                prefs.font_type,
                                                                font_size,
                                                                prefs.font_line_width)
                end
            else -- larger than target
                while (test_label_w > target_width) do
                    font_size = font_size - 2
                    success, test_label_w, test_label_h = get_label_size(prefs.test_label, 
                                                                prefs.font_type,
                                                                font_size,
                                                                prefs.font_line_width)
                end
            end -- if test_label_w < target_width; else
        end -- success
    end -- if average_region_size and average_region_size > 0

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

function check_clash(x1, y1, w1, h1,  x2, y2, w2, h2)
    non_overlapping = ((x1+w1)<=x2) or (x1>=(x2+w2)) or ((y1+h1)<=y2) or (y1>=(y2+h2))
    return not non_overlapping
end

--------------------------------------------------------------------------------
-- Check if label clashes with anything else in image

function check_label_clash(label)
    overall_clash = false
    
    -- check for clash with other labels
    labels = labelling_context.labels
    for i, other in pairs(labels) do
        if other ~= label then -- skip comparing self
            clash = check_clash(label.x, label.y, label.w, label.h,
                                other.x, other.y, other.w, other.h)
            if clash then
                overall_clash = true
                logger.writeLog(3, "- label " .. label.text .. " clash with label:" .. other.text)
            end
        end
    end
    
    -- check for clash with face outlines
    people = labelling_context.people
    for i, person in pairs(people) do
        clash = check_clash(label.x, label.y, label.w, label.h,
                                person.x, person.y, person.w, person.h)
        if clash then
            overall_clash = true
            logger.writeLog(3, "- label " .. label.text .. " clash with person:" .. person.name)
        end
    end
    
    return overall_clash
end

--------------------------------------------------------------------------------
-- Check all labels to see if any clash with anything else in image

function check_for_label_position_clashes()
    labels = labelling_context.labels
    for i, label in pairs(labels) do -- is this robust for zero length?
        clash = check_label_clash(label)
        label.position_clash = clash
    end
end

--------------------------------------------------------------------------------
-- Optimise single label position to try to avoid clashes

function optimise_single_label(label, experiment_list)
    local local_experiment_list = table_copy(experiment_list)
    local clash = true -- initial value
    if local_experiment_list and #local_experiment_list>0 then
        local experiment = table.remove(local_experiment_list)
        logger.writeLog(4, "- optimise_single_label - experiment: " .. experiment)
        
        if experiment == 'num_rows' then options_list = label_config.num_rows_experiment_list
        elseif experiment == 'position' then options_list = label_config.positions_experiment_list
        elseif experiment == 'revert_to_default_position' then options_list = {prefs.default_position}
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
                    try_position = prefs.default_position
                    try_num_rows = prefs.default_num_rows
                else
                    logger.writeLog(0, "optimise_single_label - unknown experiment type: " .. experiment)
                end
                
                label = set_label_position(label, 
                                           try_position,
                                           try_num_rows,
                                           nil,
                                           nil)
                clash = check_label_clash(label)
                label.position_clash = clash
                if not clash then
                    logger.writeLog(4, "- - successful experiment: " .. label.position .. ", rows=" .. label.num_rows)
                    break -- stop optimising when found a working configuration
                end
            end -- if clash
        end -- for i, option in pairs(options_list)
        
    end -- if local_experiment_list and #local_experiment_list>0
    
    return clash
end

--------------------------------------------------------------------------------
-- Go through all labels and try to optimise positions to avoid clashes

function optimise_labels(attempt_number)
    local labels = labelling_context.labels
    local num_optimisations = 2
    local experiment_list = label_config.format_experiment_list
    if not attempt_number then attempt_number = 1 end
    
    if attempt_number == 2 then -- on second attempt, reverse the order
        list = list_reverse(list)
    end
    
    overall_clash = false -- initial value
    for i, label in pairs(labels) do
        if label.position_clash then
            logger.writeLog(4, "= Optimising label position: " .. label.text)
            logger.writeTable(4, experiment_list)
            if attempt_number <= num_optimisations then
                clash = optimise_single_label(label, experiment_list)
                if clash then overall_clash = true end
            end
        end
    end
    
    if overall_clash and (attempt_number < num_optimisations) then
        optimise_labels(attempt_number+1)
    end
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