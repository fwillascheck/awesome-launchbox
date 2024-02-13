# awesome-launchbox
Rofi-like application and document launcher for the Awesome window manager.

![Screenshot with default configuration](screenshot_default.png)

# Installation
Copy the file `launchbox.lua` into the folder `.config/awesome` of your home directory and add the following line at the beginning of your `rc.lua` configuration file.

```lua
local launchbox = require("launchbox")
```

# Minimal configuration example
Create a Launchbox popup with default configuration by adding the following line somewhere at the beginning of your `rc.lua` file.

```lua
local my_launchbox_popup = launchbox("Applications"):create_popup()
```

Add a key binding (in this example `Meta+l`) to your existing `globalkeys`.

```lua
local globalkeys = gears.table.join(
    ...
    awful.key({"Mod4"}, "l", my_launchbox_popup.open, {description="Launchbox", group="launcher"}),
    ...
)
```

# Full configuration example
Coming soon...
