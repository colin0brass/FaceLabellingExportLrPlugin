# FaceLabellingExportLrPlugin
URl: https://github.com/colin0brass/FaceLabellingExportLrPlugin

## About
This is a plug-in for Adobe Lightroom (Classic), to export images with face labelling from EXIF metadata
* Plug-in name: FaceLabellingExport.lrplugin

## Illustration of Purpose
The image below is deliberately obfuscated (confidential details hidden by fading image and randomising text), however
hopefully gives an idea of the purpose of this plug-in.
![obfuscated example image](https://github.com/colin0brass/FaceLabellingExportLrPlugin/blob/master/obfuscated_label_test.jpg)

The face region outline boxes are optional and would typically be left disabled in real use, however I added them
in this example since I feel they help to show what is going on for this highly faded-out image.

The plug-in did the following:
1. Exported image file from Lightroom to specified location
2. Used existing exif metadata in the image file to locate the face regions
3. Created name label text for all the faces and devised where to position on the image and how to format them
(e.g. font size and line-wrapping)
4. Annotated the labels on the image and saved as update to the exported file

There is certainly lots that can be improved (see some thoughts listed further below), but hopefully this can be useful.

## Status
This plug-in was first created in August 2020, and has limited use so far,
but does seem to be working for a few users across Mac and Windows platforms.

Please also be aware that I only have limited image test-cases, so I fully expect there to still be limitations and
issues across a broader set of image formats and exif variations.

In the first releases I strongly advised this only for the intrepid who were comfortable with computing and scripting,
and prepared for some failures and debug.

I suspect now a wider set of people _should_ be able to use it, however I'm sure there will still be aspects of
deployment and compatibility that I haven't come across yet and therefore will cause issues and need me to fix them.

Please feel free to raise issues in github, and give information about the version, platform and more specific details
to help with diagnosis and fixing.

## Quick-Start Notes
Abbreviated instructions:
1. Please note this is an early prototype, so please only try if you are comfortable with computing and likely issues
2. Install helper apps: imagemagick (http://www.imagemagick.org) and perhaps exiftool (https://exiftool.org) if the
copy of exiftool I included in the plug-in doesn't work for you
3. Download this plug-in & install in Lightroom Plug-in Manager
4. Configure this plug-in in Lightroom Plug-in Manager: ensure helper apps are found
5. Select some photos in Lightroom, "Export..."
6. Select "Export to:" "Face Labelling Export"; check the export options; "Export"
7. Browse to your export location and hopefully you will have some new files there

## Longer Notes and Instructions
### Helper apps
This plug-in requires the following separate helper tools to be installed:
* imagemagick: http://www.imagemagick.org
* exiftool: https://exiftool.org    (I have tried including this in the plug-in, so you might not need to install this)

I have tried including a copy of ExifTool inside this plug-in, and it works for me both on Mac and Windows, but I
fully expect there might be limitations and others might end up having to install ExifTool themselves.

On Mac the operating system requires binaries to be confirmed safe before use. To do this, open the plug-in folder
in Finder (e.g. right click on it and 'Show Package Contents), browse to helper app file (e.g. Mac/ExifTool/exiftool),
and 'open' it (e.g. right click and select 'Open') to prompt the OS to look at it and ask you if you trust it.

I did try to include imagemagick inside this plug-in, however it didn't work, so that definitely needs to be separately
downloaded and installed.

### Plug-in installation
Download and unzip (if zipped) this plug-in to a suitable location on your computer.
* e.g. from github, see "Code" drop-down, and select "Download ZIP"

**Note**
* Windows users are advised _not_ to install the plugin under Lightroom folder in Program Files (causes problems)

Add the plug-in into Lightroom Classic
* In Lightroom, go to File -> Plug-in Manager
* From there, "Add", select the new plug-in and "Add Plug-in"
* Note, this tells Lightroom where to find the plug-in, and will use from there. It doesn't copy it elsewhere, so don't delete the files!

### Plug-in update
It will often be sufficient to download new version, put in same location to overwrite old files,
and either restart Lightroom Classic, or "Reload Plug-in" in Plug-in Manager, or "Remove" and then "Add" in Plug-in Manager.
To be safe and tidy in case some old files in the plug-in become obsolete, it could be good to delete the old plug-in folder from time to time before installing new version.
Check the plug-in version shown under Lightroom Plug-in Manager to see if update has been correctly installed and loaded
(note that this version information is intended to be aligned with github release & tag numbers, however is separately coded so on occasion I might miss updating it)

### Plug-in removal
If you are done with this plug-in and want to remove it:
* In Lightroom, go to File -> Plug-in Manager
* From there, take note of the plug-in file path shown in "Status", so you know where to find and delete the files
* You can then select the plug-in from the list and click "Remove"
* Now you can delete the files from the path you noted above

### Plug-in configuration
Once the plug-in is installed, please check its configuration in Plug-in Manager.
See "Overall Settings", where the paths to the helper apps are configured.

It will have a go at choosing default paths for Mac vs Windows, however they might well be wrong for your computer
setup, so please do check and update as necessary. The default paths for ImageMagick are simple fixed paths, with no
clever sensing or update going on, so they are highly likely to need updating.

Please check if it says 'Found' for all of the helper apps, and if not, ensure they are installed and that the
paths are correct.

Export settings in Export dialog box are persistent between sessions (saved during 'Export' operation)

### Export
Once the plug-in is installed and configured (as above), select some photos from your libary in Lightroom (Classic)
and click 'Export...".

Select "Face Labelling Export" from the "Export To:" option at the top of the screen.

I have not done any testing of the standard Export "Add to this catalog" option. I suspect I might try to remove it
in future.

I have added selection of the font type, which uses ImageMagick to list available system fonts
In case of problems, or to check what fonts ImageMagick knows about, try something like the following on the command-line (adding path to ImageMagick app if you need to):
`magick -list font`
or on a linux-like system with "grep" available, to get a more condensed font list:
`magick -list font | grep Font`

Check the export location, choose your labelling options (e.g. whether to draw the text, and which boxes to draw)
and finally click "Export"

# Limitations - Known & Likely
* Mainly tested on Mac, with a quick successful test on Windows, but I fully expect there to be robustness/portability issues
* Only tested with jpeg images, therefore other file types are likely not to work
* Limited testing with rotated and cropped images, so might be limitations
* Not tested with a wide range of images, types and exif labelling, therefore probably limitations

## Potential future improvements
* Support & test wider range of image file & exif formats
* Built-in plug-in upgrade mechanism
* Deploy helper-apps directly in plug-in distribution instead of requiring separate installation (ExifTool & ImageMagick)
* Improve labelling layout, font configuration, label backgrounds
* Improve label positioning algorithm

## Test platform
I have used the following for my (limited) testing so far:

### Mac
* iMac (2017), Intel Core i5; 16GB RAM
* MacOS Catalina v10.15.6; Big Sur v11.1, v11.2; Monterey v12.4
* Lightroom Classic v9.4; v10.1; v10.1.1; v11.4
* ImageMagick 7.0.10-25
* ExifTool 12.01

### Windows
* Lenovo Thinkpad, Intel i3; 8GB RAM
* Windows 10 Home, v1909; v21H1
* lightroom Classic v9.4; v11.4.1
* ImageMagic 7.0.10-28; 7.1.0-39
* ExifTool 12.04; 12.42