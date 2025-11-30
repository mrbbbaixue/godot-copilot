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


## Extract file path from diff block header
static func extract_file_path_from_diff(diff_text: String) -> String:
	var lines := diff_text.split("\n")
	
	for line in lines:
		# Match +++ b/path/to/file.gd or +++ path/to/file.gd
		if line.begins_with("+++"):
			var path_part := line.substr(4).strip_edges()
			# Remove 'b/' prefix if present
			if path_part.begins_with("b/"):
				path_part = path_part.substr(2)
			# Remove 'a/' prefix if present (shouldn't be, but just in case)
			if path_part.begins_with("a/"):
				path_part = path_part.substr(2)
			# Return the path if it's a valid resource path
			if not path_part.is_empty() and path_part != "modified" and path_part != "/dev/null":
				return path_part
	
	return ""


## Extract all diff blocks from a response with their file paths
## Returns an array of dictionaries: [{path: String, diff: String, is_new_file: bool}, ...]
static func extract_all_diffs(text: String) -> Array:
	var diffs := []
	
	# First try to extract from markdown code blocks
	var code_block_regex := RegEx.new()
	code_block_regex.compile("```diff\\s*\\n([\\s\\S]*?)\\n```")
	var matches := code_block_regex.search_all(text)
	
	if matches.size() > 0:
		for m in matches:
			var diff_content := m.get_string(1)
			var file_path := extract_file_path_from_diff(diff_content)
			var is_new_file := diff_content.contains("--- /dev/null") or diff_content.contains("--- a/dev/null")
			
			if not file_path.is_empty():
				diffs.append({
					"path": file_path,
					"diff": diff_content,
					"is_new_file": is_new_file,
					"full_match": m.get_string(0)
				})
	
	return diffs


## Extract code blocks with file path comments
## Returns an array of dictionaries: [{path: String, code: String}, ...]
static func extract_code_blocks_with_paths(text: String) -> Array:
	var blocks := []
	
	var code_block_regex := RegEx.new()
	code_block_regex.compile("```(?:gdscript|gd)?\\s*\\n([\\s\\S]*?)\\n```")
	var matches := code_block_regex.search_all(text)
	
	for m in matches:
		var code := m.get_string(1)
		var file_path := ""
		
		# Check for file path comment at the start
		var lines := code.split("\n")
		if lines.size() > 0:
			var first_line := lines[0].strip_edges()
			var path_regex := RegEx.new()
			path_regex.compile("^#\\s*[Ff]ile:\\s*(.+)$")
			var path_match := path_regex.search(first_line)
			if path_match:
				file_path = path_match.get_string(1).strip_edges()
				# Remove the file path comment from code
				lines.remove_at(0)
				code = "\n".join(lines)
		
		if not file_path.is_empty():
			blocks.append({
				"path": file_path,
				"code": code,
				"full_match": m.get_string(0)
			})
	
	return blocks
