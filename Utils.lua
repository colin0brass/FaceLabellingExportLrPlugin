--[[----------------------------------------------------------------------------
Utils.lua
Helper functions for Lightroom thumbnail export
--------------------------------------------------------------------------------
Colin Osborne
August 2020
------------------------------------------------------------------------------]]

--============================================================================--
-- Lightroom imports
local LrPathUtils 		= import 'LrPathUtils'

-------------------------------------------------------------------------------

function ifnil(str, subst)
	return ((str == nil) and subst) or str
end 

function iif(condition, thenExpr, elseExpr)
	if condition then
		return thenExpr
	else
		return elseExpr
	end
end

function cmdlineQuote()
	if WIN_ENV then
		return '"'
	elseif MAC_ENV then
		return ''
	else
		return ''
	end
end

function path_quote_selection_for_platform(path)
    if WIN_ENV == true then
        path = path -- no change
    else -- Mac
        path = '"' .. path .. '"'
    end
    
    return path
end


