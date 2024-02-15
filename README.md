# awesome-launchbox
Rofi-like application and document launcher for the Awesome 4.x window manager.

Launchbox is a multi-purpose launcher with a minimal design and high performance which can be used as stand-alone window/popup or embedded into more complex parent widgets, e.g. dashboards.

![Screenshot with default configuration](screenshot_default.png)

The screenshot shows the launcher with default configuration.
Used theme font: *Roboto*, icons: *Papirus* and colors: ...

![Screenshot with filter](screenshot_filter.png)

The filter input field is only displayed during typing as an overlay at the last list position.

## Key bindigs
- Use the cursor keys `Up` and `Down` for navigation and press `Enter` to launch the selected item.
- Press `Esc` to abort. This normally closes the window. You can also use your additional configured exit mod+key.
- `F5` updates/refreshes the list (and cache) if you have added or removed applications or documents.
- Just begin typing to start and continue filtering for item names, press `Backspace` to delete the last char from the input field.

## Features
- Multiple instances for different purposes/configurations.
- Can be used as embedded widget or stand-alone.
- Supports desktop applications, documents (via xdg-open) and terminal-based executables, with multiple include/exclude dirs and file extensions.
- File cache for faster startup.
- In-memory caching of filter results.
- Icons can be disabled to improve performance and for the most-minimal look.
- Sizes are calculated automatically from the font size.
- Uses existing theme-variables for colors, borders and font.
- Live update of filter results during typing.
- Minimal redraws, only when really needed.

## Non-features
- No dynamic list update on addition/removal of applications or documents.
- No file/MIME-type based document icons.
- No application categories.
- No GUI-based configuration options.
- No mouse support.

# Installation
Copy the file `launchbox.lua` into the folder `.config/awesome` of your home directory and add the following line at the beginning of your `rc.lua` configuration file.

```lua
local launchbox = require("launchbox")
```

# Minimal configuration example
Create a Launchbox popup with default configuration by adding the following line somewhere in your `rc.lua` file.

```lua
local my_launchbox_popup = launchbox("My Applications"):create_popup()
```

Add a key binding (in this example `Super+l`) to your existing `globalkeys` definition.

```lua
local globalkeys = gears.table.join(
    ...
    awful.key({"Mod4"}, "l", my_launchbox_popup.open, {description="Launchbox", group="launcher"}),
    ...
)
```

This should open a basic launcher popup similar (depending on your applications) to the screenshots above.

# Full configuration example
First we create the launcher widget object with all possible configuration options.

```lua
local my_launchbox_widget = launchbox("Example", {
    terminal = "urxvt",
        -- used to launch terminal-based applications, default "xterm"
    disable_cache = false,
        -- disable file cache for menu items, true/false, default false
    disable_apps = false,
        -- disable desktop applications, true/false, default false
    disable_icons = false,
        -- true/false, default false
    doc_dirs = { "Documents/Manuals", "Other", "-Backup" },
        -- list of document dirs, use "-" to exclude sub dirs
    doc_ext = { "docx", "pdf" },
        -- list of file extensions, default all
    bin_dirs = { "/usr/bin", "own_scripts" },
        -- list of terminal-based executable dirs, use "-" to exclude sub dirs
    --bin_ext = nil,
        -- list of file extensions, default all
    fg = "#ffffff",
        -- color, default beautiful.menubar_fg_normal or beautiful.fg_normal
    bg = "#000000",
        -- color, default beautiful.menubar_bg_normal or beautiful.bg_normal
    fg_focus = "#000000",
        -- color, default beautiful.menubar_fg_focus or beautiful.fg_focus
    bg_focus = "#ffffff",
        -- color, default beautiful.menubar_bg_focus or beautiful.bg_focus
    font = "Roboto 12",
        -- default beautiful.font
    margin = 10,
        -- margin around the widget, default 0
    --forced_width = 200,
        -- default auto
    rows = 10,
        -- number of menu items to display, default 10
    --forced_height = 400,
        -- if set, rows parameter is ignored, default auto
    exit_mod = "Mod4", exit_key = "l"
        -- can be set to match globalkeys to implement toggling
})

```

Then we create a popup object for that widget with all possible configuration options.


```lua
local my_launchbox_popup = my_launchbox_widget:create_popup({
    border_width = 1,
        -- default beautiful.menubar_border_width or beautiful.border_width or 0
    border_color = "#ffffff",
        -- color, default beautiful.menubar_border_color or beautiful.border_normal
    position = "top_left",
        -- allowed values for awful.placement.align(), default "centered"
    padding = 10
        -- distance from screen border, default 0
})
```

You can then use the functions `open()`, `close()` or `toggle()` of the popup object in a key binding or button to control its visibility.

## Embedding example

The following example shows how to use the launcher widget in a parent wibox. This is very similar to what is done in the `launchbox:create_popup()` function. We are re-using the my_launchbox_widget object from the example above.

```lua
local my_wibox = wibox({
    width   = my_launchbox_widget.width,
    height  = my_launchbox_widget.height,
    widget  = my_launchbox_widget,
    visible = false
})
```

We then need a function to show the wibox and to start the launcher. The list initialization and the start are two separate functions, because in cases where the wibox should be permanently visible, you will need to initialize the list only once, but you may want to start and stop the launcher depending on "mouse::enter" and "mouse::leave" events. The start function has an optional parameter to specify a "done-callback" function that is called when the launcher is aborted or an item has been executed. In this example, we simply hide the wibox.

```lua
my_wibox.open = function()
    my_launchbox_widget:init_list()
    my_launchbox_widget:start( function() my_wibox.visible = false end )
    my_wibox.visible = true
end
```

We can also add a function to close the wibox and to stop the launcher. This is not really needed for this example, because the stop function is called by the launcher itself internally on abort or execution, and we specified a callback to hide the wibox. But the close function could be used to trigger the stop externally.

```lua
my_wibox.close = function()
    my_launchbox_widget:stop()
    my_wibox.visible = false
end
```

## Function overview
Coming soon...
