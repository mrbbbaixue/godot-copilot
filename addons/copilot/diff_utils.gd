@tool
extends RefCounted

## Utility class for parsing and applying unified diff format changes

const LOOKAHEAD_LINES = 5


## Parse a unified diff and return a list of hunks
## Each hunk is a dictionary with: start_line, delete_count, insert_lines
static func parse_diff(diff_text: String) -> Array:
	var hunks := []
	var lines := diff_text.split("\n")
	var i := 0
	
	while i < lines.size():
		var line := lines[i]
		
		# Look for hunk header: @@ -start,count +start,count @@
		if line.begins_with("@@"):
			var hunk := _parse_hunk_header(line)
			if hunk.is_empty():
				i += 1
				continue
			
			var delete_lines := []
			var insert_lines := []
			i += 1
			
			# Parse hunk content
			while i < lines.size():
				var content_line := lines[i]
				if content_line.begins_with("@@") or content_line.begins_with("diff ") or content_line.begins_with("---") or content_line.begins_with("+++"):
					break
				
				if content_line.begins_with("-"):
					delete_lines.append(content_line.substr(1))
				elif content_line.begins_with("+"):
					insert_lines.append(content_line.substr(1))
				elif content_line.begins_with(" ") or content_line.is_empty():
					# Context line - if we had accumulated changes, process them
					pass
				
				i += 1
			
			hunk["delete_lines"] = delete_lines
			hunk["insert_lines"] = insert_lines
			hunks.append(hunk)
		else:
			i += 1
	
	return hunks


## Parse hunk header like "@@ -1,5 +1,6 @@"
static func _parse_hunk_header(header: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("@@\\s*-(?<old_start>\\d+)(?:,(?<old_count>\\d+))?\\s+\\+(?<new_start>\\d+)(?:,(?<new_count>\\d+))?\\s*@@")
	var result := regex.search(header)
	
	if not result:
		return {}
	
	return {
		"old_start": int(result.get_string("old_start")),
		"old_count": int(result.get_string("old_count")) if result.get_string("old_count") else 1,
		"new_start": int(result.get_string("new_start")),
		"new_count": int(result.get_string("new_count")) if result.get_string("new_count") else 1,
	}


## Apply a unified diff to the original code
## Returns the modified code, or empty string on failure
static func apply_diff(original_code: String, diff_text: String) -> Dictionary:
	# First, try to extract diff from markdown code block if present
	var actual_diff := _extract_diff_from_markdown(diff_text)
	if actual_diff.is_empty():
		actual_diff = diff_text
	
	var original_lines := original_code.split("\n")
	var result_lines := original_lines.duplicate()
	var lines := actual_diff.split("\n")
	var total_offset := 0  # Track cumulative line offset due to insertions/deletions
	
	var i := 0
	while i < lines.size():
		var line := lines[i]
		
		# Look for hunk header
		if line.begins_with("@@"):
			var hunk := _parse_hunk_header(line)
			if hunk.is_empty():
				i += 1
				continue
			
			# Parse all lines in this hunk first
			var hunk_operations := []  # Array of {type: "context"|"delete"|"add", content: String}
			i += 1
			
			while i < lines.size():
				var content_line := lines[i]
				if content_line.begins_with("@@") or content_line.begins_with("diff ") or content_line.begins_with("---") or content_line.begins_with("+++"):
					break
				
				if content_line.begins_with("-"):
					hunk_operations.append({"type": "delete", "content": content_line.substr(1)})
				elif content_line.begins_with("+"):
					hunk_operations.append({"type": "add", "content": content_line.substr(1)})
				elif content_line.begins_with(" "):
					hunk_operations.append({"type": "context", "content": content_line.substr(1)})
				elif content_line.is_empty():
					# Empty line in diff - treat as empty context line
					hunk_operations.append({"type": "context", "content": ""})
				
				i += 1
			
			# Apply the hunk operations
			var current_line = hunk["old_start"] - 1 + total_offset  # 0-indexed with offset
			var hunk_offset := 0
			
			for op in hunk_operations:
				if op["type"] == "context":
					# Verify context line matches (with fuzzy matching)
					if current_line < result_lines.size():
						if result_lines[current_line].strip_edges() != op["content"].strip_edges():
							return {"success": false, "error": "Context line %d mismatch: expected '%s', got '%s'" % [current_line + 1, op["content"].strip_edges(), result_lines[current_line].strip_edges()]}
					current_line += 1
				elif op["type"] == "delete":
					# Verify and delete line
					if current_line >= result_lines.size():
						return {"success": false, "error": "Line %d does not exist in original code" % (current_line + 1)}
					if result_lines[current_line].strip_edges() != op["content"].strip_edges():
						return {"success": false, "error": "Line %d mismatch: expected '%s', got '%s'" % [current_line + 1, op["content"].strip_edges(), result_lines[current_line].strip_edges()]}
					result_lines.remove_at(current_line)
					hunk_offset -= 1
				elif op["type"] == "add":
					# Insert new line
					result_lines.insert(current_line, op["content"])
					current_line += 1
					hunk_offset += 1
			
			total_offset += hunk_offset
		else:
			i += 1
	
	return {"success": true, "error": "", "code": "\n".join(result_lines)}


## Extract diff content from markdown code block
static func _extract_diff_from_markdown(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("```(?:diff)?\\s*\\n([\\s\\S]*?)\\n```")
	var result := regex.search(text)
	if result:
		return result.get_string(1)
	return ""


## Check if a response contains a diff format
static func contains_diff(text: String) -> bool:
	# Look for diff markers
	return text.contains("@@") and (text.contains("\n-") or text.contains("\n+"))


## Generate a unified diff between two texts using LCS-based algorithm
static func generate_diff(old_text: String, new_text: String) -> String:
	var old_lines := old_text.split("\n")
	var new_lines := new_text.split("\n")
	
	# Use simple diff algorithm to find changes
	var diff_ops := _compute_diff_operations(old_lines, new_lines)
	
	if diff_ops.is_empty():
		return ""  # No changes
	
	var diff := "--- original\n+++ modified\n"
	
	# Group operations into hunks
	var hunks := _group_into_hunks(diff_ops, old_lines, new_lines)
	
	# Format each hunk
	for hunk in hunks:
		var old_start: int = hunk["old_start"]
		var old_count: int = hunk["old_count"]
		var new_start: int = hunk["new_start"]
		var new_count: int = hunk["new_count"]
		var operations: Array = hunk["operations"]
		
		diff += "@@ -%d,%d +%d,%d @@\n" % [old_start, old_count, new_start, new_count]
		
		for op in operations:
			if op["type"] == "context":
				diff += " " + op["line"] + "\n"
			elif op["type"] == "delete":
				diff += "-" + op["line"] + "\n"
			elif op["type"] == "add":
				diff += "+" + op["line"] + "\n"
	
	return diff


## Compute diff operations using a simple algorithm
static func _compute_diff_operations(old_lines: Array, new_lines: Array) -> Array:
	var operations := []
	var old_idx := 0
	var new_idx := 0
	
	while old_idx < old_lines.size() or new_idx < new_lines.size():
		if old_idx < old_lines.size() and new_idx < new_lines.size():
			if old_lines[old_idx] == new_lines[new_idx]:
				# Lines are equal - context
				operations.append({"type": "equal", "old_idx": old_idx, "new_idx": new_idx, "line": old_lines[old_idx]})
				old_idx += 1
				new_idx += 1
			else:
				# Lines differ - find best match
				var old_match := _find_line(new_lines[new_idx], old_lines, old_idx + 1)
				var new_match := _find_line(old_lines[old_idx], new_lines, new_idx + 1)
				
				if old_match != -1 and (new_match == -1 or old_match - old_idx <= new_match - new_idx):
					# Delete old lines until we reach the match
					while old_idx < old_match:
						operations.append({"type": "delete", "old_idx": old_idx, "line": old_lines[old_idx]})
						old_idx += 1
				elif new_match != -1:
					# Add new lines until we reach the match
					while new_idx < new_match:
						operations.append({"type": "add", "new_idx": new_idx, "line": new_lines[new_idx]})
						new_idx += 1
				else:
					# No match found - replace
					operations.append({"type": "delete", "old_idx": old_idx, "line": old_lines[old_idx]})
					operations.append({"type": "add", "new_idx": new_idx, "line": new_lines[new_idx]})
					old_idx += 1
					new_idx += 1
		elif old_idx < old_lines.size():
			# Only old lines remaining - delete
			operations.append({"type": "delete", "old_idx": old_idx, "line": old_lines[old_idx]})
			old_idx += 1
		else:
			# Only new lines remaining - add
			operations.append({"type": "add", "new_idx": new_idx, "line": new_lines[new_idx]})
			new_idx += 1
	
	return operations


## Group diff operations into hunks with context
static func _group_into_hunks(operations: Array, old_lines: Array, new_lines: Array) -> Array:
	var hunks := []
	var context_lines := 3
	
	var current_hunk := null
	var old_line := 0
	var new_line := 0
	var pending_context := []
	
	for op in operations:
		if op["type"] == "equal":
			if current_hunk != null:
				# Add context after changes
				current_hunk["operations"].append({"type": "context", "line": op["line"]})
				current_hunk["old_count"] += 1
				current_hunk["new_count"] += 1
				pending_context.append(op)
				
				# Check if we have enough trailing context to close the hunk
				if pending_context.size() >= context_lines:
					hunks.append(current_hunk)
					current_hunk = null
					pending_context.clear()
			else:
				# Accumulate context before changes
				pending_context.append(op)
				if pending_context.size() > context_lines:
					pending_context.pop_front()
			old_line += 1
			new_line += 1
		else:
			# We have a change
			if current_hunk == null:
				# Start a new hunk with leading context
				var context_start := pending_context.size()
				current_hunk = {
					"old_start": old_line - context_start + 1,
					"new_start": new_line - context_start + 1,
					"old_count": context_start,
					"new_count": context_start,
					"operations": []
				}
				# Add leading context
				for ctx in pending_context:
					current_hunk["operations"].append({"type": "context", "line": ctx["line"]})
				pending_context.clear()
			else:
				# Continue current hunk, clear pending context (it's now part of the hunk)
				pending_context.clear()
			
			# Add the operation
			current_hunk["operations"].append({"type": op["type"], "line": op["line"]})
			
			if op["type"] == "delete":
				current_hunk["old_count"] += 1
				old_line += 1
			elif op["type"] == "add":
				current_hunk["new_count"] += 1
				new_line += 1
	
	# Don't forget the last hunk
	if current_hunk != null:
		hunks.append(current_hunk)
	
	return hunks


static func _find_line(line: String, lines: Array, start: int) -> int:
	for i in range(start, mini(start + LOOKAHEAD_LINES, lines.size())):
		if lines[i] == line:
			return i
	return -1
