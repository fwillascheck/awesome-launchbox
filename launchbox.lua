-- Launchbox
-- Rofi-like application and document launcher
-- Author:  Frank Willascheck <github.com/fwillascheck>
-- Created: 2024 Feb 12
-- License: MIT license

local wibox = require("wibox")
local placement = require("awful.placement")
local screen = require("awful.screen")
local keygrabber = require("awful.keygrabber")
local spawn = require("awful.spawn")
local utils = require("menubar.utils")
local beautiful = require("beautiful")
local dpi = beautiful.xresources.apply_dpi
local gshape = require("gears.shape")
local gtimer = require("gears.timer")
local gtable = require("gears.table")
local gio = require("lgi").Gio

-- =================================================================================================

local helper = {}

-- -------------------------------------------------------------------------------------------------

function helper.get_size( font, text )
    local t = wibox.widget.textbox( text, true )
    t.font = font
    return t:get_preferred_size()
end

-- -------------------------------------------------------------------------------------------------

function helper.get_width( font, text )
    local w, _ = helper.get_size( font, text )
    return w
end

-- -------------------------------------------------------------------------------------------------

function helper.get_height( font )
    local _, h = helper.get_size( font, "M" )
    return h
end

-- -------------------------------------------------------------------------------------------------

function helper.read_files( dir_table, ext_table, file_callback, disable_recursive )

    -- convert file extension table into map
    local ext_map = {}
    if ext_table then
        for i, ext in ipairs( ext_table ) do ext_map[ ext ] = 1 end
    end

    -- build map of excluded dirs
    local exclude_dir_map = {}
    for i, dir in ipairs( dir_table ) do
        if string.sub( dir, 1, 1) == "-" then
            --io.stdout:write( "helper.read_files(): adding exclude directory: "..dir.."\n" )
            exclude_dir_map[ string.sub( dir, 2 ) ] = 1
            table.remove( dir_table, i )
        end
    end

    local result_list = {}
    local gio_file_attributes = gio.FILE_ATTRIBUTE_STANDARD_NAME .. "," .. gio.FILE_ATTRIBUTE_STANDARD_TYPE

    local function read_dir( gio_file )

        local gio_file_enum = gio_file:enumerate_children( gio_file_attributes, gio.FileQueryInfoFlags.NONE )

        while true do

            local gio_file_info = gio_file_enum:next_file()
            if not gio_file_info then break end

            local gio_file_type = gio_file_info:get_file_type()
            local gio_file_child = gio_file_enum:get_child( gio_file_info )
            local file_path = gio_file_child:get_path()

            if gio_file_type == "REGULAR" then
                local file_name = gio_file_child:get_basename()
                if not ext_table or ext_map[ file_name:match(".+%.(.*)$") or "" ] then
                    --io.stdout:write( "helper.read_files(): read_dir(): processing file "..file_path.."\n")
                    if file_callback then
                        -- build list of callback return values
                        local value = file_callback( file_path, file_name )
                        if value then
                            table.insert( result_list, value )
                        end
                    else
                        -- default build list of files
                        table.insert( result_list, file_path )
                    end
                end
            elseif gio_file_type == "DIRECTORY" and not disable_recursive then
                if not exclude_dir_map[ file_path ] then
                    --io.stdout:write( "helper.read_files(): read_dir(): entering sub directory "..file_path.."\n")
                    read_dir( gio_file_child )
                end
            end

        end

        gio_file_enum:close()

    end

    for _, dir in ipairs( dir_table ) do
        --io.stdout:write( "helper.read_files(): entering directory "..dir.."\n")
        read_dir( gio.File.new_for_path( dir ) )
    end

    return result_list

end

-- -------------------------------------------------------------------------------------------------

function helper.file_exists( name )
    local f = io.open( name, "r" )
    return f ~= nil and io.close( f )
end

-- =================================================================================================

local launchbox = { mt = {} }

-- -------------------------------------------------------------------------------------------------

function launchbox:create_popup( args )

    local args = args or {}

    local header = wibox.widget.textbox( self.name )
    header.font = self.config.font
    header.align = "center"

    local launcher_with_header = wibox.widget {
        layout = wibox.layout.fixed.vertical,
        -- header
        {
            widget = wibox.container.margin,
            top = self.config.margin,
            color = self.config.bg,
            {
                widget = wibox.container.background,
                bg = self.config.bg,
                header
            }
        },
        -- launchbox
        self
    }

    local popup = wibox( {
        ontop = true,
        visible = false,
        border_width = args.border_width or beautiful.menubar_border_width or beautiful.border_width or 0,
        border_color = args.border_color or beautiful.menubar_border_color or beautiful.border_normal,
        width = self.width,
        height = self.height + helper.get_height( header.font ) + self.config.margin,
        widget = launcher_with_header
    } )

    popup.open = function()

        if popup.visible then return false end

        popup.screen = screen.focused()
        placement.align( popup, {
            position = args.position or "centered",
            margins = args.padding or 0,
            honor_workarea = true
        } )

        self:init_list()
        self:start( popup.close )
        popup.visible = true

        return true

    end

    popup.close = function()

        if not popup.visible then return false end

        self:stop()
        popup.visible = false

        return true

    end

    popup.toggle = function()
        if not popup.open() then popup.close() end
    end

    return popup

end

-- -------------------------------------------------------------------------------------------------

function launchbox:prepare_menu_items()

    io.stdout:write( "launchbox["..self.name.."].prepare_menu_items(): #all_items = " .. tostring( #self.all_items) .. "\n" )

    -- needed to pre-render icon
    local icon_box = nil
    if not self.config.disable_icons then
        icon_box = wibox.widget.imagebox()
        icon_box.resize = true
        icon_box.forced_width = self.config.icon_size
        icon_box.forced_height = self.config.icon_size
    end

    -- use cache to only draw each icon once
    local cached_icon_surfaces = {}
    local icon_path_to_cache_id = {}

    local max_item_width = -1

    for _, item in ipairs( self.all_items ) do

        if not self.config.disable_icons and item.icon_path then
            --io.stdout:write( "launchbox["..self.name.."].prepare_menu_items(): "..item.name..", icon_path: "..item.icon_path..", " )
            local surf = cached_icon_surfaces[ icon_path_to_cache_id[ item.icon_path ] ]
            if not surf then
                --io.stdout:write( "creating surface\n" )
                icon_box.image = item.icon_path
                surf = wibox.widget.draw_to_image_surface( icon_box, self.config.icon_size, self.config.icon_size )
                table.insert( cached_icon_surfaces, surf )
                icon_path_to_cache_id[ item.icon_path ] = #cached_icon_surfaces
            else
                --io.stdout:write( "using cached surface\n" )
            end
            item.icon_surface = surf
        end

        -- only if needed
        if not self.width then
            -- replace non-word chars with a medium width char for more exact width calculation
            local name = string.gsub( item.name, "%A", "_" )
            max_item_width = math.max( max_item_width, helper.get_width( self.config.font, name ) )
        end

    end

    -- sort by type and name
    table.sort( self.all_items, function( a, b )
        if a.type == b.type then
            return a.name_lower < b.name_lower
        end
        return a.type < b.type
    end)

    -- pre-cache self.all_items with empty query,
    -- needed as direct result if query is empty
    table.insert( self.filtered_items_cache, self.all_items )
    self.filtered_items_cache_index[ "" ] = #self.filtered_items_cache

    if not self.width then
        --io.stdout:write( "launchbox.prepare_menu_items(): max_item_width = " .. tostring(max_item_width) .. "\n")
        local item_width = 0
        -- add 2 * 2 px for item margin
        -- for some strange reason we need to add another 2 * 2 px to fit properly
        if self.config.disable_icons then
            item_width = max_item_width + 4 * dpi(2)
        else
            item_width = self.config.icon_size + self.config.icon_spacing + max_item_width + 4 * dpi(2)
        end
        self.list_widget.forced_width = item_width
        -- finally add margin to get the total width
        self.width = item_width + 2 * self.config.margin
        --io.stdout:write( "launchbox.prepare_menu_items(): calculated self.width = " .. tostring( self.width ) .. "\n" )
    end

end

-- -------------------------------------------------------------------------------------------------

function launchbox:write_all_items_to_cache_file()

    local file = io.open( self.item_cache_file, "w" )
    if not file then return end

    io.stdout:write( "launchbox["..self.name.."].write_all_items_to_cache_file(): "..self.item_cache_file.."\n" )

    for _, item in ipairs( self.all_items ) do
        for k, v in pairs( item ) do
            if v then file:write( k..":"..v.."," ) end
        end
        file:write("\n")
    end

    file:close()

end

function launchbox:read_all_items_from_cache_file()

    local file = io.open( self.item_cache_file, "r" )
    if not file then return end

    io.stdout:write( "launchbox["..self.name.."].read_all_items_from_cache_file(): "..self.item_cache_file.."\n" )

    for line in file:lines() do
        local item = {}
        for k, v in string.gmatch( line, "([^,:]+):([^,:]+)," ) do
            --io.stdout:write(k.." = "..v.."\n")
            item[ k ] = v
        end
        --io.stdout:write( "\n" )
        table.insert( self.all_items, item )
    end

    file:close()
    self:prepare_menu_items()

end

-- -------------------------------------------------------------------------------------------------

function launchbox:read_desktop_apps()

    -- first parse system dirs (lower prio),
    -- then user dir (higher prio) to allow overwrite
    local xdg_dirs = {
        "/usr/share/applications",
        ".local/share/applications"
    }

    utils.terminal = self.config.terminal
    --utils.wm_name = ""

    local all_apps = helper.read_files( xdg_dirs, { "desktop" }, utils.parse_desktop_file )
    --io.stdout:write( "launchbox.read_desktop_apps(): #all_apps = " .. tostring( #all_apps) .. "\n")

    -- reverse table to map name to id in result
    -- for easier overwrite and removal of entries with same name
    local name_to_id = {}

    for app_id, app in ipairs( all_apps ) do
        -- only keep apps that should be shown
        name_to_id[ app.Name ] = ( app.show and app_id ) or nil
    end

    local app_fallback_icon_path = utils.lookup_icon("applications-other")

    for _, app_id in pairs( name_to_id ) do
        local entry = all_apps[ app_id ]
        table.insert( self.all_items, {
            type = 1, -- application
            name = entry.Name,
            name_lower = string.lower( entry.Name ),
            cmdline = entry.cmdline,
            icon_path = entry.icon_path or app_fallback_icon_path,
            --icon_surface = nil,
            match_pos = 0
        } )
    end

end

-- -------------------------------------------------------------------------------------------------

function launchbox:read_documents()

    -- only apps and categories will we searched
    local document_icon_path = utils.lookup_icon("gnome-documents")

    local function create_item( file_path, file_name )
        table.insert( self.all_items, {
            type = 3, -- document
            name = file_name,
            name_lower = string.lower( file_name ),
            cmdline = "xdg-open \"" .. file_path .. "\"",
            icon_path = document_icon_path,
            match_pos = 0
        } )
    end

    helper.read_files( self.config.doc_dirs, self.config.doc_ext, create_item )

end

-- -------------------------------------------------------------------------------------------------

function launchbox:read_bin_files()

    -- only apps and categories will we searched
    local bin_file_icon_path = utils.lookup_icon("applications-all")

    -- needed to filter out duplicate programs in /bin and /usr/bin
    local all_bin_files = {}

    local function create_item( file_path, file_name )

        if #file_name == 1 then
            --io.stdout:write("launchbox.read_bin_files(): sorting out 1-char file: "..file_path.."\n")
            return
        end

        if all_bin_files[ file_name ] then
            --io.stdout:write("launchbox.read_bin_files(): bin-file already available: "..file_name.."\n")
            return
        end

        table.insert( self.all_items, {
            type = 2, -- bin-file/executable
            name = file_name,
            name_lower = string.lower( file_name ),
            cmdline = utils.terminal .. " -e " .. file_path,
            icon_path = bin_file_icon_path,
            match_pos = 0
        } )

        all_bin_files[ file_name ] = 1

    end

    helper.read_files( self.config.bin_dirs, self.config.bin_ext, create_item, true )

end

-- -------------------------------------------------------------------------------------------------

function launchbox:read_all_files()

    io.stdout:write( "launchbox["..self.name.."].read_all_files()\n" )

    self.all_items = {}
    self.filtered_items = {}
    self.filtered_items_cache_index = {}
    self.filtered_items_cache = {}
    self.no_result_cache = {}

    if not self.config.disable_apps then
        self:read_desktop_apps()
    end

    if self.config.doc_dirs then
        self:read_documents()
    end

    if self.config.bin_dirs then
        self:read_bin_files()
    end

    if not self.config.disable_cache then
        self:write_all_items_to_cache_file()
    end

    self:prepare_menu_items()

    if self.grabber then
        -- live update if launchbox is active
        -- and user requested refresh of list
        self:init_list()
        self:set_current_item_focus()
    end

end

-- -------------------------------------------------------------------------------------------------

function launchbox:get_row( item_id )
    return ( item_id - self.first_item ) + 1
end


function launchbox:get_item_id( row )
    return ( self.first_item + row ) - 1
end

-- -------------------------------------------------------------------------------------------------

function launchbox:update_list()

    for row, list_object in ipairs( self.list_objects ) do

        local item_id = self:get_item_id( row )

        if item_id > #self.filtered_items then
            list_object.name.text = ""
            list_object.icon.image = nil
        else
            local item = self.filtered_items[ item_id ]
            list_object.name.text = item.name
            list_object.icon.image = item.icon_surface
        end

    end

end

-- -------------------------------------------------------------------------------------------------

function launchbox:set_current_item_color( fg, bg )

    if self.current_item < 1 then return end
    local current_row = self:get_row( self.current_item )
    self.list_objects[ current_row ]:set_color( fg, bg )

end


function launchbox:set_current_item_focus()

    self:set_current_item_color( self.config.fg_focus, self.config.bg_focus )

end


function launchbox:clear_current_item_focus()

    self:set_current_item_color( self.config.fg, nil )

end

-- -------------------------------------------------------------------------------------------------

function launchbox:set_current_item_up()

    if self.current_item <= 1 then return end

    self:clear_current_item_focus()
    self.current_item = math.max( self.current_item - 1, 1 )

    if self.current_item < self.first_item then
        self.first_item = self.current_item
        self:update_list()
    end

    self:set_current_item_focus()

end


function launchbox:set_current_item_down()

    if self.current_item == #self.filtered_items then return end

    self:clear_current_item_focus()
    self.current_item = math.min ( self.current_item + 1, #self.filtered_items )

    if self.current_item > self:get_item_id( #self.list_objects ) then
        self.first_item = self.first_item + 1
        self:update_list()
    end

    self:set_current_item_focus()

end

-- -------------------------------------------------------------------------------------------------

function launchbox:reset_list()

    self:clear_current_item_focus()
    self.first_item = 1
    self:update_list()
    self.current_item = math.min ( 1, #self.filtered_items )
    self:set_current_item_focus()

end

-- -------------------------------------------------------------------------------------------------

function launchbox:init_list()

    --io.stdout:write( "launchbox["..self.name.."].init_list()\n" )

    self.query = ""
    self.query_history = {}
    self.input.text = ""
    self.filtered_items = self.all_items

    self:clear_current_item_focus()
    self.first_item = 1
    self:update_list()
    self.current_item = math.min ( 1, #self.filtered_items )

end

-- -------------------------------------------------------------------------------------------------

function launchbox:filter_items( query, prev_query )

    --io.stdout:write( "launchbox.filter_items(): *** new query ["..query.."] ***\n" )

    if self.no_result_cache[ query ] then
        --io.stdout:write( "launchbox.filter_items(): we already know that the query has no result\n" )
        return false
    end

    -- will also find self.all_items with query=""
    local cache_index = self.filtered_items_cache_index[ query ]
    if cache_index then
        self.filtered_items = self.filtered_items_cache[ cache_index ]
        self:reset_list()
        --io.stdout:write( "launchbox.filter_items(): show cached result, no search needed\n" )
        return true
    end

    -- search for cached results for previous query (in case of backspace)
    -- only works because we can't freely edit the input field
    cache_index = -1
    cache_index = self.filtered_items_cache_index[ prev_query ]
    --if cache_index then
        --io.stdout:write( "launchbox.filter_items(): use cached result of previous query ["..prev_query.."] for new search\n" )
    --end

    local items_to_filter = self.filtered_items_cache[ cache_index ] or self.all_items
    local query_items = {}

    -- the filter
    for _, item in ipairs( items_to_filter ) do

        --io.stdout:write( "launchbox.filter_items(): checking ["..query.."] against ["..item.name_lower.."]\n")
        local name_pos, _, _ = string.find( item.name_lower, query, 1, true )

        if name_pos then
            --io.stdout:write( "launchbox.filter_items(): found ["..query.."] in ["..item.name_lower.."], pos="..tostring(name_pos).."\n")
            -- use name match position as prio for sorting
            item.match_pos = name_pos
            table.insert ( query_items, item )
        end

    end

    if #query_items == 0 then
        --io.stdout:write( "launchbox.filter_items(): no items found for query ["..query.."]\n" )
        self.no_result_cache[ query ] = 1
        return false
    end

    -- sort by match_pos and name
    table.sort( query_items, function( a, b )
        if a.match_pos == b.match_pos then
            return a.name_lower < b.name_lower
        end
        return a.match_pos < b.match_pos
    end)

    --io.stdout:write( "launchbox.filter_items(): caching result for query ["..query.."]\n" )
    table.insert( self.filtered_items_cache, query_items )
    self.filtered_items_cache_index[ query ] = #self.filtered_items_cache

    self.filtered_items = query_items
    self:reset_list()

    return true
end

-- -------------------------------------------------------------------------------------------------

function launchbox:start( done_callback )

    --io.stdout:write( "launchbox["..self.name.."].start()\n" )

    local key_timer = nil

    local function show_filter()
        -- temporary replace last list item with filter widget
        local last_pos = #self.list_objects
        self.list_widget:set( last_pos, self.filter_widget )
        if not key_timer then
            key_timer = gtimer.start_new(1.0, function()
                self.list_widget:set( last_pos, self.list_objects[ last_pos ] )
                key_timer = nil
                return false
            end)
        else
            key_timer:again()
        end
    end

    self:set_current_item_focus()

    self.grabber = keygrabber.run( function ( modifiers, key, event )

        if event ~= "press" then
            return false
        end

        -- special keys

        if key == "Escape" or
                ( key == self.config.exit_key and gtable.hasitem( modifiers, self.config.exit_mod ) ) then
            self:stop()
            if done_callback then done_callback() end
            return true
        end

        if key == "Up" then
            self:set_current_item_up()
            return true
        end

        if key == "Down" then
            self:set_current_item_down()
            return true
        end

        if key == "Return" or key == "KP_Enter" then
            if self.current_item < 1 then return end
            local item = self.filtered_items[ self.current_item ]
            if item and item.cmdline then
                self:stop()
                if done_callback then done_callback() end
                io.stdout:write( "launchbox["..self.name.."].start(): launching "..item.name..": "..item.cmdline.."\n")
                spawn( item.cmdline )
            end
            return true
        end

        if key == "F5" then
            io.stdout:write( "launchbox["..self.name.."].start(): pressed [F5]: refreshing item list\n" )
            self:read_all_files()
            return true
        end

        -- normal input
        -- no support for umlauts/unicode at the moment
        -- only accept new key press if items found
        -- everything is lowercase

        if key == "BackSpace" then
            -- instead of manipulating the query string,
            -- we just use the complete previous query string from history
            if #self.query_history > 0 then
                show_filter()
                -- take previous query
                self.query = table.remove( self.query_history )
                --io.stdout:write( "launchbox.start(): pressed [Backspace]: took previous query ["..query.."] from history\n" )
                self.input.text = self.query
                self:filter_items( self.query )
            end
            return true
        end

        if #key == 1 then
            -- umlauts/unicode have 2 chars (#key==2), this would be no problem here,
            -- but string.lower() can't handle unicode, so umlauts in item names
            -- will not be converted to lower case.
            show_filter()
            local new_query = self.query .. string.lower( key )
            --io.stdout:write( "launchbox.start(): new query ["..new_query.."]\n" )
            if self:filter_items( new_query, self.query ) then
                -- insert previous query
                table.insert( self.query_history, self.query )
                --io.stdout:write( "launchbox.start(): pressed ["..key.."]: added previous query ["..query.."] to history\n" )
                self.query = new_query
                self.input.text = new_query
            end
            return true
        end

        return false

    end )

end

-- -------------------------------------------------------------------------------------------------

function launchbox:stop()

    --io.stdout:write( "launchbox["..self.name.."].stop()\n" )

    if self.grabber then
        keygrabber.stop( self.grabber )
        self.grabber = nil
    end

    self:clear_current_item_focus()

end

-- -------------------------------------------------------------------------------------------------

local function create_list_object( config )

    local i = wibox.widget.imagebox()
    -- needed for alignment in case of no icon available
    i.forced_width = config.icon_size
    i.forced_height = config.icon_size

    local n = wibox.widget.textbox()
    n.font = config.font

    local l = wibox.layout.fixed.horizontal( i, n )
    l.fill_space = true
    l.spacing = config.icon_spacing

    local m = wibox.container.margin( ( config.disable_icons and n ) or l )
    m.margins = dpi(2)

    local widget = wibox.container.background( m )
    widget:set_shape( gshape.rounded_rect, dpi(3) )
    widget.fg = config.fg
    widget.bg = nil

    widget.icon = i
    widget.name = n

    widget.set_color = function( self, fg, bg )
        self.fg = fg
        self.bg = bg
    end

    return widget

end


local function create_widget( config )

    --io.stdout:write( "launchbox.create_widget()\n" )

    -- create filter/input widget

    local icon = wibox.widget.imagebox()
    icon.resize = true
    icon.forced_width = config.icon_size
    icon.forced_height = config.icon_size
    --icon.image = utils.lookup_icon("filter")
    icon.image = utils.lookup_icon("preferences-system-search")
    local icon_with_spacing = wibox.container.margin( icon, 0, config.icon_spacing, 0, 0 )

    local input = wibox.widget.textbox()
    input.font = config.font

    local cursor = wibox.widget.textbox( "▍", true )
    cursor.font = config.font

    local filter_widget = wibox.widget {
        widget = wibox.container.margin,
        margins = dpi(2),
        {
            widget = wibox.layout.fixed.horizontal,
            icon_with_spacing, input, cursor
        }
    }

    -- create list widget

    local list_height = config.height - 2 * config.margin
    local avail_rows = math.floor( list_height / config.item_height )
    local remaining_space = list_height - avail_rows * config.item_height
    --io.stdout:write("launchbox.create_widget(): remaining_space = "..tostring(remaining_space).."\n")

    local list_widget = wibox.layout.fixed.vertical()
    if config.width then
        list_widget.forced_width = config.width
        -- otherwise forced_width will be set in prepare_menu_items()
    end
    list_widget.spacing = remaining_space / ( avail_rows - 1 )

    local list_objects = {}
    for i = 1, avail_rows do
        local list_object = create_list_object( config )
        table.insert( list_objects, list_object )
        list_widget:add( list_object )
    end

    -- create main widget

    local widget = wibox.widget {
        widget = wibox.container.margin,
        margins = config.margin,
        color = config.bg,
        {
            widget = wibox.container.background,
            bg = config.bg,
            list_widget
        }
    }

    widget.list_objects = list_objects
    widget.list_widget = list_widget
    widget.input = input
    widget.filter_widget = filter_widget

    return widget

end


local function parse_config( args )

    local args = args or {}
    local config = {}

    config.terminal = args.terminal or "xterm"
    config.disable_cache = args.disable_cache or false
    config.disable_apps = args.disable_apps or false
    config.disable_icons = args.disable_icons or false
    config.doc_dirs = args.doc_dirs
    config.doc_ext = args.doc_ext
    config.bin_dirs = args.bin_dirs
    config.bin_ext = args.bin_ext

    config.fg = args.fg or beautiful.menubar_fg_normal or beautiful.fg_normal
    config.bg = args.bg or beautiful.menubar_bg_normal or beautiful.bg_normal
    config.fg_focus = args.fg_focus or beautiful.menubar_fg_focus or beautiful.fg_focus
    config.bg_focus = args.bg_focus or beautiful.menubar_bg_focus or beautiful.bg_focus
    config.font = args.font or beautiful.font
    config.margin = args.margin or 0

    -- fixed values
    config.icon_spacing = dpi(5)

    -- calculate some properties
    local font_height = helper.get_height( config.font )
    config.item_height = font_height + 2 * dpi(2)
    --io.stdout:write( "launchbox.init(): calculated config.item_height = " .. tostring( config.item_height ) .. "\n" )
    config.icon_size = font_height
    -- if no width is set, it will be calculated in prepare_menu_items()
    config.width = args.forced_width
    -- default height is 10 rows/items
    local rows = args.rows or 10
    config.height = args.forced_height or ( config.item_height * rows + 2 * config.margin )

    -- exit modifier and key
    config.exit_mod = args.exit_mod
    config.exit_key = args.exit_key

    return config

end

-- -------------------------------------------------------------------------------------------------

function launchbox:new( name, args )

    if not name then return nil end

    local config = parse_config( args )
    local _launchbox = create_widget( config )

    _launchbox.name = name
    -- replace special chars from name with "x" to build filename
    _launchbox.item_cache_file = ".cache/awesome/launchbox_" .. string.gsub( name, "%A", "x" )

    _launchbox.config = config

    _launchbox.all_items = {}
    _launchbox.filtered_items = {}
    _launchbox.filtered_items_cache_index = {}
    _launchbox.filtered_items_cache = {}
    _launchbox.no_result_cache = {}

    _launchbox.current_item = 1
    _launchbox.first_item = 1

    _launchbox.query = ""
    _launchbox.query_history = {}

    _launchbox.grabber = nil

    _launchbox.width = config.width
    _launchbox.height = config.height

    setmetatable( _launchbox, self )
    self.__index = self

    if not config.disable_cache and
            helper.file_exists( _launchbox.item_cache_file ) then
        _launchbox:read_all_items_from_cache_file()
    else
        _launchbox:read_all_files()
    end

    return _launchbox

end

-- -------------------------------------------------------------------------------------------------

function launchbox.mt:__call(...)
    return launchbox:new(...)
end

return setmetatable( launchbox, launchbox.mt )
