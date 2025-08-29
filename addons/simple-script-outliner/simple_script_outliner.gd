@tool
class_name SimpleScriptOutliner extends EditorPlugin

# Editor Settings
var editor_settings: EditorSettings = initialize_outliner_editor_settings()

var outliner_position: OutlinerPosition
enum OutlinerPosition {SCRIPTS_PANEL,LEFT_SIDE,RIGHT_SIDE}

var hide_method_list: bool

var place_cursor_at: CursorPosition
enum CursorPosition {BEGINNING_OF_LINE,END_OF_LINE}

var scroll_view_to: ViewScrollPosition
enum ViewScrollPosition {TOP_OF_SCREEN,MIDDLE_OF_SCREEN}

var blacklist: PackedStringArray

# Outline UI
var outline_ui: VBoxContainer
var outline_items_list: RichTextItemList
var outline_search_field: LineEdit
var filter_string: String = ""

# Script Editor UI Components.
var script_editor: ScriptEditor = EditorInterface.get_script_editor()
var script_editor_base: ScriptEditorBase
var script_editor_split_container: HSplitContainer
var script_editor_scripts_panel: VSplitContainer
var script_editor_method_list: VBoxContainer
var script_editor_main_container: VBoxContainer

var script_editor_new_h_split: HSplitContainer
var script_editor_new_v_split: VSplitContainer

var scripts_panel_horizontal_size: int = 0

var debug_enabled: bool = false
var debug_ui: VBoxContainer

const DEFAULT_OUTLINE_PANEL_WIDTH: float = 250.0
const DEFAULT_OUTLINE_PANEL_HEIGHT: float = -250.0

func _enter_tree() -> void:
  # When refreshing tree, wait for outline_ui to free.
  if is_instance_valid(outline_ui) and outline_ui.is_queued_for_deletion():
    await outline_ui.tree_exited
  
  # Find and assign our default editor nodes.
  if !get_default_editor_nodes(): return
  
  # Remove Stock Method Editor
  if hide_method_list:
    script_editor_scripts_panel.remove_child(script_editor_method_list)
  
  # New Split Containers Setup.
  match outliner_position:
    OutlinerPosition.SCRIPTS_PANEL:
      
      if !hide_method_list:
        # Add a new split to the scripts panel.
        split_scripts_panel()
        
        var restored_outline_panel_height: float = load_panel_height_from_config()
        call_deferred("set_current_outline_panel_height", restored_outline_panel_height) # FIXME - Is Call Deferred still needed here? We have an await now.
      
    OutlinerPosition.LEFT_SIDE, OutlinerPosition.RIGHT_SIDE:
      # Connect to the scripts_panel's size changes, so we can resize our HSplitContainer to match.
      scripts_panel_horizontal_size = script_editor_scripts_panel.size.x
      script_editor_scripts_panel.item_rect_changed.connect(_on_scripts_panel_resize)
      # FIXME - Still not getting size right on startup.
      
      # Add a new split to the script editor.
      split_script_editor()
      
      # Load previous width from config, because _set_window_layout only occurs on Editor's launch.
      var restored_outline_panel_width: float = load_panel_width_from_config()
      call_deferred("set_current_outline_panel_width", restored_outline_panel_width) # FIXME - Is Call Deferred still needed here? We have an await now.
  
  build_outline_ui()
  
  # Add Outliner to Editor UI
  match outliner_position:
    OutlinerPosition.SCRIPTS_PANEL:
      if !hide_method_list:
        script_editor_new_v_split.add_child(outline_ui)
      else:
        script_editor_scripts_panel.add_child(outline_ui)
    OutlinerPosition.LEFT_SIDE:
      script_editor_new_h_split.add_child(outline_ui)
      script_editor_new_h_split.move_child(outline_ui, 0)
    OutlinerPosition.RIGHT_SIDE:
      script_editor_new_h_split.add_child(outline_ui)
  
  # Add Debug UI if enabled.
  if debug_enabled:
    #build_debug_ui()
    #add_control_to_dock(DOCK_SLOT_RIGHT_UL, debug_ui)
    #debug_ui.set_focus_mode(Control.FOCUS_ALL)
    #debug_ui.grab_focus()
    var refresh_button = Button.new()
    refresh_button.text = "Refresh Tree"
    outline_ui.add_child(refresh_button)
    refresh_button.pressed.connect(refresh_tree)
  
  # Update List with initial contents.
  update_list()

func _exit_tree() -> void:
  # Disconnect Signals
  script_editor.editor_script_changed.disconnect(_on_editor_script_changed)
  if outliner_position in [OutlinerPosition.LEFT_SIDE, OutlinerPosition.RIGHT_SIDE]:
    script_editor_scripts_panel.item_rect_changed.disconnect(_on_scripts_panel_resize)
  
  # Restore Stock Method Editor
  if !script_editor_method_list.is_inside_tree():
    script_editor_scripts_panel.add_child(script_editor_method_list)
  
  # Remove our custom splits.
  match outliner_position:
    OutlinerPosition.SCRIPTS_PANEL:
      if !hide_method_list:
        unsplit_scripts_panel()
    OutlinerPosition.LEFT_SIDE, OutlinerPosition.RIGHT_SIDE:
      unsplit_script_editor()
  
  # Remove outline_ui
  outline_ui.queue_free()
  
  # Remove debug_ui
  #if debug_enabled:
    #remove_control_from_docks(debug_ui)
    #debug_ui.queue_free()

func _on_editor_settings_changed() -> void:
  var changed_settings = editor_settings.get_changed_settings()
  
  for setting: String in changed_settings:
    match setting:
      "plugin/outliner/outliner_position":
        _exit_tree()
        outliner_position = editor_settings.get_setting("plugin/outliner/outliner_position")
        _enter_tree()
        continue
      "plugin/outliner/hide_method_list":
        _exit_tree()
        hide_method_list = editor_settings.get_setting("plugin/outliner/hide_method_list")
        _enter_tree()
        continue
      "plugin/outliner/place_cursor_at":
        place_cursor_at = editor_settings.get_setting("plugin/outliner/place_cursor_at")
        continue
      "plugin/outliner/scroll_view_to":
        scroll_view_to = editor_settings.get_setting("plugin/outliner/scroll_view_to")
        continue
      "plugin/outliner/blacklist_lines_beginning_with":
        blacklist = editor_settings.get_setting("plugin/outliner/blacklist_lines_beginning_with")
        update_list()
        continue

func _on_editor_script_changed(_script: Script) -> void:
  if script_editor_base and script_editor_base.edited_script_changed.is_connected(update_list):
    script_editor_base.edited_script_changed.disconnect(update_list)
  
  script_editor_base = script_editor.get_current_editor()
  script_editor_base.edited_script_changed.connect(update_list)
  update_list()

func _on_rich_text_list_item_pressed(line_number: int) -> void:
  var code_edit = script_editor_base.get_base_editor()
  script_editor.goto_line(line_number)
  
  code_edit.set_caret_line(line_number)
  
  match scroll_view_to:
    ViewScrollPosition.TOP_OF_SCREEN:
      code_edit.set_v_scroll(line_number)
    ViewScrollPosition.MIDDLE_OF_SCREEN:
      code_edit.set_v_scroll(line_number - (code_edit.get_visible_line_count() / 2))
  
  match place_cursor_at:
    CursorPosition.BEGINNING_OF_LINE:
      code_edit.set_caret_column(0)
    CursorPosition.END_OF_LINE:
      code_edit.set_caret_column(code_edit.get_line(line_number).length())
  
  code_edit.grab_focus()

func _on_outline_search_field_text_changed(_new_text: String) -> void:
  filter_string = outline_search_field.text
  update_list()

func _on_scripts_panel_resize() -> void:
  var size_delta: int = scripts_panel_horizontal_size - script_editor_scripts_panel.size.x
  scripts_panel_horizontal_size = script_editor_scripts_panel.size.x
  script_editor_new_h_split.split_offset += size_delta

func _on_new_split_dragged(_offset: int) -> void:
  queue_save_layout()

func refresh_tree() -> void:
  _exit_tree()
  _enter_tree()

func split_script_editor() -> void:
  script_editor_new_h_split = HSplitContainer.new()
  script_editor_split_container.add_child(script_editor_new_h_split)
  script_editor_main_container.reparent(script_editor_new_h_split)
  script_editor_new_h_split.dragged.connect(_on_new_split_dragged)

func unsplit_script_editor() -> void:
  script_editor_main_container.reparent(script_editor_split_container)
  #script_editor_split_container.remove_child(script_editor_new_h_split)
  script_editor_new_h_split.queue_free()

func split_scripts_panel() -> void:
  script_editor_new_v_split = VSplitContainer.new()
  script_editor_scripts_panel.add_child(script_editor_new_v_split)
  script_editor_method_list.reparent(script_editor_new_v_split)
  script_editor_new_v_split.dragged.connect(_on_new_split_dragged)

func unsplit_scripts_panel() -> void:
  script_editor_method_list.reparent(script_editor_scripts_panel)
  #script_editor_scripts_panel.remove_child(script_editor_new_v_split)
  script_editor_new_v_split.queue_free()

func get_default_editor_nodes() -> bool:
  # Find Editor Nodes.
  script_editor_split_container = script_editor.find_children("*", "HSplitContainer", true, false)[0]
  script_editor_scripts_panel = script_editor_split_container.find_children("*", "VSplitContainer", false, false)[0]
  script_editor_method_list = script_editor_scripts_panel.find_children("*", "VBoxContainer", false, false)[1]
  script_editor_main_container = script_editor_split_container.find_children("*", "VBoxContainer", false, false)[0]
  
  # Refresh Editor Base on Script Changed Signal
  script_editor_base = script_editor.get_current_editor()
  script_editor.editor_script_changed.connect(_on_editor_script_changed)
  
  # Bail if we can't find the default editor nodes.
  if not (
    script_editor_split_container and \
    script_editor_scripts_panel and \
    script_editor_method_list and \
    script_editor_main_container
    ):
    push_error("Simple Script Outliner: Something went wrong, couldn't find the right editor nodes.  \
    This likely means either Godot has been updated in a way that isn't yet supported, or \
    another plugin is already modifying the interface.")
    return false
  return true
  
  # NOTE - Default Tree Layout
    # script_editor_split_container
      # script_editor_scripts_panel
        # script_editor_method_list
      # script_editor_main_container
    
    # In Left Side and Right Side Position, Outliner
    # replaces main_container and reparents main_container inside of itself.
    # In Scripts Panel Position, Outliner is added as a child of the scripts_panel,
    # either below the method_list, or reparenting the method_list inside of itself.

func build_outline_ui() -> void:
  # Create Outline UI
  outline_ui = VBoxContainer.new()
  
  outline_search_field = LineEdit.new()
  outline_search_field.placeholder_text = "Filter Lines"
  outline_search_field.right_icon = preload("uid://bnpp35i5gm2m7")
  outline_search_field.text_changed.connect(_on_outline_search_field_text_changed)
  
  
  var panel: Panel = Panel.new()
  panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
  panel.custom_minimum_size = Vector2(100.0, 60.0)
  
  
  var scroll_container = ScrollContainer.new()
  scroll_container.set_anchors_preset(Control.PRESET_FULL_RECT)
  
  outline_items_list = RichTextItemList.new()
  outline_items_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  
  # Assemble Outline UI Tree
  outline_ui.add_child(outline_search_field)
  outline_ui.add_child(panel)
  panel.add_child(scroll_container)
  scroll_container.add_child(outline_items_list)

# TESTING - Not a great experience, because of re-adding the docker every refresh.
func build_debug_ui() -> void:
  # Create Outline UI
  debug_ui = VBoxContainer.new()
  debug_ui.name = "Outliner Debug"
  
  var refresh_button = Button.new()
  refresh_button.text = "Refresh Tree"
  debug_ui.add_child(refresh_button)
  refresh_button.pressed.connect(refresh_tree)
    
  var print_important_lines_button = Button.new()
  print_important_lines_button.text = "Print Important Lines"
  debug_ui.add_child(print_important_lines_button)
  #print_important_lines_button.pressed.connect()
  
  var print_whole_script_button = Button.new()
  print_whole_script_button.text = "Print Whole Script"
  debug_ui.add_child(print_whole_script_button)
  #print_whole_script_button.pressed.connect()

func update_list() -> void:
  if !script_editor_base: return
  var code_edit = script_editor_base.get_base_editor()
  var source_code: String = code_edit.text
  var lines: PackedStringArray = source_code.split("\n")
  
  var important_lines: Dictionary[int, String] = {}
  var index: int = 0
  for line: String in lines:
    
    # Skip empty lines.
    if !line.length():
      index += 1
      continue
    
    # Skip lines that start with whitespace and comments.
    if line.left(1) in [" ", "	", "#"]:
      index += 1
      continue
    
    # Skip lines the user has blacklisted.
    var should_skip: bool = false
    for string in blacklist:
      if string and line.begins_with(string):
        should_skip = true
        break
    if should_skip:
      index += 1
      continue
    
    # Filter lines if there's a search string.
    if filter_string and !line.containsn(filter_string):
      index += 1
      continue
    
    # Add line and increase index.
    important_lines[index] = line
    index += 1
  
  # Update List Items
  outline_items_list.clear()
  for line_number: int in important_lines:
    var line_string = code_edit.get_line(line_number)
    var color_info = code_edit.syntax_highlighter.get_line_syntax_highlighting(line_number)
    var colorized_string = colorize_string(line_string, color_info)
    
    var item_index: int = outline_items_list.add_item(colorized_string, line_number)
    if !outline_items_list.get_item(item_index).pressed_with_metadata.is_connected(_on_rich_text_list_item_pressed):
      outline_items_list.get_item(item_index).pressed_with_metadata.connect(_on_rich_text_list_item_pressed)

func colorize_string(string: String, color_info: Dictionary) -> String:
  var prev_key: int = string.length()
  var last_index: int = color_info.size() - 1
  const closing_tag: String = "[/color]"
  for i: int in range(last_index, -1, -1):
    var start_position: int = color_info.keys()[i]
    var end_position: int = prev_key
    var color: Color = color_info.values()[i].values()[0]
    var color_hex: String = color.to_html()
    var color_tag: String = "[color=#" + color_hex + "]"
    string = string.insert(end_position, closing_tag)
    string = string.insert(start_position, color_tag)
    
    prev_key = start_position
  return string

func initialize_outliner_editor_settings() -> EditorSettings:
  var _editor_settings: EditorSettings = EditorInterface.get_editor_settings()
  
  # Initialize Settings
  initialize_editor_setting("plugin/outliner/outliner_position", 0, TYPE_INT, PROPERTY_HINT_ENUM, "Scripts Panel,Left Side,Right Side")
  initialize_editor_setting("plugin/outliner/hide_method_list", true, TYPE_BOOL)
  initialize_editor_setting("plugin/outliner/place_cursor_at", 0, TYPE_INT, PROPERTY_HINT_ENUM, "Beginning of Line,End of Line")
  initialize_editor_setting("plugin/outliner/scroll_view_to", 1, TYPE_INT, PROPERTY_HINT_ENUM, "Top of Screen,Middle of Screen")
  initialize_editor_setting("plugin/outliner/blacklist_lines_beginning_with", PackedStringArray(), TYPE_PACKED_STRING_ARRAY)
  
  # Fetch Settings
  outliner_position = _editor_settings.get_setting("plugin/outliner/outliner_position")
  hide_method_list = _editor_settings.get_setting("plugin/outliner/hide_method_list")
  place_cursor_at = _editor_settings.get_setting("plugin/outliner/place_cursor_at")
  scroll_view_to = _editor_settings.get_setting("plugin/outliner/scroll_view_to")
  blacklist = _editor_settings.get_setting("plugin/outliner/blacklist_lines_beginning_with")
  
  # Connect to settings_changed
  if !_editor_settings.settings_changed.is_connected(_on_editor_settings_changed):
    _editor_settings.settings_changed.connect(_on_editor_settings_changed)
  
  return _editor_settings

func initialize_editor_setting(key_path: StringName, value: Variant, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "", update_current: bool = false) -> void:
  var _editor_settings: EditorSettings = EditorInterface.get_editor_settings()
  if not _editor_settings.has_setting(key_path):
    _editor_settings.set(key_path, value)
  _editor_settings.set_initial_value(key_path, value, update_current)
    
  var property_info: Dictionary = {
    "name": key_path,
    "type": type,
    "hint": hint,
    "hint_string": hint_string
  }
  _editor_settings.add_property_info(property_info)

func set_current_outline_panel_height(height: float) -> void:
  if outliner_position == OutlinerPosition.SCRIPTS_PANEL and !hide_method_list:
    script_editor_new_v_split.split_offset = height

func get_current_outline_panel_height() -> float:
  if outliner_position == OutlinerPosition.SCRIPTS_PANEL and !hide_method_list:
    return script_editor_new_v_split.split_offset
  return DEFAULT_OUTLINE_PANEL_HEIGHT

func set_current_outline_panel_width(width: float) -> void:
  match outliner_position:
    OutlinerPosition.LEFT_SIDE:
      script_editor_new_h_split.split_offset = width
    OutlinerPosition.RIGHT_SIDE:
      # Await having a size, because we need it for the right side calculation.
      while !script_editor_new_h_split.size:
        await get_tree().process_frame
      script_editor_new_h_split.split_offset = script_editor_new_h_split.size.x - width

func get_current_outline_panel_width() -> float:
  var width: float = DEFAULT_OUTLINE_PANEL_WIDTH
  match outliner_position:
    OutlinerPosition.LEFT_SIDE:
      width = script_editor_new_h_split.split_offset
    OutlinerPosition.RIGHT_SIDE: 
      width = script_editor_new_h_split.size.x - script_editor_new_h_split.split_offset
  return width

func _set_window_layout(configuration: ConfigFile) -> void:
  var width: float = configuration.get_value("SimpleScriptOutliner", "outline_panel_width", DEFAULT_OUTLINE_PANEL_WIDTH)
  var height: float = configuration.get_value("SimpleScriptOutliner", "outline_panel_height", DEFAULT_OUTLINE_PANEL_HEIGHT)
  set_current_outline_panel_width(width)
  set_current_outline_panel_width(height)

func _get_window_layout(configuration: ConfigFile) -> void:
  configuration.set_value("SimpleScriptOutliner", "outline_panel_width", get_current_outline_panel_width())
  configuration.set_value("SimpleScriptOutliner", "outline_panel_height", get_current_outline_panel_height())

func load_panel_width_from_config() -> float:
  var config = ConfigFile.new()
  var error: Error = config.load("res://.godot/editor/editor_layout.cfg")
  
  if error:
    if debug_enabled: 
      push_error("Error reading editor_layout.cfg: ", error_string(error))
    return DEFAULT_OUTLINE_PANEL_WIDTH
  
  return config.get_value("SimpleScriptOutliner", "outline_panel_width", DEFAULT_OUTLINE_PANEL_WIDTH)

func load_panel_height_from_config() -> float:
  var config = ConfigFile.new()
  var error: Error = config.load("res://.godot/editor/editor_layout.cfg")
  
  if error:
    if debug_enabled: 
      push_error("Error reading editor_layout.cfg: ", error_string(error))
    return DEFAULT_OUTLINE_PANEL_HEIGHT
  
  return config.get_value("SimpleScriptOutliner", "outline_panel_height", DEFAULT_OUTLINE_PANEL_HEIGHT)
