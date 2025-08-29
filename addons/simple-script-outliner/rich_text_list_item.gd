@tool
class_name RichTextListItem extends Button

var rich_text_label: RichTextLabel = RichTextLabel.new()
var metadata: Variant
var selected: bool = false: set = set_selected

var stylebox_plain: StyleBox = EditorInterface.get_base_control().get_theme_stylebox("cursor", "ItemList")
var stylebox_hovered: StyleBox = EditorInterface.get_base_control().get_theme_stylebox("hovered", "ItemList")
var stylebox_selected: StyleBox = EditorInterface.get_base_control().get_theme_stylebox("selected", "ItemList")
var stylebox_selected_focus: StyleBox = EditorInterface.get_base_control().get_theme_stylebox("selected_focus", "ItemList")
var stylebox_hovered_selected: StyleBox = EditorInterface.get_base_control().get_theme_stylebox("hovered_selected", "ItemList")

signal pressed_with_metadata(metadata: Variant)
signal item_selected(self_node: RichTextListItem)

func _init() -> void:
  # Set Button Properties
  set_anchors_preset(PRESET_TOP_WIDE)
  clip_contents = true
  pressed.connect(_on_pressed)
  mouse_entered.connect(_on_mouse_entered)
  mouse_exited.connect(_on_mouse_exited)
  
  # Set RichTextLabel Properties
  rich_text_label.custom_minimum_size.y = 20
  rich_text_label.bbcode_enabled = true
  rich_text_label.fit_content = true
  rich_text_label.autowrap_mode = TextServer.AUTOWRAP_OFF
  rich_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
  rich_text_label.set_anchors_preset(PRESET_FULL_RECT)
  rich_text_label.mouse_filter = Control.MOUSE_FILTER_PASS
  rich_text_label.item_rect_changed.connect(_on_rich_text_label_item_rect_changed)
  rich_text_label.add_theme_stylebox_override("normal", stylebox_plain)
  
  # Set Button Styleboxes
  add_theme_stylebox_override("focus", stylebox_hovered)
  add_theme_stylebox_override("hover_pressed", stylebox_selected_focus)
  add_theme_stylebox_override("hover_pressed_mirrored", stylebox_selected_focus)
  add_theme_stylebox_override("hover", stylebox_hovered)
  add_theme_stylebox_override("hover_mirrored", stylebox_hovered)
  add_theme_stylebox_override("pressed", stylebox_selected)
  add_theme_stylebox_override("pressed_mirrored", stylebox_selected)
  add_theme_stylebox_override("normal", stylebox_plain)
  add_theme_stylebox_override("normal_mirrored", stylebox_plain)
  
  # Add RichTextLabel as child.
  add_child(rich_text_label)

func _ready() -> void:
  _set_minimum_height()

func set_item(text: String, _metadata: Variant = null) -> void:
  rich_text_label.text = text
  metadata = _metadata

func clear() -> void:
  rich_text_label.text = ""
  metadata = null

func _set_minimum_height() -> void:
  custom_minimum_size.y = rich_text_label.size.y

func set_selected(new_value) -> void:
  selected = new_value
  if selected:
    add_theme_stylebox_override("normal", stylebox_selected)
    add_theme_stylebox_override("hover", stylebox_hovered_selected)
    item_selected.emit(self)
  else:
    add_theme_stylebox_override("normal", stylebox_plain)
    add_theme_stylebox_override("hover", stylebox_hovered)

# NOTE - I would prefer to hook directly into "hover", but there's no signal for it.
# Internally, Godot sets hover status on mouse enter/exit, so this should be fine.
func _on_mouse_entered() -> void:
  rich_text_label.modulate = Color(1.25, 1.25, 1.25)

func _on_mouse_exited() -> void:
  rich_text_label.modulate = Color(1.0, 1.0, 1.0)

func _on_pressed() -> void:
  selected = true
  pressed_with_metadata.emit(metadata)

func _on_rich_text_label_item_rect_changed() -> void:
  _set_minimum_height()
