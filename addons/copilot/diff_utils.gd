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
	var offset := 0  # Track line offset due to insertions/deletions
	
	var i := 0
	while i < lines.size():
		var line := lines[i]
		
		# Look for hunk header
		if line.begins_with("@@"):
			var hunk := _parse_hunk_header(line)
			if hunk.is_empty():
				i += 1
				continue
			
			var old_start: int = hunk["old_start"] - 1 + offset  # Convert to 0-indexed
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
					# Context line (or empty context line) with changes accumulated - apply them
					if delete_lines.size() > 0 or insert_lines.size() > 0:
						var apply_result := _apply_single_change(result_lines, old_start, delete_lines, insert_lines)
						if not apply_result["success"]:
							return {"success": false, "error": apply_result["error"], "code": ""}
						offset += insert_lines.size() - delete_lines.size()
						old_start += delete_lines.size() + 1  # Move past deleted lines and context
						delete_lines = []
						insert_lines = []
					else:
						old_start += 1
				
				i += 1
			
			# Apply any remaining changes
			if delete_lines.size() > 0 or insert_lines.size() > 0:
				var apply_result := _apply_single_change(result_lines, old_start, delete_lines, insert_lines)
				if not apply_result["success"]:
					return {"success": false, "error": apply_result["error"], "code": ""}
				offset += insert_lines.size() - delete_lines.size()
		else:
			i += 1
	
	return {"success": true, "error": "", "code": "\n".join(result_lines)}


## Apply a single change (delete some lines, insert others)
static func _apply_single_change(result_lines: Array, start_idx: int, delete_lines: Array, insert_lines: Array) -> Dictionary:
	# Validate the lines to delete match
	for j in range(delete_lines.size()):
		var idx := start_idx + j
		if idx >= result_lines.size():
			return {"success": false, "error": "Line %d does not exist in original code" % (idx + 1)}
		# Allow fuzzy matching (ignore leading/trailing whitespace differences)
		if result_lines[idx].strip_edges() != delete_lines[j].strip_edges():
			return {"success": false, "error": "Line %d mismatch: expected '%s', got '%s'" % [idx + 1, delete_lines[j].strip_edges(), result_lines[idx].strip_edges()]}
	
	# Remove the lines
	for j in range(delete_lines.size()):
		result_lines.remove_at(start_idx)
	
	# Insert new lines
	for j in range(insert_lines.size()):
		result_lines.insert(start_idx + j, insert_lines[j])
	
	return {"success": true, "error": ""}


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


## Generate a simple diff between two texts
static func generate_diff(old_text: String, new_text: String) -> String:
	var old_lines := old_text.split("\n")
	var new_lines := new_text.split("\n")
	
	var diff := "--- original\n+++ modified\n"
	
	# Simple line-by-line diff (not optimal but sufficient for display)
	var i := 0
	var j := 0
	var hunks := []
	var current_hunk := {"old_start": 1, "old_lines": [], "new_lines": [], "context_before": [], "context_after": []}
	
	while i < old_lines.size() or j < new_lines.size():
		if i < old_lines.size() and j < new_lines.size() and old_lines[i] == new_lines[j]:
			# Lines match - context
			if current_hunk["old_lines"].size() > 0 or current_hunk["new_lines"].size() > 0:
				current_hunk["context_after"].append(old_lines[i])
				if current_hunk["context_after"].size() >= 3:
					hunks.append(current_hunk)
					current_hunk = {"old_start": i + 2, "old_lines": [], "new_lines": [], "context_before": [], "context_after": []}
			else:
				current_hunk["context_before"].append(old_lines[i])
				if current_hunk["context_before"].size() > 3:
					current_hunk["context_before"].pop_front()
				current_hunk["old_start"] = i + 1 - current_hunk["context_before"].size() + 1
			i += 1
			j += 1
		elif i < old_lines.size() and (j >= new_lines.size() or _find_line(old_lines[i], new_lines, j) == -1):
			# Line removed
			current_hunk["old_lines"].append(old_lines[i])
			current_hunk["context_after"].clear()
			i += 1
		elif j < new_lines.size():
			# Line added
			current_hunk["new_lines"].append(new_lines[j])
			current_hunk["context_after"].clear()
			j += 1
	
	# Add final hunk
	if current_hunk["old_lines"].size() > 0 or current_hunk["new_lines"].size() > 0:
		hunks.append(current_hunk)
	
	# Format hunks
	for hunk in hunks:
		var old_count = hunk["context_before"].size() + hunk["old_lines"].size() + hunk["context_after"].size()
		var new_count = hunk["context_before"].size() + hunk["new_lines"].size() + hunk["context_after"].size()
		diff += "@@ -%d,%d +%d,%d @@\n" % [hunk["old_start"], old_count, hunk["old_start"], new_count]
		
		for line in hunk["context_before"]:
			diff += " " + line + "\n"
		for line in hunk["old_lines"]:
			diff += "-" + line + "\n"
		for line in hunk["new_lines"]:
			diff += "+" + line + "\n"
		for line in hunk["context_after"]:
			diff += " " + line + "\n"
	
	return diff


static func _find_line(line: String, lines: Array, start: int) -> int:
	for i in range(start, mini(start + LOOKAHEAD_LINES, lines.size())):
		if lines[i] == line:
			return i
	return -1
