@tool
class_name RichTextItemList extends VBoxContainer

var list_items: Array[RichTextListItem] = []
var spare_list_items: Array[RichTextListItem] = []

func add_item(text: String, metadata: Variant = null) -> int:
  if spare_list_items.is_empty():
    var new_item: RichTextListItem = RichTextListItem.new()
    new_item.item_selected.connect(_on_list_item_selected)
    spare_list_items.append(new_item)
  
  var new_item: RichTextListItem = spare_list_items.pop_back()
  new_item.set_item(text, metadata)
  
  list_items.append(new_item)
  add_child(new_item)
  
  return list_items.size() - 1

func get_item(idx: int) -> RichTextListItem:
  return list_items[idx]

func move_item(from_idx: int, to_idx: int) -> void:
  var item: RichTextListItem = list_items.pop_at(from_idx)
  list_items.insert(to_idx, item)
  move_child(item, to_idx)

func remove_item(idx: int) -> void:
  var item: RichTextListItem = list_items.pop_at(idx)
  item.clear()
  spare_list_items.append(item)
  remove_child(item)

func clear() -> void:
  # NOTE - We iterate backwards here to avoid index changes, instead of using a while loop.
  for idx in range(list_items.size() - 1, -1, -1):
    remove_item(idx)

func _on_list_item_selected(selected_node: RichTextListItem) -> void:
  for item_node: RichTextListItem in list_items:
    if item_node != selected_node:
      item_node.selected = false
