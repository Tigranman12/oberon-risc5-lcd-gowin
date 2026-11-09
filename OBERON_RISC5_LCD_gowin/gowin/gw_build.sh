#!/bin/bash
# Run build.tcl with gw_sh. Sets Gowin's library and Qt paths only for this
# command (like IDE/bin/gowin_ide does), and uses Qt's "offscreen" platform:
# a command-line build needs no window, and without this gw_sh stops with
# "Could not load the Qt platform plugin xcb" or a MESA/GLX error.
# Usage (from OBERON_RISC5_LCD_gowin/gowin):  runlog rf_gowin ./gw_build.sh
cd "$(dirname "$0")" || exit 1
G=/tools/Gowin/IDE
export LD_LIBRARY_PATH=$G/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export QT_QPA_PLATFORM_PLUGIN_PATH=$G/plugins/qt/platforms
export QT_PLUGIN_PATH=$G/plugins
export QT_QPA_PLATFORM=offscreen
# Qt 5's offscreen plugin still opens X11/GLX when DISPLAY is set, which loads
# the system Mesa driver; that needs a newer libstdc++ than Gowin's
# (GLIBCXX_3.4.29). Without a display it renders in software only.
unset DISPLAY WAYLAND_DISPLAY
exec $G/bin/gw_sh build.tcl
