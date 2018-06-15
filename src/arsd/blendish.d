/*
Blendish - Blender 2.5 UI based theming functions for NanoVega

Copyright (c) 2014 Leonard Ritter <leonard.ritter@duangle.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/
// Fork developement, feature integration and new bugs:
// Ketmar // Invisible Vector <ketmar@ketmar.no-ip.org>
/**

Revision 6 (2014-09-21)

Summary

Blendish is a small collection of drawing functions for NanoVega, designed to
replicate the look of the Blender 2.5+ User Interface. You can use these
functions to theme your UI library. Several metric constants for faithful
reproduction are also included.

Blendish supports the original Blender icon sheet; As the licensing of Blenders
icons is unclear, they are not included in Blendishes repository, but a SVG
template, "icons_template.svg" is provided, which you can use to build your own
icon sheet.

To use icons, you must first load the icon sheet using one of the
`nvgCreateImage*()` functions and then pass the image handle to `bndSetIconImage()`;
otherwise, no icons will be drawn. See `bndSetIconImage()` for more information.

Blendish will not render text until a suitable UI font has been passed to
`bndSetFont()` has been called. See `bndSetFont()` for more information.


Drawbacks

There is no support for varying dpi resolutions yet. The library is hardcoded
to the equivalent of 72 dpi in the Blender system settings.

Support for label truncation is missing. Text rendering breaks when widgets are
too short to contain their labels.
*/
module arsd.blendish;
private:

import arsd.nanovega;
version(aliced) {
  import iv.meta;
} else {
  private alias usize = size_t;
  // i fear phobos!
  private template Unqual(T) {
         static if (is(T U ==          immutable U)) alias Unqual = U;
    else static if (is(T U == shared inout const U)) alias Unqual = U;
    else static if (is(T U == shared inout       U)) alias Unqual = U;
    else static if (is(T U == shared       const U)) alias Unqual = U;
    else static if (is(T U == shared             U)) alias Unqual = U;
    else static if (is(T U ==        inout const U)) alias Unqual = U;
    else static if (is(T U ==        inout       U)) alias Unqual = U;
    else static if (is(T U ==              const U)) alias Unqual = U;
    else alias Unqual = T;
  }
  private template isAnyCharType(T, bool unqual=false) {
    static if (unqual) private alias UT = Unqual!T; else private alias UT = T;
    enum isAnyCharType = is(UT == char) || is(UT == wchar) || is(UT == dchar);
  }
  private template isWideCharType(T, bool unqual=false) {
    static if (unqual) private alias UT = Unqual!T; else private alias UT = T;
    enum isWideCharType = is(UT == wchar) || is(UT == dchar);
  }
}

nothrow @trusted @nogc:


/** describes the theme used to draw a single widget or widget box;
 * these values correspond to the same values that can be retrieved from
 * the Theme panel in the Blender preferences */
public struct BNDwidgetTheme {
  /// theme name
  string name;
  /// color of widget box outline
  NVGColor outlineColor;
  /// color of widget item (meaning changes depending on class)
  NVGColor itemColor;
  /// fill color of widget box
  NVGColor innerColor;
  /// fill color of widget box when active
  NVGColor innerSelectedColor;
  /// color of text label
  NVGColor textColor;
  /// color of text label when active
  NVGColor textSelectedColor;
  /// delta modifier for upper part of gradient (-100 to 100)
  int shadeTop;
  /// delta modifier for lower part of gradient (-100 to 100)
  int shadeDown;
  /// color of hovered text (if transparent, use `textSelectedColor`)
  NVGColor textHoverColor;
  /// color of caret for text field (if transparent, use `textColor`)
  NVGColor textCaretColor;
}

/// describes the theme used to draw nodes
public struct BNDnodeTheme {
  /// theme name
  string name;
  /// inner color of selected node (and downarrow)
  NVGColor nodeSelectedColor;
  /// outline of wires
  NVGColor wiresColor;
  /// color of text label when active
  NVGColor textSelectedColor;

  /// inner color of active node (and dragged wire)
  NVGColor activeNodeColor;
  /// color of selected wire
  NVGColor wireSelectColor;
  /// color of background of node
  NVGColor nodeBackdropColor;

  /// how much a noodle curves (0 to 10)
  int noodleCurving;
}

/// describes the theme used to draw widgets
public struct BNDtheme {
  /// theme name
  string name;
  /// the background color of panels and windows
  NVGColor backgroundColor;
  /// theme for labels
  BNDwidgetTheme regularTheme;
  /// theme for tool buttons
  BNDwidgetTheme toolTheme;
  /// theme for radio buttons
  BNDwidgetTheme radioTheme;
  /// theme for text fields
  BNDwidgetTheme textFieldTheme;
  /// theme for option buttons (checkboxes)
  BNDwidgetTheme optionTheme;
  /// theme for choice buttons (comboboxes)
  /// Blender calls them "menu buttons"
  BNDwidgetTheme choiceTheme;
  /// theme for number fields
  BNDwidgetTheme numberFieldTheme;
  /// theme for slider controls
  BNDwidgetTheme sliderTheme;
  /// theme for scrollbars
  BNDwidgetTheme scrollBarTheme;
  /// theme for tooltips
  BNDwidgetTheme tooltipTheme;
  /// theme for menu backgrounds
  BNDwidgetTheme menuTheme;
  /// theme for menu items
  BNDwidgetTheme menuItemTheme;
  /// theme for nodes
  BNDnodeTheme nodeTheme;
}

/// how text on a control is aligned
public alias BNDtextAlignment = int;
/// how text on a control is aligned (values)
public enum /*BNDtextAlignment*/ : int {
  BND_LEFT = 0, /// left
  BND_CENTER, /// center
  BND_RIGHT, /// right
}

/// states altering the styling of a widget
public alias BNDwidgetState = int;
/// states altering the styling of a widget (values)
public enum /*BNDwidgetState*/ : int {
  /// not interacting
  BND_DEFAULT = 0,
  /// the mouse is hovering over the control
  BND_HOVER,
  /// the widget is activated (pressed) or in an active state (toggled)
  BND_ACTIVE,
}

/// flags indicating which corners are sharp (for grouping widgets)
public alias BNDcornerFlags = int;
public enum /*BNDcornerFlags*/ : int {
  /// all corners are round
  BND_CORNER_NONE = 0,
  /// sharp top left corner
  BND_CORNER_TOP_LEFT = 1,
  /// sharp top right corner
  BND_CORNER_TOP_RIGHT = 2,
  /// sharp bottom right corner
  BND_CORNER_DOWN_RIGHT = 4,
  /// sharp bottom left corner
  BND_CORNER_DOWN_LEFT = 8,
  /// all corners are sharp; you can invert a set of flags using ^= BND_CORNER_ALL
  BND_CORNER_ALL = 0xF,
  /// top border is sharp
  BND_CORNER_TOP = 3,
  /// bottom border is sharp
  BND_CORNER_DOWN = 0xC,
  /// left border is sharp
  BND_CORNER_LEFT = 9,
  /// right border is sharp
  BND_CORNER_RIGHT = 6,
}

/** build an icon ID from two coordinates into the icon sheet, where
 * (0, 0) designates the upper-leftmost icon, (1, 0) the one right next to it,
 * and so on. */
public enum BND_ICONID(int x, int y) = ((x)|((y)<<8));

/// alpha of disabled widget groups; can be used in conjunction with nvgGlobalAlpha()
public __gshared float BND_DISABLED_ALPHA = 0.5;

public __gshared {
  /// default widget height
  int BND_WIDGET_HEIGHT = 21;
  /// default toolbutton width (if icon only)
  int BND_TOOL_WIDTH = 20;

  /// default radius of node ports
  int BND_NODE_PORT_RADIUS = 5;
  /// top margin of node content
  int BND_NODE_MARGIN_TOP = 25;
  /// bottom margin of node content
  int BND_NODE_MARGIN_DOWN = 5;
  /// left and right margin of node content
  int BND_NODE_MARGIN_SIDE = 10;
  /// height of node title bar
  int BND_NODE_TITLE_HEIGHT = 20;
  /// width of node title arrow click area
  int BND_NODE_ARROW_AREA_WIDTH = 20;

  /// size of splitter corner click area
  int BND_SPLITTER_AREA_SIZE = 12;

  /// width of vertical scrollbar
  int BND_SCROLLBAR_WIDTH = 13;
  /// height of horizontal scrollbar
  int BND_SCROLLBAR_HEIGHT = 14;

  /// default vertical spacing
  int BND_VSPACING = 1;
  /// default vertical spacing between groups
  int BND_VSPACING_GROUP = 8;
  /// default horizontal spacing
  int BND_HSPACING = 8;
}

public alias BNDicon = int;
public enum /*BNDicon*/ {
  BND_ICON_NONE = BND_ICONID!(0, 29),
  BND_ICON_QUESTION = BND_ICONID!(1, 29),
  BND_ICON_ERROR = BND_ICONID!(2, 29),
  BND_ICON_CANCEL = BND_ICONID!(3, 29),
  BND_ICON_TRIA_RIGHT = BND_ICONID!(4, 29),
  BND_ICON_TRIA_DOWN = BND_ICONID!(5, 29),
  BND_ICON_TRIA_LEFT = BND_ICONID!(6, 29),
  BND_ICON_TRIA_UP = BND_ICONID!(7, 29),
  BND_ICON_ARROW_LEFTRIGHT = BND_ICONID!(8, 29),
  BND_ICON_PLUS = BND_ICONID!(9, 29),
  BND_ICON_DISCLOSURE_TRI_DOWN = BND_ICONID!(10, 29),
  BND_ICON_DISCLOSURE_TRI_RIGHT = BND_ICONID!(11, 29),
  BND_ICON_RADIOBUT_OFF = BND_ICONID!(12, 29),
  BND_ICON_RADIOBUT_ON = BND_ICONID!(13, 29),
  BND_ICON_MENU_PANEL = BND_ICONID!(14, 29),
  BND_ICON_BLENDER = BND_ICONID!(15, 29),
  BND_ICON_GRIP = BND_ICONID!(16, 29),
  BND_ICON_DOT = BND_ICONID!(17, 29),
  BND_ICON_COLLAPSEMENU = BND_ICONID!(18, 29),
  BND_ICON_X = BND_ICONID!(19, 29),
  BND_ICON_GO_LEFT = BND_ICONID!(21, 29),
  BND_ICON_PLUG = BND_ICONID!(22, 29),
  BND_ICON_UI = BND_ICONID!(23, 29),
  BND_ICON_NODE = BND_ICONID!(24, 29),
  BND_ICON_NODE_SEL = BND_ICONID!(25, 29),
}
public enum /*BNDicon*/ {
  BND_ICON_FULLSCREEN = BND_ICONID!(0, 28),
  BND_ICON_SPLITSCREEN = BND_ICONID!(1, 28),
  BND_ICON_RIGHTARROW_THIN = BND_ICONID!(2, 28),
  BND_ICON_BORDERMOVE = BND_ICONID!(3, 28),
  BND_ICON_VIEWZOOM = BND_ICONID!(4, 28),
  BND_ICON_ZOOMIN = BND_ICONID!(5, 28),
  BND_ICON_ZOOMOUT = BND_ICONID!(6, 28),
  BND_ICON_PANEL_CLOSE = BND_ICONID!(7, 28),
  BND_ICON_COPY_ID = BND_ICONID!(8, 28),
  BND_ICON_EYEDROPPER = BND_ICONID!(9, 28),
  BND_ICON_LINK_AREA = BND_ICONID!(10, 28),
  BND_ICON_AUTO = BND_ICONID!(11, 28),
  BND_ICON_CHECKBOX_DEHLT = BND_ICONID!(12, 28),
  BND_ICON_CHECKBOX_HLT = BND_ICONID!(13, 28),
  BND_ICON_UNLOCKED = BND_ICONID!(14, 28),
  BND_ICON_LOCKED = BND_ICONID!(15, 28),
  BND_ICON_UNPINNED = BND_ICONID!(16, 28),
  BND_ICON_PINNED = BND_ICONID!(17, 28),
  BND_ICON_SCREEN_BACK = BND_ICONID!(18, 28),
  BND_ICON_RIGHTARROW = BND_ICONID!(19, 28),
  BND_ICON_DOWNARROW_HLT = BND_ICONID!(20, 28),
  BND_ICON_DOTSUP = BND_ICONID!(21, 28),
  BND_ICON_DOTSDOWN = BND_ICONID!(22, 28),
  BND_ICON_LINK = BND_ICONID!(23, 28),
  BND_ICON_INLINK = BND_ICONID!(24, 28),
  BND_ICON_PLUGIN = BND_ICONID!(25, 28),
}
public enum /*BNDicon*/ {
  BND_ICON_HELP = BND_ICONID!(0, 27),
  BND_ICON_GHOST_ENABLED = BND_ICONID!(1, 27),
  BND_ICON_COLOR = BND_ICONID!(2, 27),
  BND_ICON_LINKED = BND_ICONID!(3, 27),
  BND_ICON_UNLINKED = BND_ICONID!(4, 27),
  BND_ICON_HAND = BND_ICONID!(5, 27),
  BND_ICON_ZOOM_ALL = BND_ICONID!(6, 27),
  BND_ICON_ZOOM_SELECTED = BND_ICONID!(7, 27),
  BND_ICON_ZOOM_PREVIOUS = BND_ICONID!(8, 27),
  BND_ICON_ZOOM_IN = BND_ICONID!(9, 27),
  BND_ICON_ZOOM_OUT = BND_ICONID!(10, 27),
  BND_ICON_RENDER_REGION = BND_ICONID!(11, 27),
  BND_ICON_BORDER_RECT = BND_ICONID!(12, 27),
  BND_ICON_BORDER_LASSO = BND_ICONID!(13, 27),
  BND_ICON_FREEZE = BND_ICONID!(14, 27),
  BND_ICON_STYLUS_PRESSURE = BND_ICONID!(15, 27),
  BND_ICON_GHOST_DISABLED = BND_ICONID!(16, 27),
  BND_ICON_NEW = BND_ICONID!(17, 27),
  BND_ICON_FILE_TICK = BND_ICONID!(18, 27),
  BND_ICON_QUIT = BND_ICONID!(19, 27),
  BND_ICON_URL = BND_ICONID!(20, 27),
  BND_ICON_RECOVER_LAST = BND_ICONID!(21, 27),
  BND_ICON_FULLSCREEN_ENTER = BND_ICONID!(23, 27),
  BND_ICON_FULLSCREEN_EXIT = BND_ICONID!(24, 27),
  BND_ICON_BLANK1 = BND_ICONID!(25, 27),
}
public enum /*BNDicon*/ {
  BND_ICON_LAMP = BND_ICONID!(0, 26),
  BND_ICON_MATERIAL = BND_ICONID!(1, 26),
  BND_ICON_TEXTURE = BND_ICONID!(2, 26),
  BND_ICON_ANIM = BND_ICONID!(3, 26),
  BND_ICON_WORLD = BND_ICONID!(4, 26),
  BND_ICON_SCENE = BND_ICONID!(5, 26),
  BND_ICON_EDIT = BND_ICONID!(6, 26),
  BND_ICON_GAME = BND_ICONID!(7, 26),
  BND_ICON_RADIO = BND_ICONID!(8, 26),
  BND_ICON_SCRIPT = BND_ICONID!(9, 26),
  BND_ICON_PARTICLES = BND_ICONID!(10, 26),
  BND_ICON_PHYSICS = BND_ICONID!(11, 26),
  BND_ICON_SPEAKER = BND_ICONID!(12, 26),
  BND_ICON_TEXTURE_SHADED = BND_ICONID!(13, 26),
}
public enum /*BNDicon*/ {
  BND_ICON_VIEW3D = BND_ICONID!(0, 25),
  BND_ICON_IPO = BND_ICONID!(1, 25),
  BND_ICON_OOPS = BND_ICONID!(2, 25),
  BND_ICON_BUTS = BND_ICONID!(3, 25),
  BND_ICON_FILESEL = BND_ICONID!(4, 25),
  BND_ICON_IMAGE_COL = BND_ICONID!(5, 25),
  BND_ICON_INFO = BND_ICONID!(6, 25),
  BND_ICON_SEQUENCE = BND_ICONID!(7, 25),
  BND_ICON_TEXT = BND_ICONID!(8, 25),
  BND_ICON_IMASEL = BND_ICONID!(9, 25),
  BND_ICON_SOUND = BND_ICONID!(10, 25),
  BND_ICON_ACTION = BND_ICONID!(11, 25),
  BND_ICON_NLA = BND_ICONID!(12, 25),
  BND_ICON_SCRIPTWIN = BND_ICONID!(13, 25),
  BND_ICON_TIME = BND_ICONID!(14, 25),
  BND_ICON_NODETREE = BND_ICONID!(15, 25),
  BND_ICON_LOGIC = BND_ICONID!(16, 25),
  BND_ICON_CONSOLE = BND_ICONID!(17, 25),
  BND_ICON_PREFERENCES = BND_ICONID!(18, 25),
  BND_ICON_CLIP = BND_ICONID!(19, 25),
  BND_ICON_ASSET_MANAGER = BND_ICONID!(20, 25),
}
public enum /*BNDicon*/ {
  BND_ICON_OBJECT_DATAMODE = BND_ICONID!(0, 24),
  BND_ICON_EDITMODE_HLT = BND_ICONID!(1, 24),
  BND_ICON_FACESEL_HLT = BND_ICONID!(2, 24),
  BND_ICON_VPAINT_HLT = BND_ICONID!(3, 24),
  BND_ICON_TPAINT_HLT = BND_ICONID!(4, 24),
  BND_ICON_WPAINT_HLT = BND_ICONID!(5, 24),
  BND_ICON_SCULPTMODE_HLT = BND_ICONID!(6, 24),
  BND_ICON_POSE_HLT = BND_ICONID!(7, 24),
  BND_ICON_PARTICLEMODE = BND_ICONID!(8, 24),
  BND_ICON_LIGHTPAINT = BND_ICONID!(9, 24),
}
public enum /*BNDicon*/ {
  BND_ICON_SCENE_DATA = BND_ICONID!(0, 23),
  BND_ICON_RENDERLAYERS = BND_ICONID!(1, 23),
  BND_ICON_WORLD_DATA = BND_ICONID!(2, 23),
  BND_ICON_OBJECT_DATA = BND_ICONID!(3, 23),
  BND_ICON_MESH_DATA = BND_ICONID!(4, 23),
  BND_ICON_CURVE_DATA = BND_ICONID!(5, 23),
  BND_ICON_META_DATA = BND_ICONID!(6, 23),
  BND_ICON_LATTICE_DATA = BND_ICONID!(7, 23),
  BND_ICON_LAMP_DATA = BND_ICONID!(8, 23),
  BND_ICON_MATERIAL_DATA = BND_ICONID!(9, 23),
  BND_ICON_TEXTURE_DATA = BND_ICONID!(10, 23),
  BND_ICON_ANIM_DATA = BND_ICONID!(11, 23),
  BND_ICON_CAMERA_DATA = BND_ICONID!(12, 23),
  BND_ICON_PARTICLE_DATA = BND_ICONID!(13, 23),
  BND_ICON_LIBRARY_DATA_DIRECT = BND_ICONID!(14, 23),
  BND_ICON_GROUP = BND_ICONID!(15, 23),
  BND_ICON_ARMATURE_DATA = BND_ICONID!(16, 23),
  BND_ICON_POSE_DATA = BND_ICONID!(17, 23),
  BND_ICON_BONE_DATA = BND_ICONID!(18, 23),
  BND_ICON_CONSTRAINT = BND_ICONID!(19, 23),
  BND_ICON_SHAPEKEY_DATA = BND_ICONID!(20, 23),
  BND_ICON_CONSTRAINT_BONE = BND_ICONID!(21, 23),
  BND_ICON_CAMERA_STEREO = BND_ICONID!(22, 23),
  BND_ICON_PACKAGE = BND_ICONID!(23, 23),
  BND_ICON_UGLYPACKAGE = BND_ICONID!(24, 23),
}
public enum /*BNDicon*/ {
  BND_ICON_BRUSH_DATA = BND_ICONID!(0, 22),
  BND_ICON_IMAGE_DATA = BND_ICONID!(1, 22),
  BND_ICON_FILE = BND_ICONID!(2, 22),
  BND_ICON_FCURVE = BND_ICONID!(3, 22),
  BND_ICON_FONT_DATA = BND_ICONID!(4, 22),
  BND_ICON_RENDER_RESULT = BND_ICONID!(5, 22),
  BND_ICON_SURFACE_DATA = BND_ICONID!(6, 22),
  BND_ICON_EMPTY_DATA = BND_ICONID!(7, 22),
  BND_ICON_SETTINGS = BND_ICONID!(8, 22),
  BND_ICON_RENDER_ANIMATION = BND_ICONID!(9, 22),
  BND_ICON_RENDER_STILL = BND_ICONID!(10, 22),
  BND_ICON_BOIDS = BND_ICONID!(12, 22),
  BND_ICON_STRANDS = BND_ICONID!(13, 22),
  BND_ICON_LIBRARY_DATA_INDIRECT = BND_ICONID!(14, 22),
  BND_ICON_GREASEPENCIL = BND_ICONID!(15, 22),
  BND_ICON_LINE_DATA = BND_ICONID!(16, 22),
  BND_ICON_GROUP_BONE = BND_ICONID!(18, 22),
  BND_ICON_GROUP_VERTEX = BND_ICONID!(19, 22),
  BND_ICON_GROUP_VCOL = BND_ICONID!(20, 22),
  BND_ICON_GROUP_UVS = BND_ICONID!(21, 22),
  BND_ICON_RNA = BND_ICONID!(24, 22),
  BND_ICON_RNA_ADD = BND_ICONID!(25, 22),
}
public enum /*BNDicon*/ {
  BND_ICON_OUTLINER_OB_EMPTY = BND_ICONID!(0, 20),
  BND_ICON_OUTLINER_OB_MESH = BND_ICONID!(1, 20),
  BND_ICON_OUTLINER_OB_CURVE = BND_ICONID!(2, 20),
  BND_ICON_OUTLINER_OB_LATTICE = BND_ICONID!(3, 20),
  BND_ICON_OUTLINER_OB_META = BND_ICONID!(4, 20),
  BND_ICON_OUTLINER_OB_LAMP = BND_ICONID!(5, 20),
  BND_ICON_OUTLINER_OB_CAMERA = BND_ICONID!(6, 20),
  BND_ICON_OUTLINER_OB_ARMATURE = BND_ICONID!(7, 20),
  BND_ICON_OUTLINER_OB_FONT = BND_ICONID!(8, 20),
  BND_ICON_OUTLINER_OB_SURFACE = BND_ICONID!(9, 20),
  BND_ICON_OUTLINER_OB_SPEAKER = BND_ICONID!(10, 20),
  BND_ICON_RESTRICT_VIEW_OFF = BND_ICONID!(19, 20),
  BND_ICON_RESTRICT_VIEW_ON = BND_ICONID!(20, 20),
  BND_ICON_RESTRICT_SELECT_OFF = BND_ICONID!(21, 20),
  BND_ICON_RESTRICT_SELECT_ON = BND_ICONID!(22, 20),
  BND_ICON_RESTRICT_RENDER_OFF = BND_ICONID!(23, 20),
  BND_ICON_RESTRICT_RENDER_ON = BND_ICONID!(24, 20),
}
public enum /*BNDicon*/ {
  BND_ICON_OUTLINER_DATA_EMPTY = BND_ICONID!(0, 19),
  BND_ICON_OUTLINER_DATA_MESH = BND_ICONID!(1, 19),
  BND_ICON_OUTLINER_DATA_CURVE = BND_ICONID!(2, 19),
  BND_ICON_OUTLINER_DATA_LATTICE = BND_ICONID!(3, 19),
  BND_ICON_OUTLINER_DATA_META = BND_ICONID!(4, 19),
  BND_ICON_OUTLINER_DATA_LAMP = BND_ICONID!(5, 19),
  BND_ICON_OUTLINER_DATA_CAMERA = BND_ICONID!(6, 19),
  BND_ICON_OUTLINER_DATA_ARMATURE = BND_ICONID!(7, 19),
  BND_ICON_OUTLINER_DATA_FONT = BND_ICONID!(8, 19),
  BND_ICON_OUTLINER_DATA_SURFACE = BND_ICONID!(9, 19),
  BND_ICON_OUTLINER_DATA_SPEAKER = BND_ICONID!(10, 19),
  BND_ICON_OUTLINER_DATA_POSE = BND_ICONID!(11, 19),
}
public enum /*BNDicon*/ {
  BND_ICON_MESH_PLANE = BND_ICONID!(0, 18),
  BND_ICON_MESH_CUBE = BND_ICONID!(1, 18),
  BND_ICON_MESH_CIRCLE = BND_ICONID!(2, 18),
  BND_ICON_MESH_UVSPHERE = BND_ICONID!(3, 18),
  BND_ICON_MESH_ICOSPHERE = BND_ICONID!(4, 18),
  BND_ICON_MESH_GRID = BND_ICONID!(5, 18),
  BND_ICON_MESH_MONKEY = BND_ICONID!(6, 18),
  BND_ICON_MESH_CYLINDER = BND_ICONID!(7, 18),
  BND_ICON_MESH_TORUS = BND_ICONID!(8, 18),
  BND_ICON_MESH_CONE = BND_ICONID!(9, 18),
  BND_ICON_LAMP_POINT = BND_ICONID!(12, 18),
  BND_ICON_LAMP_SUN = BND_ICONID!(13, 18),
  BND_ICON_LAMP_SPOT = BND_ICONID!(14, 18),
  BND_ICON_LAMP_HEMI = BND_ICONID!(15, 18),
  BND_ICON_LAMP_AREA = BND_ICONID!(16, 18),
  BND_ICON_META_EMPTY = BND_ICONID!(19, 18),
  BND_ICON_META_PLANE = BND_ICONID!(20, 18),
  BND_ICON_META_CUBE = BND_ICONID!(21, 18),
  BND_ICON_META_BALL = BND_ICONID!(22, 18),
  BND_ICON_META_ELLIPSOID = BND_ICONID!(23, 18),
  BND_ICON_META_CAPSULE = BND_ICONID!(24, 18),
}
public enum /*BNDicon*/ {
  BND_ICON_SURFACE_NCURVE = BND_ICONID!(0, 17),
  BND_ICON_SURFACE_NCIRCLE = BND_ICONID!(1, 17),
  BND_ICON_SURFACE_NSURFACE = BND_ICONID!(2, 17),
  BND_ICON_SURFACE_NCYLINDER = BND_ICONID!(3, 17),
  BND_ICON_SURFACE_NSPHERE = BND_ICONID!(4, 17),
  BND_ICON_SURFACE_NTORUS = BND_ICONID!(5, 17),
  BND_ICON_CURVE_BEZCURVE = BND_ICONID!(9, 17),
  BND_ICON_CURVE_BEZCIRCLE = BND_ICONID!(10, 17),
  BND_ICON_CURVE_NCURVE = BND_ICONID!(11, 17),
  BND_ICON_CURVE_NCIRCLE = BND_ICONID!(12, 17),
  BND_ICON_CURVE_PATH = BND_ICONID!(13, 17),
  BND_ICON_COLOR_RED = BND_ICONID!(19, 17),
  BND_ICON_COLOR_GREEN = BND_ICONID!(20, 17),
  BND_ICON_COLOR_BLUE = BND_ICONID!(21, 17),
}
public enum /*BNDicon*/ {
  BND_ICON_FORCE_FORCE = BND_ICONID!(0, 16),
  BND_ICON_FORCE_WIND = BND_ICONID!(1, 16),
  BND_ICON_FORCE_VORTEX = BND_ICONID!(2, 16),
  BND_ICON_FORCE_MAGNETIC = BND_ICONID!(3, 16),
  BND_ICON_FORCE_HARMONIC = BND_ICONID!(4, 16),
  BND_ICON_FORCE_CHARGE = BND_ICONID!(5, 16),
  BND_ICON_FORCE_LENNARDJONES = BND_ICONID!(6, 16),
  BND_ICON_FORCE_TEXTURE = BND_ICONID!(7, 16),
  BND_ICON_FORCE_CURVE = BND_ICONID!(8, 16),
  BND_ICON_FORCE_BOID = BND_ICONID!(9, 16),
  BND_ICON_FORCE_TURBULENCE = BND_ICONID!(10, 16),
  BND_ICON_FORCE_DRAG = BND_ICONID!(11, 16),
  BND_ICON_FORCE_SMOKEFLOW = BND_ICONID!(12, 16),
}
public enum /*BNDicon*/ {
  BND_ICON_MODIFIER = BND_ICONID!(0, 12),
  BND_ICON_MOD_WAVE = BND_ICONID!(1, 12),
  BND_ICON_MOD_BUILD = BND_ICONID!(2, 12),
  BND_ICON_MOD_DECIM = BND_ICONID!(3, 12),
  BND_ICON_MOD_MIRROR = BND_ICONID!(4, 12),
  BND_ICON_MOD_SOFT = BND_ICONID!(5, 12),
  BND_ICON_MOD_SUBSURF = BND_ICONID!(6, 12),
  BND_ICON_HOOK = BND_ICONID!(7, 12),
  BND_ICON_MOD_PHYSICS = BND_ICONID!(8, 12),
  BND_ICON_MOD_PARTICLES = BND_ICONID!(9, 12),
  BND_ICON_MOD_BOOLEAN = BND_ICONID!(10, 12),
  BND_ICON_MOD_EDGESPLIT = BND_ICONID!(11, 12),
  BND_ICON_MOD_ARRAY = BND_ICONID!(12, 12),
  BND_ICON_MOD_UVPROJECT = BND_ICONID!(13, 12),
  BND_ICON_MOD_DISPLACE = BND_ICONID!(14, 12),
  BND_ICON_MOD_CURVE = BND_ICONID!(15, 12),
  BND_ICON_MOD_LATTICE = BND_ICONID!(16, 12),
  BND_ICON_CONSTRAINT_DATA = BND_ICONID!(17, 12),
  BND_ICON_MOD_ARMATURE = BND_ICONID!(18, 12),
  BND_ICON_MOD_SHRINKWRAP = BND_ICONID!(19, 12),
  BND_ICON_MOD_CAST = BND_ICONID!(20, 12),
  BND_ICON_MOD_MESHDEFORM = BND_ICONID!(21, 12),
  BND_ICON_MOD_BEVEL = BND_ICONID!(22, 12),
  BND_ICON_MOD_SMOOTH = BND_ICONID!(23, 12),
  BND_ICON_MOD_SIMPLEDEFORM = BND_ICONID!(24, 12),
  BND_ICON_MOD_MASK = BND_ICONID!(25, 12),
}
public enum /*BNDicon*/ {
  BND_ICON_MOD_CLOTH = BND_ICONID!(0, 11),
  BND_ICON_MOD_EXPLODE = BND_ICONID!(1, 11),
  BND_ICON_MOD_FLUIDSIM = BND_ICONID!(2, 11),
  BND_ICON_MOD_MULTIRES = BND_ICONID!(3, 11),
  BND_ICON_MOD_SMOKE = BND_ICONID!(4, 11),
  BND_ICON_MOD_SOLIDIFY = BND_ICONID!(5, 11),
  BND_ICON_MOD_SCREW = BND_ICONID!(6, 11),
  BND_ICON_MOD_VERTEX_WEIGHT = BND_ICONID!(7, 11),
  BND_ICON_MOD_DYNAMICPAINT = BND_ICONID!(8, 11),
  BND_ICON_MOD_REMESH = BND_ICONID!(9, 11),
  BND_ICON_MOD_OCEAN = BND_ICONID!(10, 11),
  BND_ICON_MOD_WARP = BND_ICONID!(11, 11),
  BND_ICON_MOD_SKIN = BND_ICONID!(12, 11),
  BND_ICON_MOD_TRIANGULATE = BND_ICONID!(13, 11),
  BND_ICON_MOD_WIREFRAME = BND_ICONID!(14, 11),
}
public enum /*BNDicon*/ {
  BND_ICON_REC = BND_ICONID!(0, 10),
  BND_ICON_PLAY = BND_ICONID!(1, 10),
  BND_ICON_FF = BND_ICONID!(2, 10),
  BND_ICON_REW = BND_ICONID!(3, 10),
  BND_ICON_PAUSE = BND_ICONID!(4, 10),
  BND_ICON_PREV_KEYFRAME = BND_ICONID!(5, 10),
  BND_ICON_NEXT_KEYFRAME = BND_ICONID!(6, 10),
  BND_ICON_PLAY_AUDIO = BND_ICONID!(7, 10),
  BND_ICON_PLAY_REVERSE = BND_ICONID!(8, 10),
  BND_ICON_PREVIEW_RANGE = BND_ICONID!(9, 10),
  BND_ICON_ACTION_TWEAK = BND_ICONID!(10, 10),
  BND_ICON_PMARKER_ACT = BND_ICONID!(11, 10),
  BND_ICON_PMARKER_SEL = BND_ICONID!(12, 10),
  BND_ICON_PMARKER = BND_ICONID!(13, 10),
  BND_ICON_MARKER_HLT = BND_ICONID!(14, 10),
  BND_ICON_MARKER = BND_ICONID!(15, 10),
  BND_ICON_SPACE2 = BND_ICONID!(16, 10),
  BND_ICON_SPACE3 = BND_ICONID!(17, 10),
  BND_ICON_KEYINGSET = BND_ICONID!(18, 10),
  BND_ICON_KEY_DEHLT = BND_ICONID!(19, 10),
  BND_ICON_KEY_HLT = BND_ICONID!(20, 10),
  BND_ICON_MUTE_IPO_OFF = BND_ICONID!(21, 10),
  BND_ICON_MUTE_IPO_ON = BND_ICONID!(22, 10),
  BND_ICON_VISIBLE_IPO_OFF = BND_ICONID!(23, 10),
  BND_ICON_VISIBLE_IPO_ON = BND_ICONID!(24, 10),
  BND_ICON_DRIVER = BND_ICONID!(25, 10),
}
public enum /*BNDicon*/ {
  BND_ICON_SOLO_OFF = BND_ICONID!(0, 9),
  BND_ICON_SOLO_ON = BND_ICONID!(1, 9),
  BND_ICON_FRAME_PREV = BND_ICONID!(2, 9),
  BND_ICON_FRAME_NEXT = BND_ICONID!(3, 9),
  BND_ICON_NLA_PUSHDOWN = BND_ICONID!(4, 9),
  BND_ICON_IPO_CONSTANT = BND_ICONID!(5, 9),
  BND_ICON_IPO_LINEAR = BND_ICONID!(6, 9),
  BND_ICON_IPO_BEZIER = BND_ICONID!(7, 9),
  BND_ICON_IPO_SINE = BND_ICONID!(8, 9),
  BND_ICON_IPO_QUAD = BND_ICONID!(9, 9),
  BND_ICON_IPO_CUBIC = BND_ICONID!(10, 9),
  BND_ICON_IPO_QUART = BND_ICONID!(11, 9),
  BND_ICON_IPO_QUINT = BND_ICONID!(12, 9),
  BND_ICON_IPO_EXPO = BND_ICONID!(13, 9),
  BND_ICON_IPO_CIRC = BND_ICONID!(14, 9),
  BND_ICON_IPO_BOUNCE = BND_ICONID!(15, 9),
  BND_ICON_IPO_ELASTIC = BND_ICONID!(16, 9),
  BND_ICON_IPO_BACK = BND_ICONID!(17, 9),
  BND_ICON_IPO_EASE_IN = BND_ICONID!(18, 9),
  BND_ICON_IPO_EASE_OUT = BND_ICONID!(19, 9),
  BND_ICON_IPO_EASE_IN_OUT = BND_ICONID!(20, 9),
}
public enum /*BNDicon*/ {
  BND_ICON_VERTEXSEL = BND_ICONID!(0, 8),
  BND_ICON_EDGESEL = BND_ICONID!(1, 8),
  BND_ICON_FACESEL = BND_ICONID!(2, 8),
  BND_ICON_LOOPSEL = BND_ICONID!(3, 8),
  BND_ICON_ROTATE = BND_ICONID!(5, 8),
  BND_ICON_CURSOR = BND_ICONID!(6, 8),
  BND_ICON_ROTATECOLLECTION = BND_ICONID!(7, 8),
  BND_ICON_ROTATECENTER = BND_ICONID!(8, 8),
  BND_ICON_ROTACTIVE = BND_ICONID!(9, 8),
  BND_ICON_ALIGN = BND_ICONID!(10, 8),
  BND_ICON_SMOOTHCURVE = BND_ICONID!(12, 8),
  BND_ICON_SPHERECURVE = BND_ICONID!(13, 8),
  BND_ICON_ROOTCURVE = BND_ICONID!(14, 8),
  BND_ICON_SHARPCURVE = BND_ICONID!(15, 8),
  BND_ICON_LINCURVE = BND_ICONID!(16, 8),
  BND_ICON_NOCURVE = BND_ICONID!(17, 8),
  BND_ICON_RNDCURVE = BND_ICONID!(18, 8),
  BND_ICON_PROP_OFF = BND_ICONID!(19, 8),
  BND_ICON_PROP_ON = BND_ICONID!(20, 8),
  BND_ICON_PROP_CON = BND_ICONID!(21, 8),
  BND_ICON_SCULPT_DYNTOPO = BND_ICONID!(22, 8),
  BND_ICON_PARTICLE_POINT = BND_ICONID!(23, 8),
  BND_ICON_PARTICLE_TIP = BND_ICONID!(24, 8),
  BND_ICON_PARTICLE_PATH = BND_ICONID!(25, 8),
}
public enum /*BNDicon*/ {
  BND_ICON_MAN_TRANS = BND_ICONID!(0, 7),
  BND_ICON_MAN_ROT = BND_ICONID!(1, 7),
  BND_ICON_MAN_SCALE = BND_ICONID!(2, 7),
  BND_ICON_MANIPUL = BND_ICONID!(3, 7),
  BND_ICON_SNAP_OFF = BND_ICONID!(4, 7),
  BND_ICON_SNAP_ON = BND_ICONID!(5, 7),
  BND_ICON_SNAP_NORMAL = BND_ICONID!(6, 7),
  BND_ICON_SNAP_INCREMENT = BND_ICONID!(7, 7),
  BND_ICON_SNAP_VERTEX = BND_ICONID!(8, 7),
  BND_ICON_SNAP_EDGE = BND_ICONID!(9, 7),
  BND_ICON_SNAP_FACE = BND_ICONID!(10, 7),
  BND_ICON_SNAP_VOLUME = BND_ICONID!(11, 7),
  BND_ICON_STICKY_UVS_LOC = BND_ICONID!(13, 7),
  BND_ICON_STICKY_UVS_DISABLE = BND_ICONID!(14, 7),
  BND_ICON_STICKY_UVS_VERT = BND_ICONID!(15, 7),
  BND_ICON_CLIPUV_DEHLT = BND_ICONID!(16, 7),
  BND_ICON_CLIPUV_HLT = BND_ICONID!(17, 7),
  BND_ICON_SNAP_PEEL_OBJECT = BND_ICONID!(18, 7),
  BND_ICON_GRID = BND_ICONID!(19, 7),
}
public enum /*BNDicon*/ {
  BND_ICON_PASTEDOWN = BND_ICONID!(0, 6),
  BND_ICON_COPYDOWN = BND_ICONID!(1, 6),
  BND_ICON_PASTEFLIPUP = BND_ICONID!(2, 6),
  BND_ICON_PASTEFLIPDOWN = BND_ICONID!(3, 6),
  BND_ICON_SNAP_SURFACE = BND_ICONID!(8, 6),
  BND_ICON_AUTOMERGE_ON = BND_ICONID!(9, 6),
  BND_ICON_AUTOMERGE_OFF = BND_ICONID!(10, 6),
  BND_ICON_RETOPO = BND_ICONID!(11, 6),
  BND_ICON_UV_VERTEXSEL = BND_ICONID!(12, 6),
  BND_ICON_UV_EDGESEL = BND_ICONID!(13, 6),
  BND_ICON_UV_FACESEL = BND_ICONID!(14, 6),
  BND_ICON_UV_ISLANDSEL = BND_ICONID!(15, 6),
  BND_ICON_UV_SYNC_SELECT = BND_ICONID!(16, 6),
}
public enum /*BNDicon*/ {
  BND_ICON_BBOX = BND_ICONID!(0, 5),
  BND_ICON_WIRE = BND_ICONID!(1, 5),
  BND_ICON_SOLID = BND_ICONID!(2, 5),
  BND_ICON_SMOOTH = BND_ICONID!(3, 5),
  BND_ICON_POTATO = BND_ICONID!(4, 5),
  BND_ICON_ORTHO = BND_ICONID!(6, 5),
  BND_ICON_LOCKVIEW_OFF = BND_ICONID!(9, 5),
  BND_ICON_LOCKVIEW_ON = BND_ICONID!(10, 5),
  BND_ICON_AXIS_SIDE = BND_ICONID!(12, 5),
  BND_ICON_AXIS_FRONT = BND_ICONID!(13, 5),
  BND_ICON_AXIS_TOP = BND_ICONID!(14, 5),
  BND_ICON_NDOF_DOM = BND_ICONID!(15, 5),
  BND_ICON_NDOF_TURN = BND_ICONID!(16, 5),
  BND_ICON_NDOF_FLY = BND_ICONID!(17, 5),
  BND_ICON_NDOF_TRANS = BND_ICONID!(18, 5),
  BND_ICON_LAYER_USED = BND_ICONID!(19, 5),
  BND_ICON_LAYER_ACTIVE = BND_ICONID!(20, 5),
}
public enum /*BNDicon*/ {
  BND_ICON_SORTALPHA = BND_ICONID!(0, 3),
  BND_ICON_SORTBYEXT = BND_ICONID!(1, 3),
  BND_ICON_SORTTIME = BND_ICONID!(2, 3),
  BND_ICON_SORTSIZE = BND_ICONID!(3, 3),
  BND_ICON_LONGDISPLAY = BND_ICONID!(4, 3),
  BND_ICON_SHORTDISPLAY = BND_ICONID!(5, 3),
  BND_ICON_GHOST = BND_ICONID!(6, 3),
  BND_ICON_IMGDISPLAY = BND_ICONID!(7, 3),
  BND_ICON_SAVE_AS = BND_ICONID!(8, 3),
  BND_ICON_SAVE_COPY = BND_ICONID!(9, 3),
  BND_ICON_BOOKMARKS = BND_ICONID!(10, 3),
  BND_ICON_FONTPREVIEW = BND_ICONID!(11, 3),
  BND_ICON_FILTER = BND_ICONID!(12, 3),
  BND_ICON_NEWFOLDER = BND_ICONID!(13, 3),
  BND_ICON_OPEN_RECENT = BND_ICONID!(14, 3),
  BND_ICON_FILE_PARENT = BND_ICONID!(15, 3),
  BND_ICON_FILE_REFRESH = BND_ICONID!(16, 3),
  BND_ICON_FILE_FOLDER = BND_ICONID!(17, 3),
  BND_ICON_FILE_BLANK = BND_ICONID!(18, 3),
  BND_ICON_FILE_BLEND = BND_ICONID!(19, 3),
  BND_ICON_FILE_IMAGE = BND_ICONID!(20, 3),
  BND_ICON_FILE_MOVIE = BND_ICONID!(21, 3),
  BND_ICON_FILE_SCRIPT = BND_ICONID!(22, 3),
  BND_ICON_FILE_SOUND = BND_ICONID!(23, 3),
  BND_ICON_FILE_FONT = BND_ICONID!(24, 3),
  BND_ICON_FILE_TEXT = BND_ICONID!(25, 3),
}
public enum /*BNDicon*/ {
  BND_ICON_RECOVER_AUTO = BND_ICONID!(0, 2),
  BND_ICON_SAVE_PREFS = BND_ICONID!(1, 2),
  BND_ICON_LINK_BLEND = BND_ICONID!(2, 2),
  BND_ICON_APPEND_BLEND = BND_ICONID!(3, 2),
  BND_ICON_IMPORT = BND_ICONID!(4, 2),
  BND_ICON_EXPORT = BND_ICONID!(5, 2),
  BND_ICON_EXTERNAL_DATA = BND_ICONID!(6, 2),
  BND_ICON_LOAD_FACTORY = BND_ICONID!(7, 2),
  BND_ICON_LOOP_BACK = BND_ICONID!(13, 2),
  BND_ICON_LOOP_FORWARDS = BND_ICONID!(14, 2),
  BND_ICON_BACK = BND_ICONID!(15, 2),
  BND_ICON_FORWARD = BND_ICONID!(16, 2),
  BND_ICON_FILE_BACKUP = BND_ICONID!(24, 2),
  BND_ICON_DISK_DRIVE = BND_ICONID!(25, 2),
}
public enum /*BNDicon*/ {
  BND_ICON_MATPLANE = BND_ICONID!(0, 1),
  BND_ICON_MATSPHERE = BND_ICONID!(1, 1),
  BND_ICON_MATCUBE = BND_ICONID!(2, 1),
  BND_ICON_MONKEY = BND_ICONID!(3, 1),
  BND_ICON_HAIR = BND_ICONID!(4, 1),
  BND_ICON_ALIASED = BND_ICONID!(5, 1),
  BND_ICON_ANTIALIASED = BND_ICONID!(6, 1),
  BND_ICON_MAT_SPHERE_SKY = BND_ICONID!(7, 1),
  BND_ICON_WORDWRAP_OFF = BND_ICONID!(12, 1),
  BND_ICON_WORDWRAP_ON = BND_ICONID!(13, 1),
  BND_ICON_SYNTAX_OFF = BND_ICONID!(14, 1),
  BND_ICON_SYNTAX_ON = BND_ICONID!(15, 1),
  BND_ICON_LINENUMBERS_OFF = BND_ICONID!(16, 1),
  BND_ICON_LINENUMBERS_ON = BND_ICONID!(17, 1),
  BND_ICON_SCRIPTPLUGINS = BND_ICONID!(18, 1),
}
public enum /*BNDicon*/ {
  BND_ICON_SEQ_SEQUENCER = BND_ICONID!(0, 0),
  BND_ICON_SEQ_PREVIEW = BND_ICONID!(1, 0),
  BND_ICON_SEQ_LUMA_WAVEFORM = BND_ICONID!(2, 0),
  BND_ICON_SEQ_CHROMA_SCOPE = BND_ICONID!(3, 0),
  BND_ICON_SEQ_HISTOGRAM = BND_ICONID!(4, 0),
  BND_ICON_SEQ_SPLITVIEW = BND_ICONID!(5, 0),
  BND_ICON_IMAGE_RGB = BND_ICONID!(9, 0),
  BND_ICON_IMAGE_RGB_ALPHA = BND_ICONID!(10, 0),
  BND_ICON_IMAGE_ALPHA = BND_ICONID!(11, 0),
  BND_ICON_IMAGE_ZDEPTH = BND_ICONID!(12, 0),
  BND_ICON_IMAGEFILE = BND_ICONID!(13, 0),
}


////////////////////////////////////////////////////////////////////////////////
public float bndMin(T) (in T a, in T b) if (__traits(isFloating, T)) { pragma(inline, true); import std.math : isNaN; return (isNaN(a) ? b : ( isNaN(b) ? a : (a < b ? a : b))); }
public float bndMax(T) (in T a, in T b) if (__traits(isFloating, T)) { pragma(inline, true); import std.math : isNaN; return (isNaN(a) ? b : ( isNaN(b) ? a : (a > b ? a : b))); }


////////////////////////////////////////////////////////////////////////////////
/// default text size
public __gshared float BND_LABEL_FONT_SIZE = 13;

/// default text padding in inner box
public __gshared int BND_PAD_LEFT = 8;
public __gshared int BND_PAD_RIGHT = 8;

/// label: value separator string
public __gshared string BND_LABEL_SEPARATOR = ": ";

/// alpha intensity of transparent items (0xa4)
public __gshared float BND_TRANSPARENT_ALPHA = 0.643;

/// shade intensity of beveled panels
public __gshared int BND_BEVEL_SHADE = 30;
/// shade intensity of beveled insets
public __gshared int BND_INSET_BEVEL_SHADE = 30;
/// shade intensity of hovered inner boxes
public __gshared int BND_HOVER_SHADE = 15;
/// shade intensity of splitter bevels
public __gshared int BND_SPLITTER_SHADE = 100;

/// width of icon sheet
public __gshared int BND_ICON_SHEET_WIDTH = 602;
/// height of icon sheet
public __gshared int BND_ICON_SHEET_HEIGHT = 640;
/// gridsize of icon sheet in both dimensions
public __gshared int BND_ICON_SHEET_GRID = 21;
/// offset of first icon tile relative to left border
public __gshared int BND_ICON_SHEET_OFFSET_X = 5;
/// offset of first icon tile relative to top border
public __gshared int BND_ICON_SHEET_OFFSET_Y = 10;
/// resolution of single icon
public __gshared int BND_ICON_SHEET_RES = 16;

/// size of number field arrow
public __gshared float BND_NUMBER_ARROW_SIZE = 4;

/// default text color
public enum BND_COLOR_TEXT = nvgRGBAf(0, 0, 0, 1);
/// default highlighted text color
public enum BND_COLOR_TEXT_SELECTED = nvgRGBAf(1, 1, 1, 1);
/// default color for active element
public enum BND_COLOR_ACTIVE = nvgRGBA(255, 127, 0, 255);

/// radius of tool button
public __gshared float BND_TOOL_RADIUS = 4;

/// radius of option button
public __gshared float BND_OPTION_RADIUS = 4;
/// width of option button checkbox
public __gshared float BND_OPTION_WIDTH = 14;
/// height of option button checkbox
public __gshared float BND_OPTION_HEIGHT = 15;

/// radius of text field
public __gshared float BND_TEXT_RADIUS = 4;

/// radius of number button
public __gshared float BND_NUMBER_RADIUS = 10;

/// radius of menu popup
public __gshared float BND_MENU_RADIUS = 3;
/// feather of menu popup shadow
public __gshared float BND_SHADOW_FEATHER = 12;
/// alpha of menu popup shadow
public __gshared float BND_SHADOW_ALPHA = 0.5;

/// radius of scrollbar
public __gshared float BND_SCROLLBAR_RADIUS = 7;
/// shade intensity of active scrollbar
public __gshared int BND_SCROLLBAR_ACTIVE_SHADE = 15;

/// max glyphs for position testing
public enum BND_MAX_GLYPHS = 1024;

/// max rows for position testing
public enum BND_MAX_ROWS = 32;

/// text distance from bottom
public __gshared int BND_TEXT_PAD_DOWN = 7;

/// stroke width of wire outline
public __gshared float BND_NODE_WIRE_OUTLINE_WIDTH = 4;
/// stroke width of wire
public __gshared float BND_NODE_WIRE_WIDTH = 2;
/// radius of node box
public __gshared float BND_NODE_RADIUS = 8;
/// feather of node title text
public __gshared float BND_NODE_TITLE_FEATHER = 1;
/// size of node title arrow
public __gshared float BND_NODE_ARROW_SIZE = 9;


////////////////////////////////////////////////////////////////////////////////
public float bndClamp() (float v, float mn, float mx) { pragma(inline, true); return (v > mx ? mx : (v < mn ? mn : v)); }


////////////////////////////////////////////////////////////////////////////////

/// the initial theme
public __gshared BNDtheme bndTheme = BNDtheme(
  "default theme",
  // backgroundColor
  nvgRGBA(113, 113, 113, 255),
  // regularTheme
  BNDwidgetTheme(
    "regular",
    nvgRGBA( 24,  24,  24, 255), // outlineColor
    nvgRGBA( 24,  24,  24, 255), // itemColor
    nvgRGBA(153, 153, 153, 255), // innerColor
    nvgRGBA( 99,  99,  99, 255), // innerSelectedColor
    BND_COLOR_TEXT, // textColor
    BND_COLOR_TEXT_SELECTED, // textSelectedColor
    0, // shadeTop
    0, // shadeDown
  ),
  // toolTheme
  BNDwidgetTheme(
    "tool",
    nvgRGBA( 24,  24,  24, 255), // outlineColor
    nvgRGBA( 24,  24,  24, 255), // itemColor
    nvgRGBA(153, 153, 153, 255), // innerColor
    nvgRGBA( 99,  99,  99, 255), // innerSelectedColor
    BND_COLOR_TEXT, // textColor
    BND_COLOR_TEXT_SELECTED, // textSelectedColor
    15, // shadeTop
    -15, // shadeDown
  ),
  // radioTheme
  BNDwidgetTheme(
    "radio",
    nvgRGBA(  0,   0,   0, 255), // outlineColor
    nvgRGBA(255, 255, 255, 255), // itemColor
    nvgRGBA( 70,  70,  70, 255), // innerColor
    BND_COLOR_ACTIVE, // innerSelectedColor
    BND_COLOR_TEXT_SELECTED, // textColor
    BND_COLOR_TEXT, // textSelectedColor
    15, // shadeTop
    -15, // shadeDown
  ),
  // textFieldTheme
  BNDwidgetTheme(
    "text field",
    nvgRGBA( 24,  24,  24, 255), // outlineColor
    nvgRGBA( 60, 160, 160, 255), // itemColor
    nvgRGBA(153, 153, 153, 255), // innerColor
    nvgRGBA(213, 213, 213, 255), // innerSelectedColor
    BND_COLOR_TEXT, // textColor
    BND_COLOR_TEXT, // textSelectedColor
    0, // shadeTop
    25, // shadeDown
    NVGColor.transparent, // textHoverColor
    NVGColor.black, // textCaretColor
  ),
  // optionTheme
  BNDwidgetTheme(
    "option",
    nvgRGBA(  0,   0,   0, 255), // outlineColor
    nvgRGBA(255, 255, 255, 255), // itemColor
    nvgRGBA( 70,  70,  70, 255), // innerColor
    nvgRGBA( 70,  70,  70, 255), // innerSelectedColor
    BND_COLOR_TEXT, // textColor
    BND_COLOR_TEXT_SELECTED, // textSelectedColor
    15, // shadeTop
    -15, // shadeDown
  ),
  // choiceTheme
  BNDwidgetTheme(
    "choice",
    nvgRGBA(  0,   0,   0, 255), // outlineColor
    nvgRGBA(255, 255, 255, 255), // itemColor
    nvgRGBA( 70,  70,  70, 255), // innerColor
    nvgRGBA( 70,  70,  70, 255), // innerSelectedColor
    BND_COLOR_TEXT_SELECTED, // textColor
    nvgRGBA(204, 204, 204, 255), // textSelectedColor
    15, // shadeTop
    -15, // shadeDown
  ),
  // numberFieldTheme
  BNDwidgetTheme(
    "number field",
    nvgRGBA( 24,  24,  24, 255), // outlineColor
    nvgRGBA( 90,  90,  90, 255), // itemColor
    nvgRGBA(180, 180, 180, 255), // innerColor
    nvgRGBA(153, 153, 153, 255), // innerSelectedColor
    BND_COLOR_TEXT, // textColor
    BND_COLOR_TEXT_SELECTED, // textSelectedColor
    -20, // shadeTop
    0, // shadeDown
  ),
  // sliderTheme
  BNDwidgetTheme(
    "slider",
    nvgRGBA( 24,  24,  24, 255), // outlineColor
    nvgRGBA(128, 128, 128, 255), // itemColor
    nvgRGBA(180, 180, 180, 255), // innerColor
    nvgRGBA(153, 153, 153, 255), // innerSelectedColor
    BND_COLOR_TEXT, // textColor
    BND_COLOR_TEXT_SELECTED, // textSelectedColor
    -20, // shadeTop
    0, // shadeDown
  ),
  // scrollBarTheme
  BNDwidgetTheme(
    "scrollbar",
    nvgRGBA( 49,  49,  49, 255), // outlineColor
    nvgRGBA(128, 128, 128, 255), // itemColor
    nvgRGBA( 80,  80,  80, 180), // innerColor
    nvgRGBA( 99,  99,  99, 180), // innerSelectedColor
    BND_COLOR_TEXT, // textColor
    BND_COLOR_TEXT_SELECTED, // textSelectedColor
    5, // shadeTop
    -5, // shadeDown
  ),
  // tooltipTheme
  BNDwidgetTheme(
    "tooltip",
    nvgRGBA(  0,   0,   0, 255), // outlineColor
    nvgRGBA( 99,  99,  99, 255), // itemColor
    nvgRGBA( 24,  24,  24, 230), // innerColor
    nvgRGBA( 44,  44,  44, 230), // innerSelectedColor
    nvgRGBA(159, 159, 159, 255), // textColor
    BND_COLOR_TEXT_SELECTED, // textSelectedColor
    0, // shadeTop
    0, // shadeDown
  ),
  // menuTheme
  BNDwidgetTheme(
    "menu",
    nvgRGBA(  0,   0,   0, 255), // outlineColor
    nvgRGBA( 99,  99,  99, 255), // itemColor
    nvgRGBA( 24,  24,  24, 230), // innerColor
    nvgRGBA( 44,  44,  44, 230), // innerSelectedColor
    nvgRGBA(159, 159, 159, 255), // textColor
    BND_COLOR_TEXT_SELECTED, // textSelectedColor
    0, // shadeTop
    0, // shadeDown
  ),
  // menuItemTheme
  BNDwidgetTheme(
    "menu item",
    nvgRGBA(  0,   0,   0, 255), // outlineColor
    nvgRGBA(172, 172, 172, 128), // itemColor
    nvgRGBA(  0, 100, 180, 255), // innerColor
    BND_COLOR_ACTIVE, // innerSelectedColor
    BND_COLOR_TEXT_SELECTED, // textColor
    BND_COLOR_TEXT, // textSelectedColor
    38, // shadeTop
    0, // shadeDown
    nvgRGBA(255, 255, 255, 255), // textHoverColor
  ),
  // nodeTheme
  BNDnodeTheme(
    "node",
    nvgRGBA(240,  87,   0, 255), // nodeSelectedColor
    nvgRGBA(  0,   0,   0, 255), // wiresColor
    nvgRGBA(126, 111, 111, 255), // textSelectedColor
    nvgRGBA(255, 170,  64, 255), // activeNodeColor
    nvgRGBA(255, 255, 255, 255), // wireSelectColor
    nvgRGBA(155, 155, 155, 159), // nodeBackdropColor
    5, // noodleCurving
  ),
);

////////////////////////////////////////////////////////////////////////////////

/// Sets the current theme all widgets will be drawn with. the default Blender 2.6 theme is set by default.
public void bndSetTheme (in ref BNDtheme theme) { bndTheme = theme; }

/// Returns the currently set theme
public BNDtheme* bndGetTheme () { return &bndTheme; }

// the handle to the image containing the icon sheet
private __gshared NVGImage bndIconImage;

//HACK!
//shared static ~this () { bndIconImage.clear(); }

/** Designates an image handle as returned by nvgCreateImage*() as the themes'
 * icon sheet. The icon sheet format must be compatible to Blender 2.6's icon
 * sheet; the order of icons does not matter.
 *
 * A valid icon sheet is e.g. shown at
 * http://wiki.blender.org/index.php/Dev:2.5/Doc/How_to/Add_an_icon
 *
 * $(WARNING Icon sheet image should not outlive it's parent context! Use [bndClearIconImage] before context deletion.)
 */
public void bndSetIconImage() (in auto ref NVGImage image) nothrow @trusted @nogc { version(aliced) pragma(inline, true); bndIconImage = image; }

/// Clears current icon image.
public void bndClearIconImage () nothrow @trusted @nogc { version(aliced) pragma(inline, true); bndIconImage.clear(); }

/// Returns icon sheet image.
public NVGImage bndGetIconImage () nothrow @trusted @nogc { version(aliced) pragma(inline, true); return bndIconImage; }

// the handle to the UI font
private __gshared int bndFont = -1;
private __gshared string bndFontFace = null;

/** Designates an image handle as returned by nvgCreateFont*() as the themes'
 * UI font. Blender's original UI font Droid Sans is perfectly suited and
 * available here:
 * https://svn.blender.org/svnroot/bf-blender/trunk/blender/release/datafiles/fonts/
 */
public void bndSetFont (int font) nothrow @trusted @nogc { pragma(inline, true); bndFont = font; bndFontFace = null; }

/** Designates an image handle as returned by nvgCreateFont*() as the themes'
 * UI font. Blender's original UI font Droid Sans is perfectly suited and
 * available here:
 * https://svn.blender.org/svnroot/bf-blender/trunk/blender/release/datafiles/fonts/
 */
public void bndSetFont (string font) nothrow @trusted @nogc { pragma(inline, true); bndFont = -1; bndFontFace = font; }

public struct BndFontSaviour {
  int bndFont = -1;
  string bndFontFace = null;
}

/// Returns opaque object with the current font.
public BndFontSaviour bndGetFont () nothrow @trusted @nogc { pragma(inline, true); return BndFontSaviour(bndFont, bndFontFace); }

/// Sets current font from the opaque object, returned by [bndGetFont].
public void bndSetFont (in BndFontSaviour fsv) nothrow @trusted @nogc { pragma(inline, true); bndFont = fsv.bndFont; bndFontFace = fsv.bndFontFace; }


// returns `true` if font *looks* like valid
public bool bndRealizeFont (NVGContext ctx) nothrow @trusted @nogc {
  if (ctx is null) return false;
  if (bndFont >= 0) { ctx.fontFaceId = bndFont; return true; }
  if (bndFontFace.length) { ctx.fontFace = bndFontFace; return true; }
  return false;
}


////////////////////////////////////////////////////////////////////////////////
/// High Level Functions. Use these functions to draw themed widgets with your NVGcontext.

/** Draw a label with its lower left origin at (x, y) and size of (w, h).
 *
 * if iconid >= 0, an icon will be added to the widget
 *
 * if label is not null, a label will be added to the widget
 *
 * widget looks best when height is BND_WIDGET_HEIGHT
 */
public void bndLabel(T=char) (NVGContext ctx, float x, float y, float w, float h, int iconid, const(T)[] label, int align_=BND_LEFT)
if (isAnyCharType!T)
{
  bndIconLabelValue(ctx, x, y, w, h, iconid, bndTheme.regularTheme.textColor, /*BND_LEFT*/align_, BND_LABEL_FONT_SIZE, label);
}

/** Draw a tool button  with its lower left origin at (x, y) and size of (w, h),
 * where flags is one or multiple flags from BNDcornerFlags and state denotes
 * the widgets current UI state.
 *
 * if iconid >= 0, an icon will be added to the widget
 *
 * if label is not null, a label will be added to the widget
 *
 * widget looks best when height is BND_WIDGET_HEIGHT
 */
public void bndToolButton(T=char) (NVGContext ctx, float x, float y, float w, float h, int flags, BNDwidgetState state, int iconid, const(T)[] label)
if (isAnyCharType!T)
{
  float[4] cr = void;
  NVGColor shadeTop, shadeDown;
  bndSelectCorners(cr[], BND_TOOL_RADIUS, flags);
  bndBevelInset(ctx, x, y, w, h, cr[2], cr[3]);
  bndInnerColors(&shadeTop, &shadeDown, &bndTheme.toolTheme, state, 1);
  bndInnerBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], shadeTop, shadeDown);
  bndOutlineBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], bndTransparent(bndTheme.toolTheme.outlineColor));
  bndIconLabelValue(ctx, x, y, w, h, iconid, bndTextColor(&bndTheme.toolTheme, state), BND_CENTER, BND_LABEL_FONT_SIZE, label);
}

/** Draw a radio button with its lower left origin at (x, y) and size of (w, h),
 * where flags is one or multiple flags from BNDcornerFlags and state denotes
 * the widgets current UI state.
 *
 * if iconid >= 0, an icon will be added to the widget
 *
 * if label is not null, a label will be added to the widget
 *
 * widget looks best when height is BND_WIDGET_HEIGHT
 */
public void bndRadioButton(T=char) (NVGContext ctx, float x, float y, float w, float h, int flags, BNDwidgetState state, int iconid, const(T)[] label)
if (isAnyCharType!T)
{
  float[4] cr = void;
  NVGColor shadeTop, shadeDown;
  bndSelectCorners(cr[], BND_OPTION_RADIUS, flags);
  bndBevelInset(ctx, x, y, w, h, cr[2], cr[3]);
  bndInnerColors(&shadeTop, &shadeDown, &bndTheme.radioTheme, state, 1);
  bndInnerBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], shadeTop, shadeDown);
  bndOutlineBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], bndTransparent(bndTheme.radioTheme.outlineColor));
  bndIconLabelValue(ctx, x, y, w, h, iconid, bndTextColor(&bndTheme.radioTheme, state), BND_CENTER, BND_LABEL_FONT_SIZE, label);
}

/** Draw a radio button with its lower left origin at (x, y) and size of (w, h),
 * where flags is one or multiple flags from BNDcornerFlags and state denotes
 * the widgets current UI state.
 *
 * if iconid >= 0, an icon will be added to the widget
 *
 * if label is not null, a label will be added to the widget
 *
 * widget looks best when height is BND_WIDGET_HEIGHT
 */
public void bndRadioButton2(T=char) (NVGContext ctx, float x, float y, float w, float h, int flags, BNDwidgetState state, int iconid, const(T)[] label)
if (isAnyCharType!T)
{
  float ox, oy;
  NVGColor shadeTop, shadeDown;
  ox = x;
  oy = y+h-BND_OPTION_HEIGHT-3;
  bndBevelInset(ctx, ox, oy, BND_OPTION_WIDTH, BND_OPTION_HEIGHT, BND_OPTION_RADIUS, BND_OPTION_RADIUS);
  bndInnerColors(&shadeTop, &shadeDown, &bndTheme.optionTheme, state, 1);
  bndInnerBox(ctx, ox, oy, BND_OPTION_WIDTH, BND_OPTION_HEIGHT, BND_OPTION_RADIUS, BND_OPTION_RADIUS, BND_OPTION_RADIUS, BND_OPTION_RADIUS, shadeTop, shadeDown);
  bndOutlineBox(ctx, ox, oy, BND_OPTION_WIDTH, BND_OPTION_HEIGHT, BND_OPTION_RADIUS, BND_OPTION_RADIUS, BND_OPTION_RADIUS, BND_OPTION_RADIUS, bndTransparent(bndTheme.optionTheme.outlineColor));
  if (state == BND_ACTIVE) bndRadioCheck(ctx, ox, oy, bndTransparent(bndTheme.optionTheme.itemColor));
  bndIconLabelValue(ctx, x+12, y, w-12, h, -1, bndTextColor(&bndTheme.optionTheme, state), BND_LEFT, BND_LABEL_FONT_SIZE, label);
}

/** Calculate the corresponding text position for given coordinates px/py
 * in a text field.
 * See bndTextField for more info.
 */
public int bndTextFieldTextPosition(T=char) (NVGContext ctx, float x, float y, float w, float h, int iconid, const(T)[] text, int px, int py)
if (isAnyCharType!T)
{
  return bndIconLabelTextPosition(ctx, x, y, w, h, iconid, BND_LABEL_FONT_SIZE, text, px, py);
}

/** Draw a text field with its lower left origin at (x, y) and size of (w, h),
 * where flags is one or multiple flags from BNDcornerFlags and state denotes
 * the widgets current UI state.
 *
 * if iconid >= 0, an icon will be added to the widget
 *
 * if text is not null, text will be printed to the widget
 *
 * cbegin must be >= 0 and <= strlen(text) and denotes the beginning of the caret
 *
 * cend must be >= cbegin and <= strlen(text) and denotes the end of the caret
 *
 * if cend < cbegin, then no caret will be drawn
 *
 * widget looks best when height is BND_WIDGET_HEIGHT
 */
public void bndTextField(T=char) (NVGContext ctx, float x, float y, float w, float h, int flags, BNDwidgetState state, int iconid, const(T)[] text, int cbegin, int cend)
if (isAnyCharType!T)
{
  float[4] cr = void;
  NVGColor shadeTop, shadeDown;
  bndSelectCorners(cr[], BND_TEXT_RADIUS, flags);
  bndBevelInset(ctx, x, y, w, h, cr[2], cr[3]);
  bndInnerColors(&shadeTop, &shadeDown, &bndTheme.textFieldTheme, state, 0);
  bndInnerBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], shadeTop, shadeDown);
  bndOutlineBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], bndTransparent(bndTheme.textFieldTheme.outlineColor));
  if (state != BND_ACTIVE) cend = -1;
  NVGColor cc = bndTheme.textFieldTheme.textCaretColor;
  if (cc.isTransparent) cc = bndTheme.textFieldTheme.textColor;
  bndIconLabelCaret(ctx, x, y, w, h, iconid, bndTextColor(&bndTheme.textFieldTheme, state), BND_LABEL_FONT_SIZE, text, bndTheme.textFieldTheme.itemColor, cbegin, cend, cc);
}

/** Draw an option button with its lower left origin at (x, y) and size of (w, h),
 * where flags is one or multiple flags from BNDcornerFlags and state denotes
 * the widgets current UI state.
 *
 * if label is not null, a label will be added to the widget
 *
 * widget looks best when height is BND_WIDGET_HEIGHT
 */
public void bndOptionButton(T=char) (NVGContext ctx, float x, float y, float w, float h, BNDwidgetState state, const(T)[] label)
if (isAnyCharType!T)
{
  float ox, oy;
  NVGColor shadeTop, shadeDown;
  ox = x;
  oy = y+h-BND_OPTION_HEIGHT-3;
  bndBevelInset(ctx, ox, oy, BND_OPTION_WIDTH, BND_OPTION_HEIGHT, BND_OPTION_RADIUS, BND_OPTION_RADIUS);
  bndInnerColors(&shadeTop, &shadeDown, &bndTheme.optionTheme, state, 1);
  bndInnerBox(ctx, ox, oy, BND_OPTION_WIDTH, BND_OPTION_HEIGHT, BND_OPTION_RADIUS, BND_OPTION_RADIUS, BND_OPTION_RADIUS, BND_OPTION_RADIUS, shadeTop, shadeDown);
  bndOutlineBox(ctx, ox, oy, BND_OPTION_WIDTH, BND_OPTION_HEIGHT, BND_OPTION_RADIUS, BND_OPTION_RADIUS, BND_OPTION_RADIUS, BND_OPTION_RADIUS, bndTransparent(bndTheme.optionTheme.outlineColor));
  if (state == BND_ACTIVE) bndCheck(ctx, ox, oy, bndTransparent(bndTheme.optionTheme.itemColor));
  bndIconLabelValue(ctx, x+12, y, w-12, h, -1, bndTextColor(&bndTheme.optionTheme, state), BND_LEFT, BND_LABEL_FONT_SIZE, label);
}

/** Draw a choice button with its lower left origin at (x, y) and size of (w, h),
 * where flags is one or multiple flags from BNDcornerFlags and state denotes
 * the widgets current UI state.
 *
 * if iconid >= 0, an icon will be added to the widget
 *
 * if label is not null, a label will be added to the widget
 *
 * widget looks best when height is BND_WIDGET_HEIGHT
 */
public void bndChoiceButton(T=char) (NVGContext ctx, float x, float y, float w, float h, int flags, BNDwidgetState state, int iconid, const(T)[] label)
if (isAnyCharType!T)
{
  float[4] cr = void;
  NVGColor shadeTop, shadeDown;
  bndSelectCorners(cr[], BND_OPTION_RADIUS, flags);
  bndBevelInset(ctx, x, y, w, h, cr[2], cr[3]);
  bndInnerColors(&shadeTop, &shadeDown, &bndTheme.choiceTheme, state, 1);
  bndInnerBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], shadeTop, shadeDown);
  bndOutlineBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], bndTransparent(bndTheme.choiceTheme.outlineColor));
  bndIconLabelValue(ctx, x, y, w, h, iconid, bndTextColor(&bndTheme.choiceTheme, state), BND_LEFT, BND_LABEL_FONT_SIZE, label);
  bndUpDownArrow(ctx, x+w-10, y+10, 5, bndTransparent(bndTheme.choiceTheme.itemColor));
}

/** Draw a color button  with its lower left origin at (x, y) and size of (w, h),
 * where flags is one or multiple flags from BNDcornerFlags and state denotes
 * the widgets current UI state.
 *
 * widget looks best when height is BND_WIDGET_HEIGHT
 */
public void bndColorButton (NVGContext ctx, float x, float y, float w, float h, int flags, NVGColor color) {
  float[4] cr = void;
  bndSelectCorners(cr[], BND_TOOL_RADIUS, flags);
  bndBevelInset(ctx, x, y, w, h, cr[2], cr[3]);
  bndInnerBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], color, color);
  bndOutlineBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], bndTransparent(bndTheme.toolTheme.outlineColor));
}

/** Draw a number field with its lower left origin at (x, y) and size of (w, h),
 * where flags is one or multiple flags from BNDcornerFlags and state denotes
 * the widgets current UI state.
 *
 * if label is not null, a label will be added to the widget
 *
 * if value is not null, a value will be added to the widget, along with a ":" separator
 *
 * widget looks best when height is BND_WIDGET_HEIGHT
 */
public void bndNumberField(T=char) (NVGContext ctx, float x, float y, float w, float h, int flags, BNDwidgetState state, const(T)[] label, const(char)[] value)
if (isAnyCharType!T)
{
  float[4] cr = void;
  NVGColor shadeTop, shadeDown;
  bndSelectCorners(cr[], BND_NUMBER_RADIUS, flags);
  bndBevelInset(ctx, x, y, w, h, cr[2], cr[3]);
  bndInnerColors(&shadeTop, &shadeDown, &bndTheme.numberFieldTheme, state, 0);
  bndInnerBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], shadeTop, shadeDown);
  bndOutlineBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], bndTransparent(bndTheme.numberFieldTheme.outlineColor));
  bndIconLabelValue(ctx, x, y, w, h, -1, bndTextColor(&bndTheme.numberFieldTheme, state), BND_CENTER, BND_LABEL_FONT_SIZE, label, value);
  bndArrow(ctx, x+8, y+10, -BND_NUMBER_ARROW_SIZE, bndTransparent(bndTheme.numberFieldTheme.itemColor));
  bndArrow(ctx, x+w-8, y+10, BND_NUMBER_ARROW_SIZE, bndTransparent(bndTheme.numberFieldTheme.itemColor));
}

/** Draw slider control with its lower left origin at (x, y) and size of (w, h),
 * where flags is one or multiple flags from BNDcornerFlags and state denotes
 * the widgets current UI state.
 *
 * progress must be in the range 0..1 and controls the size of the slider bar
 *
 * if label is not null, a label will be added to the widget
 *
 * if value is not null, a value will be added to the widget, along with a ":" separator
 *
 * widget looks best when height is BND_WIDGET_HEIGHT
 */
public void bndSlider(T=char,TV=char) (NVGContext ctx, float x, float y, float w, float h, int flags, BNDwidgetState state, float progress, const(T)[] label, const(TV)[] value)
if (isAnyCharType!T && isAnyCharType!TV)
{
  float[4] cr = void;
  NVGColor shadeTop, shadeDown;

  bndSelectCorners(cr[], BND_NUMBER_RADIUS, flags);
  bndBevelInset(ctx, x, y, w, h, cr[2], cr[3]);
  bndInnerColors(&shadeTop, &shadeDown, &bndTheme.sliderTheme, state, 0);
  bndInnerBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], shadeTop, shadeDown);

  if (state == BND_ACTIVE) {
    shadeTop = bndOffsetColor(bndTheme.sliderTheme.itemColor, bndTheme.sliderTheme.shadeTop);
    shadeDown = bndOffsetColor(bndTheme.sliderTheme.itemColor, bndTheme.sliderTheme.shadeDown);
  } else {
    shadeTop = bndOffsetColor(bndTheme.sliderTheme.itemColor, bndTheme.sliderTheme.shadeDown);
    shadeDown = bndOffsetColor(bndTheme.sliderTheme.itemColor, bndTheme.sliderTheme.shadeTop);
  }
  ctx.scissor(x, y, 8+(w-8)*bndClamp(progress, 0, 1), h);
  bndInnerBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], shadeTop, shadeDown);
  ctx.resetScissor();

  bndOutlineBox(ctx, x, y, w, h, cr[0], cr[1], cr[2], cr[3], bndTransparent(bndTheme.sliderTheme.outlineColor));
  bndIconLabelValue(ctx, x, y, w, h, -1, bndTextColor(&bndTheme.sliderTheme, state), BND_CENTER, BND_LABEL_FONT_SIZE, label, value);
}

/** Draw scrollbar with its lower left origin at (x, y) and size of (w, h),
 * where state denotes the widgets current UI state.
 *
 * offset is in the range 0..1 and controls the position of the scroll handle
 *
 * size is in the range 0..1 and controls the size of the scroll handle
 *
 * horizontal widget looks best when height is BND_SCROLLBAR_HEIGHT,
 *
 * vertical looks best when width is BND_SCROLLBAR_WIDTH
 */
public void bndScrollBar (NVGContext ctx, float x, float y, float w, float h, BNDwidgetState state, float offset, float size) {
  bndBevelInset(ctx, x, y, w, h, BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS);
  bndInnerBox(ctx, x, y, w, h,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    bndOffsetColor(bndTheme.scrollBarTheme.innerColor, 3*bndTheme.scrollBarTheme.shadeDown),
    bndOffsetColor(bndTheme.scrollBarTheme.innerColor, 3*bndTheme.scrollBarTheme.shadeTop));
  bndOutlineBox(ctx, x, y, w, h,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    bndTransparent(bndTheme.scrollBarTheme.outlineColor));

  NVGColor itemColor = bndOffsetColor(bndTheme.scrollBarTheme.itemColor, (state == BND_ACTIVE ? BND_SCROLLBAR_ACTIVE_SHADE : 0));

  bndScrollHandleRect(&x, &y, &w, &h, offset, size);

  bndInnerBox(ctx, x, y, w, h,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    bndOffsetColor(itemColor, 3*bndTheme.scrollBarTheme.shadeTop),
    bndOffsetColor(itemColor, 3*bndTheme.scrollBarTheme.shadeDown));
  bndOutlineBox(ctx, x, y, w, h,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    bndTransparent(bndTheme.scrollBarTheme.outlineColor));
}

/** Draw scrollbar with its lower left origin at (x, y) and size of (w, h),
 * where state denotes the widgets current UI state.
 *
 * offset is in the range 0..1 and controls the position of the scroll handle
 *
 * size is in the range 0..1 and controls the size of the scroll handle
 *
 * horizontal widget looks best when height is BND_SCROLLBAR_HEIGHT,
 *
 * vertical looks best when width is BND_SCROLLBAR_WIDTH
 */
public void bndScrollSlider (NVGContext ctx, float x, float y, float w, float h, BNDwidgetState state, float offset, float size=0) {
  bndBevelInset(ctx, x, y, w, h, BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS);
  bndInnerBox(ctx, x, y, w, h,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    bndOffsetColor(bndTheme.scrollBarTheme.innerColor, 3*bndTheme.scrollBarTheme.shadeDown),
    bndOffsetColor(bndTheme.scrollBarTheme.innerColor, 3*bndTheme.scrollBarTheme.shadeTop));
  bndOutlineBox(ctx, x, y, w, h,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    bndTransparent(bndTheme.scrollBarTheme.outlineColor));

  NVGColor itemColor = bndOffsetColor(bndTheme.scrollBarTheme.itemColor, (state == BND_ACTIVE ? BND_SCROLLBAR_ACTIVE_SHADE : 0));

  bndScrollSliderRect(&w, &h, offset, size);

  bndInnerBox(ctx, x, y, w, h,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    bndOffsetColor(itemColor, 3*bndTheme.scrollBarTheme.shadeTop),
    bndOffsetColor(itemColor, 3*bndTheme.scrollBarTheme.shadeDown));
  bndOutlineBox(ctx, x, y, w, h,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    BND_SCROLLBAR_RADIUS, BND_SCROLLBAR_RADIUS,
    bndTransparent(bndTheme.scrollBarTheme.outlineColor));
}

/** Draw a menu background with its lower left origin at (x, y) and size of (w, h),
 * where flags is one or multiple flags from BNDcornerFlags.
 */
public void bndMenuBackground (NVGContext ctx, float x, float y, float w, float h, int flags) {
  float[4] cr = void;
  NVGColor shadeTop, shadeDown;
  bndSelectCorners(cr[], BND_MENU_RADIUS, flags);
  bndInnerColors(&shadeTop, &shadeDown, &bndTheme.menuTheme, BND_DEFAULT, 0);
  bndInnerBox(ctx, x, y, w, h+1, cr[0], cr[1], cr[2], cr[3], shadeTop, shadeDown);
  bndOutlineBox(ctx, x, y, w, h+1, cr[0], cr[1], cr[2], cr[3], bndTransparent(bndTheme.menuTheme.outlineColor));
  bndDropShadow(ctx, x, y, w, h, BND_MENU_RADIUS, BND_SHADOW_FEATHER, BND_SHADOW_ALPHA);
}

/// Draw a tooltip background with its lower left origin at (x, y) and size of (w, h)
public void bndTooltipBackground (NVGContext ctx, float x, float y, float w, float h) {
  NVGColor shadeTop, shadeDown;
  bndInnerColors(&shadeTop, &shadeDown, &bndTheme.tooltipTheme, BND_DEFAULT, 0);
  bndInnerBox(ctx, x, y, w, h+1, BND_MENU_RADIUS, BND_MENU_RADIUS, BND_MENU_RADIUS, BND_MENU_RADIUS, shadeTop, shadeDown);
  bndOutlineBox(ctx, x, y, w, h+1, BND_MENU_RADIUS, BND_MENU_RADIUS, BND_MENU_RADIUS, BND_MENU_RADIUS, bndTransparent(bndTheme.tooltipTheme.outlineColor));
  bndDropShadow(ctx, x, y, w, h, BND_MENU_RADIUS, BND_SHADOW_FEATHER, BND_SHADOW_ALPHA);
}

/** Draw a menu label with its lower left origin at (x, y) and size of (w, h).
 *
 * if iconid >= 0, an icon will be added to the widget
 *
 * if label is not null, a label will be added to the widget
 *
 * widget looks best when height is BND_WIDGET_HEIGHT
 */
public void bndMenuLabel(T=char) (NVGContext ctx, float x, float y, float w, float h, int iconid, const(T)[] label)
if (isAnyCharType!T)
{
  bndIconLabelValue(ctx, x, y, w, h, iconid, bndTheme.menuTheme.textColor, BND_LEFT, BND_LABEL_FONT_SIZE, label);
}

/** Draw a menu item with its lower left origin at (x, y) and size of (w, h),
 * where state denotes the widgets current UI state.
 *
 * if iconid >= 0, an icon will be added to the widget
 *
 * if label is not null, a label will be added to the widget
 *
 * widget looks best when height is BND_WIDGET_HEIGHT
 */
public void bndMenuItem(T=char) (NVGContext ctx, float x, float y, float w, float h, BNDwidgetState state, int iconid, const(T)[] label)
if (isAnyCharType!T)
{
  if (state != BND_DEFAULT) {
    auto clr = (state == BND_HOVER ? bndOffsetColor(bndTheme.menuItemTheme.innerColor/*innerSelectedColor*/, BND_HOVER_SHADE) : bndTheme.menuItemTheme.innerSelectedColor);
    bndInnerBox(ctx, x, y, w, h, 0, 0, 0, 0,
      bndOffsetColor(clr, bndTheme.menuItemTheme.shadeTop),
      bndOffsetColor(clr, bndTheme.menuItemTheme.shadeDown));
    //state = BND_ACTIVE;
  }
  bndIconLabelValue(ctx, x, y, w, h, iconid,
    bndTextColor(&bndTheme.menuItemTheme, state), BND_LEFT,
    BND_LABEL_FONT_SIZE, label);
}

/// Draw a node port at the given position filled with the given color
public void bndNodePort (NVGContext ctx, float x, float y, BNDwidgetState state, NVGColor color) {
  ctx.beginPath();
  ctx.circle(x, y, BND_NODE_PORT_RADIUS);
  ctx.strokeColor(bndTheme.nodeTheme.wiresColor);
  ctx.strokeWidth(1.0f);
  ctx.stroke();
  ctx.fillColor((state != BND_DEFAULT ? bndOffsetColor(color, BND_HOVER_SHADE) : color));
  ctx.fill();
}

/// Draw a node wire originating at (x0, y0) and floating to (x1, y1), with a colored gradient based on the two colors color0 and color1
public void bndColoredNodeWire (NVGContext ctx, float x0, float y0, float x1, float y1, NVGColor color0, NVGColor color1) {
  import core.stdc.math : fabsf;
  float length = bndMax(fabsf(x1-x0), fabsf(y1-y0));
  float delta = length*cast(float)bndTheme.nodeTheme.noodleCurving/10.0f;

  ctx.beginPath();
  ctx.moveTo(x0, y0);
  ctx.bezierTo(x0+delta, y0, x1-delta, y1, x1, y1);
  NVGColor colorw = bndTheme.nodeTheme.wiresColor;
  colorw.a = (color0.a < color1.a ? color0.a : color1.a);
  ctx.strokeColor(colorw);
  ctx.strokeWidth(BND_NODE_WIRE_OUTLINE_WIDTH);
  ctx.stroke();
  ctx.strokePaint(ctx.linearGradient(x0, y0, x1, y1, color0, color1));
  ctx.strokeWidth(BND_NODE_WIRE_WIDTH);
  ctx.stroke();
}

/** Draw a node wire originating at (x0, y0) and floating to (x1, y1), with
 * a colored gradient based on the states state0 and state1:
 *
 * BND_DEFAULT: default wire color
 *
 * BND_HOVER: selected wire color
 *
 * BND_ACTIVE: dragged wire color
 */
public void bndNodeWire (NVGContext ctx, float x0, float y0, float x1, float y1, BNDwidgetState state0, BNDwidgetState state1) {
  bndColoredNodeWire(ctx, x0, y0, x1, y1, bndNodeWireColor(&bndTheme.nodeTheme, state0), bndNodeWireColor(&bndTheme.nodeTheme, state1));
}

/// Draw a node background with its upper left origin at (x, y) and size of (w, h) where titleColor provides the base color for the title bar
public void bndNodeBackground(T=char) (NVGContext ctx, float x, float y, float w, float h, BNDwidgetState state, int iconid, const(T)[] label, NVGColor titleColor)
if (isAnyCharType!T)
{
  bndInnerBox(ctx, x, y, w, BND_NODE_TITLE_HEIGHT+2,
      BND_NODE_RADIUS, BND_NODE_RADIUS, 0, 0,
      bndTransparent(bndOffsetColor(titleColor, BND_BEVEL_SHADE)),
      bndTransparent(titleColor));
  bndInnerBox(ctx, x, y+BND_NODE_TITLE_HEIGHT-1, w, h+2-BND_NODE_TITLE_HEIGHT,
      0, 0, BND_NODE_RADIUS, BND_NODE_RADIUS,
      bndTransparent(bndTheme.nodeTheme.nodeBackdropColor),
      bndTransparent(bndTheme.nodeTheme.nodeBackdropColor));
  bndNodeIconLabel(ctx,
      x+BND_NODE_ARROW_AREA_WIDTH, y,
      w-BND_NODE_ARROW_AREA_WIDTH-BND_NODE_MARGIN_SIDE, BND_NODE_TITLE_HEIGHT,
      iconid, bndTheme.regularTheme.textColor,
      bndOffsetColor(titleColor, BND_BEVEL_SHADE),
      BND_LEFT, BND_LABEL_FONT_SIZE, label);
  NVGColor arrowColor;
  NVGColor borderColor;
  switch (state) {
    default:
    case BND_DEFAULT:
      borderColor = nvgRGBf(0, 0, 0);
      arrowColor = bndOffsetColor(titleColor, -BND_BEVEL_SHADE);
      break;
    case BND_HOVER:
      borderColor = bndTheme.nodeTheme.nodeSelectedColor;
      arrowColor = bndTheme.nodeTheme.nodeSelectedColor;
      break;
    case BND_ACTIVE:
      borderColor = bndTheme.nodeTheme.activeNodeColor;
      arrowColor = bndTheme.nodeTheme.nodeSelectedColor;
      break;
  }
  bndOutlineBox(ctx, x, y, w, h+1, BND_NODE_RADIUS, BND_NODE_RADIUS, BND_NODE_RADIUS, BND_NODE_RADIUS, bndTransparent(borderColor));
  //bndNodeArrowDown(ctx, x+BND_NODE_MARGIN_SIDE, y+BND_NODE_TITLE_HEIGHT-4, BND_NODE_ARROW_SIZE, arrowColor);
  bndDropShadow(ctx, x, y, w, h, BND_NODE_RADIUS, BND_SHADOW_FEATHER, BND_SHADOW_ALPHA);
}

/// Draw a window with the upper right and lower left splitter widgets into the rectangle at origin (x, y) and size (w, h)
public void bndSplitterWidgets (NVGContext ctx, float x, float y, float w, float h) {
  NVGColor insetLight = bndTransparent(bndOffsetColor(bndTheme.backgroundColor, BND_SPLITTER_SHADE));
  NVGColor insetDark = bndTransparent(bndOffsetColor(bndTheme.backgroundColor, -BND_SPLITTER_SHADE));
  NVGColor inset = bndTransparent(bndTheme.backgroundColor);

  float x2 = x+w;
  float y2 = y+h;

  ctx.beginPath();
  ctx.moveTo(x, y2-13);
  ctx.lineTo(x+13, y2);
  ctx.moveTo(x, y2-9);
  ctx.lineTo(x+9, y2);
  ctx.moveTo(x, y2-5);
  ctx.lineTo(x+5, y2);

  ctx.moveTo(x2-11, y);
  ctx.lineTo(x2, y+11);
  ctx.moveTo(x2-7, y);
  ctx.lineTo(x2, y+7);
  ctx.moveTo(x2-3, y);
  ctx.lineTo(x2, y+3);

  ctx.strokeColor(insetDark);
  ctx.stroke();

  ctx.beginPath();
  ctx.moveTo(x, y2-11);
  ctx.lineTo(x+11, y2);
  ctx.moveTo(x, y2-7);
  ctx.lineTo(x+7, y2);
  ctx.moveTo(x, y2-3);
  ctx.lineTo(x+3, y2);

  ctx.moveTo(x2-13, y);
  ctx.lineTo(x2, y+13);
  ctx.moveTo(x2-9, y);
  ctx.lineTo(x2, y+9);
  ctx.moveTo(x2-5, y);
  ctx.lineTo(x2, y+5);

  ctx.strokeColor(insetLight);
  ctx.stroke();

  ctx.beginPath();
  ctx.moveTo(x, y2-12);
  ctx.lineTo(x+12, y2);
  ctx.moveTo(x, y2-8);
  ctx.lineTo(x+8, y2);
  ctx.moveTo(x, y2-4);
  ctx.lineTo(x+4, y2);

  ctx.moveTo(x2-12, y);
  ctx.lineTo(x2, y+12);
  ctx.moveTo(x2-8, y);
  ctx.lineTo(x2, y+8);
  ctx.moveTo(x2-4, y);
  ctx.lineTo(x2, y+4);

  ctx.strokeColor(inset);
  ctx.stroke();
}

/** Draw the join area overlay stencil into the rectangle
 * at origin (x, y) and size (w, h)
 *
 * vertical is `false` or `true` and designates the arrow orientation, mirror is `false` or `true` and flips the arrow side
 */
public void bndJoinAreaOverlay (NVGContext ctx, float x, float y, float w, float h, bool vertical, bool mirror) {
  if (vertical) {
    float u = w;
    w = h; h = u;
  }

  float s = (w < h ? w : h);

  float x0, y0, x1, y1;
  if (mirror) {
    x0 = w;
    y0 = h;
    x1 = 0;
    y1 = 0;
    s = -s;
  } else {
    x0 = 0;
    y0 = 0;
    x1 = w;
    y1 = h;
  }

  float yc = (y0+y1)*0.5f;
  float s2 = s/2.0f;
  float s4 = s/4.0f;
  float s8 = s/8.0f;
  float x4 = x0+s4;

  float[2][11] points = [
    [ x0, y0 ],
    [ x1, y0 ],
    [ x1, y1 ],
    [ x0, y1 ],
    [ x0, yc+s8 ],
    [ x4, yc+s8 ],
    [ x4, yc+s4 ],
    [ x0+s2, yc ],
    [ x4, yc-s4 ],
    [ x4, yc-s8 ],
    [ x0, yc-s8 ]
  ];

  ctx.beginPath();
  int count = cast(int)points.length; //sizeof(points)/(sizeof(float)*2);
  ctx.moveTo(x+points[0][vertical&1], y+points[0][(vertical&1)^1]);
  foreach (int i; 1..count) ctx.lineTo(x+points[i][vertical&1], y+points[i][(vertical&1)^1]);

  ctx.fillColor(nvgRGBAf(0, 0, 0, 0.3));
  ctx.fill();
}


////////////////////////////////////////////////////////////////////////////////
/// Estimator Functions
/// Use these functions to estimate sizes for widgets with your NVGcontext.

/// returns the ideal width for a label with given icon and text
public float bndLabelWidth(T=char) (NVGContext ctx, int iconid, const(T)[] label) if (isAnyCharType!T) {
  float w = BND_PAD_LEFT+BND_PAD_RIGHT;
  if (iconid >= 0) w += BND_ICON_SHEET_RES;
  if (label.length && bndRealizeFont(ctx)) {
    ctx.fontSize(BND_LABEL_FONT_SIZE);
    w += ctx.textBounds(1, 1, label, null);
  }
  return cast(float)cast(int)(w+0.5);
}

/// returns the height for a label with given icon, text and width; this function is primarily useful in conjunction with multiline labels and textboxes
public float bndLabelHeight(T=char) (NVGContext ctx, int iconid, const(T)[] label, float width) if (isAnyCharType!T) {
  float h = BND_WIDGET_HEIGHT;
  width -= BND_TEXT_RADIUS*2;
  if (iconid >= 0) width -= BND_ICON_SHEET_RES;
  if (label.length && bndRealizeFont(ctx)) {
    ctx.fontSize(BND_LABEL_FONT_SIZE);
    float[4] bounds = void;
    ctx.textBoxBounds(1, 1, width, label, bounds[]);
    float bh = (bounds[3]-bounds[1])+BND_TEXT_PAD_DOWN;
    if (bh > h) h = bh;
  }
  return cast(float)cast(int)(h+0.5);
}


////////////////////////////////////////////////////////////////////////////////
/// Low Level Functions
/// these are part of the implementation detail and can be used to theme new kinds of controls in a similar fashion.

/** Add a rounded box path at position (x, y) with size (w, h) and a separate
 * radius for each corner listed in clockwise order, so that cr0 = top left,
 * cr1 = top right, cr2 = bottom right, cr3 = bottom left;
 *
 * this is a low level drawing function: the path must be stroked or filled
 * to become visible.
 */
public void bndRoundedBox (NVGContext ctx, float x, float y, float w, float h, float cr0, float cr1, float cr2, float cr3) {
  float d;
  w = bndMax(0, w);
  h = bndMax(0, h);
  d = bndMin(w, h);
  ctx.moveTo(x, y+h*0.5f);
  ctx.arcTo(x, y, x+w, y, bndMin(cr0, d/2));
  ctx.arcTo(x+w, y, x+w, y+h, bndMin(cr1, d/2));
  ctx.arcTo(x+w, y+h, x, y+h, bndMin(cr2, d/2));
  ctx.arcTo(x, y+h, x, y, bndMin(cr3, d/2));
  ctx.closePath();
}

/// make color transparent using the default alpha value
public NVGColor bndTransparent (NVGColor color) {
  color.a *= BND_TRANSPARENT_ALPHA;
  return color;
}

/// offset a color by a given integer delta in the range -100 to 100
public NVGColor bndOffsetColor (NVGColor color, int delta) {
  float offset = cast(float)delta/255.0f;
  return (delta ? nvgRGBAf(bndClamp(color.r+offset, 0, 1), bndClamp(color.g+offset, 0, 1), bndClamp(color.b+offset, 0, 1), color.a) : color);
}

/// Draw a beveled border at position (x, y) with size (w, h) shaded with lighter and darker versions of backgroundColor
public void bndBevel (NVGContext ctx, float x, float y, float w, float h) {
  ctx.strokeWidth(1);

  x += 0.5f;
  y += 0.5f;
  w -= 1;
  h -= 1;

  ctx.beginPath();
  ctx.moveTo(x, y+h);
  ctx.lineTo(x+w, y+h);
  ctx.lineTo(x+w, y);
  ctx.strokeColor(bndTransparent(bndOffsetColor(bndTheme.backgroundColor, -BND_BEVEL_SHADE)));
  ctx.stroke();

  ctx.beginPath();
  ctx.moveTo(x, y+h);
  ctx.lineTo(x, y);
  ctx.lineTo(x+w, y);
  ctx.strokeColor(bndTransparent(bndOffsetColor(bndTheme.backgroundColor, BND_BEVEL_SHADE)));
  ctx.stroke();
}

/** Draw a lower inset for a rounded box at position (x, y) with size (w, h)
 * that gives the impression the surface has been pushed in.
 *
 * cr2 and cr3 contain the radiuses of the bottom right and bottom left
 * corners of the rounded box.
 */
public void bndBevelInset (NVGContext ctx, float x, float y, float w, float h, float cr2, float cr3) {
  float d;

  y -= 0.5f;
  d = bndMin(w, h);
  cr2 = bndMin(cr2, d/2);
  cr3 = bndMin(cr3, d/2);

  ctx.beginPath();
  ctx.moveTo(x+w, y+h-cr2);
  ctx.arcTo(x+w, y+h, x, y+h, cr2);
  ctx.arcTo(x, y+h, x, y, cr3);

  NVGColor bevelColor = bndOffsetColor(bndTheme.backgroundColor, BND_INSET_BEVEL_SHADE);

  ctx.strokeWidth(1);
  ctx.strokePaint(ctx.linearGradient(x, y+h-bndMax(cr2, cr3)-1, x, y+h-1, nvgRGBAf(bevelColor.r, bevelColor.g, bevelColor.b, 0), bevelColor));
  ctx.stroke();
}

/// Draw a flat panel without any decorations at position (x, y) with size (w, h) and fills it with backgroundColor
public void bndBackground (NVGContext ctx, float x, float y, float w, float h) {
  ctx.beginPath();
  ctx.rect(x, y, w, h);
  ctx.fillColor(bndTheme.backgroundColor);
  ctx.fill();
}

/// Draw an icon with (x, y) as its upper left coordinate; the iconid selects the icon from the sheet; use the BND_ICONID macro to build icon IDs.
public void bndIcon (NVGContext ctx, float x, float y, int iconid) {
  int ix, iy, u, v;
  if (!bndIconImage.valid) return; // no icons loaded

  ix = iconid&0xff;
  iy = (iconid>>8)&0xff;
  u = BND_ICON_SHEET_OFFSET_X+ix*BND_ICON_SHEET_GRID;
  v = BND_ICON_SHEET_OFFSET_Y+iy*BND_ICON_SHEET_GRID;

  ctx.beginPath();
  ctx.rect(x, y, BND_ICON_SHEET_RES, BND_ICON_SHEET_RES);
  ctx.fillPaint(ctx.imagePattern(x-u, y-v, BND_ICON_SHEET_WIDTH, BND_ICON_SHEET_HEIGHT, 0, bndIconImage, 1));
  ctx.fill();
}

/** Draw a drop shadow around the rounded box at (x, y) with size (w, h) and
 * radius r, with feather as its maximum range in pixels.
 *
 * No shadow will be painted inside the rounded box.
 */
public void bndDropShadow (NVGContext ctx, float x, float y, float w, float h, float r, float feather, float alpha) {
  ctx.beginPath();
  y += feather;
  h -= feather;

  ctx.moveTo(x-feather, y-feather);
  ctx.lineTo(x, y-feather);
  ctx.lineTo(x, y+h-feather);
  ctx.arcTo(x, y+h, x+r, y+h, r);
  ctx.arcTo(x+w, y+h, x+w, y+h-r, r);
  ctx.lineTo(x+w, y-feather);
  ctx.lineTo(x+w+feather, y-feather);
  ctx.lineTo(x+w+feather, y+h+feather);
  ctx.lineTo(x-feather, y+h+feather);
  ctx.closePath();

  ctx.fillPaint(ctx.boxGradient(x-feather*0.5f, y-feather*0.5f,
      w+feather, h+feather,
      r+feather*0.5f,
      feather,
      nvgRGBAf(0, 0, 0, alpha*alpha),
      nvgRGBAf(0, 0, 0, 0)));
  ctx.fill();
}

/* Draw the inner part of a widget box, with a gradient from shadeTop to
 * shadeDown. If h>w, the gradient will be horizontal instead of vertical.
 */
public void bndInnerBox (NVGContext ctx, float x, float y, float w, float h, float cr0, float cr1, float cr2, float cr3, NVGColor shadeTop, NVGColor shadeDown) {
  ctx.beginPath();
  bndRoundedBox(ctx, x+1, y+1, w-2, h-3, bndMax(0, cr0-1), bndMax(0, cr1-1), bndMax(0, cr2-1), bndMax(0, cr3-1));
  ctx.fillPaint((h-2 > w ? ctx.linearGradient(x, y, x+w, y, shadeTop, shadeDown) : ctx.linearGradient(x, y, x, y+h, shadeTop, shadeDown)));
  ctx.fill();
}

/// Draw the outline part of a widget box with the given color
public void bndOutlineBox (NVGContext ctx, float x, float y, float w, float h, float cr0, float cr1, float cr2, float cr3, NVGColor color) {
  ctx.beginPath();
  bndRoundedBox(ctx, x+0.5f, y+0.5f, w-1, h-2, cr0, cr1, cr2, cr3);
  ctx.strokeColor(color);
  ctx.strokeWidth(1);
  ctx.stroke();
}

/** assigns radius r to the four entries of array radiuses depending on whether
 * the corner is marked as sharp or not; see BNDcornerFlags for possible
 * flag values.
 */
public void bndSelectCorners (float[] radiuses, float r, int flags) {
  if (radiuses.length > 0) radiuses.ptr[0] = (flags&BND_CORNER_TOP_LEFT ? 0 : r);
  if (radiuses.length > 1) radiuses.ptr[1] = (flags&BND_CORNER_TOP_RIGHT ? 0 : r);
  if (radiuses.length > 2) radiuses.ptr[2] = (flags&BND_CORNER_DOWN_RIGHT ? 0 : r);
  if (radiuses.length > 3) radiuses.ptr[3] = (flags&BND_CORNER_DOWN_LEFT ? 0 : r);
}

/** computes the upper and lower gradient colors for the inner box from a widget
 * theme and the widgets state. If flipActive is set and the state is
 * BND_ACTIVE, the upper and lower colors will be swapped.
 */
public void bndInnerColors (NVGColor* shadeTop, NVGColor* shadeDown, const(BNDwidgetTheme)* theme, BNDwidgetState state, int flipActive) {
  switch (state) {
    default:
    case BND_DEFAULT:
      if (shadeTop !is null) *shadeTop = bndOffsetColor(theme.innerColor, theme.shadeTop);
      if (shadeDown !is null) *shadeDown = bndOffsetColor(theme.innerColor, theme.shadeDown);
      break;
    case BND_HOVER:
      NVGColor color = bndOffsetColor(theme.innerColor, BND_HOVER_SHADE);
      if (shadeTop !is null) *shadeTop = bndOffsetColor(color, theme.shadeTop);
      if (shadeDown !is null) *shadeDown = bndOffsetColor(color, theme.shadeDown);
      break;
    case BND_ACTIVE:
      if (shadeTop !is null) *shadeTop = bndOffsetColor(theme.innerSelectedColor, flipActive?theme.shadeDown:theme.shadeTop);
      if (shadeDown !is null) *shadeDown = bndOffsetColor(theme.innerSelectedColor, flipActive?theme.shadeTop:theme.shadeDown);
      break;
  }
}

/// computes the text color for a widget label from a widget theme and the widgets state.
public NVGColor bndTextColor (const(BNDwidgetTheme)* theme, BNDwidgetState state) nothrow @trusted @nogc {
  pragma(inline, true);
  return
    state == BND_ACTIVE ? theme.textSelectedColor :
    state == BND_HOVER ? (theme.textHoverColor.isTransparent ? theme.textColor : theme.textHoverColor) :
    theme.textColor;
}

/** Draw an optional icon specified by <iconid> and an optional label with
 * given alignment (BNDtextAlignment), fontsize and color within a widget box.
 *
 * if iconid is >= 0, an icon will be drawn and the labels remaining space will be adjusted.
 *
 * if label is not null, it will be drawn with the specified alignment, fontsize and color.
 *
 * if value is not null, label and value will be drawn with a ":" separator inbetween.
 */
public void bndIconLabelValue(T=char,TV=char) (NVGContext ctx, float x, float y, float w, float h, int iconid, NVGColor color, int align_, float fontsize, const(T)[] label, const(TV)[] value=null)
if (isAnyCharType!T && isAnyCharType!TV)
{
  float pleft = BND_PAD_LEFT;
  if (label.length) {
    if (iconid >= 0) {
      bndIcon(ctx, x+4, y+2, iconid);
      pleft += BND_ICON_SHEET_RES;
    }

    if (!bndRealizeFont(ctx)) return;
    ctx.fontSize(fontsize);
    ctx.beginPath();
    ctx.fillColor(color);
    if (value.length) {
      float label_width = ctx.textBounds(1, 1, label, null);
      float sep_width = ctx.textBounds(1, 1, BND_LABEL_SEPARATOR, null);

      ctx.textAlign(NVGTextAlign.H.Left, NVGTextAlign.V.Baseline);
      x += pleft;
      if (align_ == BND_CENTER) {
        float width = label_width+sep_width+ctx.textBounds(1, 1, value, null);
        x += ((w-BND_PAD_RIGHT-pleft)-width)*0.5f;
      } else if (align_ == BND_RIGHT) {
        float width = label_width+sep_width+ctx.textBounds(1, 1, value, null);
        x += w-BND_PAD_RIGHT-width;
      }
      y += BND_WIDGET_HEIGHT-BND_TEXT_PAD_DOWN;
      ctx.text(x, y, label);
      x += label_width;
      ctx.text(x, y, BND_LABEL_SEPARATOR);
      x += sep_width;
      ctx.text(x, y, value);
    } else {
      ctx.textAlign((align_ == BND_LEFT ? NVGTextAlign(NVGTextAlign.H.Left, NVGTextAlign.V.Baseline) : align_ == BND_CENTER ? NVGTextAlign(NVGTextAlign.H.Center, NVGTextAlign.V.Baseline) : NVGTextAlign(NVGTextAlign.H.Right, NVGTextAlign.V.Baseline)));
      ctx.textBox(x+pleft, y+BND_WIDGET_HEIGHT-BND_TEXT_PAD_DOWN, w-BND_PAD_RIGHT-pleft, label);
      //{ import core.stdc.stdio : printf; printf("l=%u\n", cast(uint)label.length); }
    }
  } else if (iconid >= 0) {
    bndIcon(ctx, x+2, y+2, iconid);
  }
}

/** Draw an optional icon specified by <iconid> and an optional label with
 * given alignment (BNDtextAlignment), fontsize and color within a node title bar
 *
 * if iconid is >= 0, an icon will be drawn
 *
 * if label is not null, it will be drawn with the specified alignment, fontsize and color.
 */
public void bndNodeIconLabel(T=char) (NVGContext ctx, float x, float y, float w, float h, int iconid, NVGColor color, NVGColor shadowColor, int align_, float fontsize, const(T)[] label)
if (isAnyCharType!T)
{
  if (label.length && bndRealizeFont(ctx)) {
    ctx.fontSize(fontsize);
    ctx.beginPath();
    ctx.textAlign(NVGTextAlign.H.Left, NVGTextAlign.V.Baseline);
    ctx.fillColor(shadowColor);
    ctx.fontBlur(BND_NODE_TITLE_FEATHER);
    ctx.textBox(x+1, y+h+3-BND_TEXT_PAD_DOWN, w, label);
    ctx.fillColor(color);
    ctx.fontBlur(0);
    ctx.textBox(x, y+h+2-BND_TEXT_PAD_DOWN, w, label);
  }
  if (iconid >= 0) bndIcon(ctx, x+w-BND_ICON_SHEET_RES, y+3, iconid);
}

/** Calculate the corresponding text position for given coordinates px/py in an iconLabel.
 * See bndIconLabelCaret for more info.
 */
public int bndIconLabelTextPosition(T=char) (NVGContext ctx, float x, float y, float w, float h, int iconid, float fontsize, const(T)[] label, int px, int py)
if (isAnyCharType!T)
{
  float[4] bounds;
  float pleft = BND_TEXT_RADIUS;
  if (label.length == 0) return -1;
  if (iconid >= 0) pleft += BND_ICON_SHEET_RES;

  if (!bndRealizeFont(ctx)) return -1;

  x += pleft;
  y += BND_WIDGET_HEIGHT-BND_TEXT_PAD_DOWN;

  ctx.fontSize(fontsize);
  ctx.textAlign(NVGTextAlign.H.Left, NVGTextAlign.V.Baseline);

  w -= BND_TEXT_RADIUS+pleft;

  float asc, desc, lh;
  static NVGTextRow!T[BND_MAX_ROWS] rows;
  auto rres = ctx.textBreakLines(label, w, rows[]);
  //{ import core.stdc.stdio : printf; printf("rlen=%u\n", cast(uint)rres.length); }
  if (rres.length == 0) return 0;
  ctx.textBoxBounds(x, y, w, label, bounds[]);
  ctx.textMetrics(&asc, &desc, &lh);

  // calculate vertical position
  int row = cast(int)bndClamp(cast(int)(cast(float)(py-bounds[1])/lh), 0, cast(int)rres.length-1);
  // search horizontal position
  static NVGGlyphPosition[BND_MAX_GLYPHS] glyphs;
  //int nglyphs = ctx.textGlyphPositions(x, y, rows[row].start, rows[row].end+1, glyphs.ptr, BND_MAX_GLYPHS);
  auto rglyphs = ctx.textGlyphPositions(x, y, rows[row].row!T, glyphs[]);
  int nglyphs = cast(int)rglyphs.length;
  int col, p = 0;
  for (col = 0; col < nglyphs && glyphs[col].x < px; ++col) p = cast(int)glyphs[col].strpos;
  // see if we should move one character further
  if (col > 0 && col < nglyphs && glyphs[col].x-px < px-glyphs[col-1].x) p = cast(int)glyphs[col].strpos;
  return p;
}

void bndCaretPosition(RT) (NVGContext ctx, float x, float y, float desc, float lineHeight, int caretpos, RT[] rows, int* cr, float* cx, float* cy)
if (is(RT : NVGTextRow!CT, CT))
{
  static NVGGlyphPosition[BND_MAX_GLYPHS] glyphs;
  usize r = 0;
  //for (r = 0; r < nrows && rows[r].end < caret; ++r) {}
  while (r < rows.length && rows[r].end < caretpos) ++r;
  if (cr !is null) *cr = cast(int)r;
  if (cx !is null) *cx = x;
  if (cy !is null) *cy = y-lineHeight-desc+r*lineHeight;
  if (rows.length == 0) return;
  if (cx !is null) *cx = rows[r].minx;
  //auto rglyphs = (rows[r].isChar ? ctx.textGlyphPositions(x, y, rows[r].row!char, glyphs[]) : ctx.textGlyphPositions(x, y, rows[r].row!dchar, glyphs[]));
  auto rglyphs = ctx.textGlyphPositions(x, y, rows[r].row, glyphs[]);
  foreach (immutable i; 0..rglyphs.length) {
    if (cx !is null) *cx = glyphs.ptr[i].x;
    if (glyphs.ptr[i].strpos == caretpos) break;
  }
}

/** Draw an optional icon specified by <iconid>, an optional label and
 * a caret with given fontsize and color within a widget box.
 *
 * if iconid is >= 0, an icon will be drawn and the labels remaining space will be adjusted.
 *
 * if label is not null, it will be drawn with the specified alignment, fontsize and color.
 *
 * cbegin must be >= 0 and <= strlen(text) and denotes the beginning of the caret
 *
 * cend must be >= cbegin and <= strlen(text) and denotes the end of the caret if cend < cbegin, then no caret will be drawn
 */
public void bndIconLabelCaret(T=char) (NVGContext ctx, float x, float y, float w, float h, int iconid, NVGColor color, float fontsize, const(T)[] label, NVGColor caretcolor, int cbegin, int cend, NVGColor thinCaretColor=NVGColor.black)
if (isAnyCharType!T)
{
  float pleft = BND_TEXT_RADIUS;
  if (label.length == 0) return;
  if (iconid >= 0) {
    bndIcon(ctx, x+4, y+2, iconid);
    pleft += BND_ICON_SHEET_RES;
  }

  if (!bndRealizeFont(ctx)) return;

  x += pleft;
  y += BND_WIDGET_HEIGHT-BND_TEXT_PAD_DOWN;

  ctx.fontSize(fontsize);
  ctx.textAlign(NVGTextAlign.H.Left, NVGTextAlign.V.Baseline);

  w -= BND_TEXT_RADIUS+pleft;

  if (cend >= cbegin) {
    int c0r, c1r;
    float c0x, c0y, c1x, c1y;
    float desc, lh;
    static NVGTextRow!T[BND_MAX_ROWS] rows;
    auto rrows = ctx.textBreakLines(label[0..cend], w, rows[]);
    ctx.textMetrics(null, &desc, &lh);

    bndCaretPosition(ctx, x, y, desc, lh, cbegin, rrows, &c0r, &c0x, &c0y);
    bndCaretPosition(ctx, x, y, desc, lh, cend, rrows, &c1r, &c1x, &c1y);

    ctx.beginPath();
    if (cbegin == cend) {
      //ctx.fillColor(nvgRGBf(0.337, 0.502, 0.761));
      ctx.fillColor(thinCaretColor);
      //ctx.rect(c0x-1, c0y, 2, lh+1);
      ctx.rect(c0x, c0y, 1, lh+1);
    } else {
      ctx.fillColor(caretcolor);
      if (c0r == c1r) {
        ctx.rect(c0x-1, c0y, c1x-c0x+1, lh+1);
      } else {
        int blk = c1r-c0r-1;
        ctx.rect(c0x-1, c0y, x+w-c0x+1, lh+1);
        ctx.rect(x, c1y, c1x-x+1, lh+1);
        if (blk) ctx.rect(x, c0y+lh, w, blk*lh+1);
      }
    }
    ctx.fill();
  }

  ctx.beginPath();
  ctx.fillColor(color);
  ctx.textBox(x, y, w, label);
}

/// Draw a checkmark for an option box with the given upper left coordinates (ox, oy) with the specified color.
public void bndCheck (NVGContext ctx, float ox, float oy, NVGColor color) {
  ctx.beginPath();
  ctx.strokeWidth(2);
  ctx.strokeColor(color);
  ctx.lineCap(NVGLineCap.Butt);
  ctx.lineJoin(NVGLineCap.Miter);
  ctx.moveTo(ox+4, oy+5);
  ctx.lineTo(ox+7, oy+8);
  ctx.lineTo(ox+14, oy+1);
  ctx.stroke();
}

/// Draw a checkmark for a radio with the given upper left coordinates (ox, oy) with the specified color.
public void bndRadioCheck (NVGContext ctx, float ox, float oy, NVGColor color) {
  ctx.beginPath();
  ctx.fillColor(color);
  ctx.circle(ox+7, oy+7, 3);
  ctx.fill();
}

/// Draw a horizontal arrow for a number field with its center at (x, y) and size s; if s is negative, the arrow points to the left.
public void bndArrow (NVGContext ctx, float x, float y, float s, NVGColor color) {
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.lineTo(x-s, y+s);
  ctx.lineTo(x-s, y-s);
  ctx.closePath();
  ctx.fillColor(color);
  ctx.fill();
}

/// Draw an up/down arrow for a choice box with its center at (x, y) and size s
public void bndUpDownArrow (NVGContext ctx, float x, float y, float s, NVGColor color) {
  float w;
  ctx.beginPath();
  w = 1.1f*s;
  ctx.moveTo(x, y-1);
  ctx.lineTo(x+0.5*w, y-s-1);
  ctx.lineTo(x+w, y-1);
  ctx.closePath();
  ctx.moveTo(x, y+1);
  ctx.lineTo(x+0.5*w, y+s+1);
  ctx.lineTo(x+w, y+1);
  ctx.closePath();
  ctx.fillColor(color);
  ctx.fill();
}

/// Draw a node down-arrow with its tip at (x, y) and size s
public void bndNodeArrowDown (NVGContext ctx, float x, float y, float s, NVGColor color) {
  float w;
  ctx.beginPath();
  w = 1.0f*s;
  ctx.moveTo(x, y);
  ctx.lineTo(x+0.5*w, y-s);
  ctx.lineTo(x-0.5*w, y-s);
  ctx.closePath();
  ctx.fillColor(color);
  ctx.fill();
}

/** computes the bounds of the scrollbar handle from the scrollbar size and the handles offset and size.
 *
 * offset is in the range 0..1 and defines the position of the scroll handle
 *
 * size is in the range 0..1 and defines the size of the scroll handle
 */
public void bndScrollHandleRect (float* x, float* y, float* w, float* h, float offset, float size) {
  assert(w !is null);
  assert(h !is null);
  size = bndClamp(size, 0, 1);
  offset = bndClamp(offset, 0, 1);
  if (*h > *w) {
    immutable float hs = bndMax(size*(*h), (*w)+1);
    if (y !is null) *y = (*y)+((*h)-hs)*offset;
    *h = hs;
  } else {
    immutable float ws = bndMax(size*(*w), (*h)-1);
    if (x !is null) *x = (*x)+((*w)-ws)*offset;
    *w = ws;
  }
}

/** computes the bounds of the scroll slider from the scrollbar size and the handles offset and size.
 *
 * offset is in the range 0..1 and defines the position of the scroll handle
 *
 * size is in the range 0..1 and defines the size of the scroll handle
 */
public void bndScrollSliderRect (float* w, float* h, float offset, float size) {
  assert(w !is null);
  assert(h !is null);
  size = bndClamp(size, 0, 1);
  offset = bndClamp(offset, 0, 1);
  if (*h > *w) {
    immutable float hs = bndMax(size*(*h), (*w)+1);
    *h = ((*h)-hs)*offset+hs;
  } else {
    immutable float ws = bndMax(size*(*w), (*h)-1);
    *w = ((*w)-ws)*offset+ws;
  }
}

/** return the color of a node wire based on state
 *
 * BND_HOVER indicates selected state,
 *
 * BND_ACTIVE indicates dragged state
 */
public NVGColor bndNodeWireColor (const(BNDnodeTheme)* theme, BNDwidgetState state) {
  switch (state) {
    default:
    case BND_DEFAULT: return nvgRGBf(0.5f, 0.5f, 0.5f);
    case BND_HOVER: return theme.wireSelectColor;
    case BND_ACTIVE: return theme.activeNodeColor;
  }
}
