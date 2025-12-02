@tool
extends RefCounted

## Utility class for parsing and applying unified diff format changes

const LOOKAHEAD_LINES = 5
const FUZZY_SEARCH_WINDOW = 50  # Increased from 10 to 50 for better fuzzy search
const MAX_SEARCH_WINDOW = 200  # Maximum lines to search for hunk matching
const TAB_WIDTH = 4  # Spaces per tab for normalization to tabs
const INDENT_TOLERANCE = true  # Whether to be tolerant of indentation differences
const CONTEXT_LINES_TO_MATCH = 3  # Number of context lines to require for matching


## Clean line endings by removing \r and \n characters
static func _clean_line_endings(line: String) -> String:
	return line.replace("\r", "").replace("\n", "")


## Split text into lines and clean line endings
static func _split_and_clean_lines(text: String) -> Array:
	var lines := text.split("\n", false)  # keep empty lines
	var cleaned_lines := []
	for line in lines:
		cleaned_lines.append(_clean_line_endings(line))
	return cleaned_lines


## Parse a unified diff and return a list of hunks
## Each hunk is a dictionary with: old_start, old_count, new_start, new_count, operations
## operations is an array of dictionaries with: type ("context", "delete", "add"), content
static func parse_diff(diff_text: String) -> Array:
	var hunks := []
	var lines := diff_text.split("\n", false)  # keep empty lines
	var i := 0

	while i < lines.size():
		var line := lines[i]

		# Look for hunk header: @@ -start,count +start,count @@
		if line.begins_with("@@"):
			var hunk := _parse_hunk_header(line)
			if hunk.is_empty():
				i += 1
				continue

			var operations := []
			i += 1

			# Parse hunk content with strict prefix checking
			while i < lines.size():
				var content_line := lines[i]
				# Stop at next hunk header or diff/file markers
				if content_line.begins_with("@@") or content_line.begins_with("diff ") or content_line.begins_with("---") or content_line.begins_with("+++"):
					break

				if content_line.begins_with("-"):
					operations.append({"type": "delete", "content": _clean_line_endings(content_line.substr(1))})
				elif content_line.begins_with("+"):
					operations.append({"type": "add", "content": _clean_line_endings(content_line.substr(1))})
				elif content_line.begins_with(" "):
					operations.append({"type": "context", "content": _clean_line_endings(content_line.substr(1))})
				elif content_line.is_empty():
					# Empty line in diff - treat as empty context line
					operations.append({"type": "context", "content": ""})
				else:
					# Lines without recognized prefix are ignored (strict mode)
					# This prevents the bug where lines starting with spaces were incorrectly
					# treated as context lines with space prefix
					pass

				i += 1

			hunk["operations"] = operations
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
## Returns a dictionary with success flag, error message (if any), and modified code
static func apply_diff(original_code: String, diff_text: String) -> Dictionary:
	# First, try to extract diff from markdown code block if present
	var actual_diff := _extract_diff_from_markdown(diff_text)
	if actual_diff.is_empty():
		actual_diff = diff_text

	# Parse the diff into hunks
	var hunks = parse_diff(actual_diff)
	if hunks.is_empty():
		return {"success": false, "error": "No valid diff hunks found", "code": ""}

	var original_lines := _split_and_clean_lines(original_code)
	var result_lines := original_lines.duplicate()
	var total_offset := 0  # Track cumulative line offset due to insertions/deletions

	for hunk in hunks:
		var operations = hunk.get("operations", [])
		if operations.is_empty():
			continue

		# Calculate suggested position based on hunk header and previous offsets
		var suggested_pos = hunk["old_start"] - 1 + total_offset

		# Find the best matching position for this hunk
		var match_result := _find_best_hunk_match(result_lines, operations, suggested_pos)
		if not match_result["found"]:
			return {
				"success": false,
				"error": "Failed to apply hunk at line %d: %s" % [hunk["old_start"], match_result["error"]],
				"code": ""
			}

		var start_pos = match_result["position"]
		var hunk_offset := _apply_hunk_with_validation(result_lines, operations, start_pos)
		total_offset += hunk_offset

	return {"success": true, "error": "", "code": "\n".join(result_lines)}


## Find the best matching position for a hunk
static func _find_best_hunk_match(lines: Array, operations: Array, suggested_pos: int) -> Dictionary:
	# First, try exact match at suggested position
	var exact_match = _validate_hunk_at_position(lines, operations, suggested_pos)
	if exact_match["valid"]:
		return {"found": true, "position": suggested_pos, "confidence": 1.0}

	# If no exact match, try fuzzy search in expanding windows
	var search_windows = [
		FUZZY_SEARCH_WINDOW,      # Primary search window
		FUZZY_SEARCH_WINDOW * 2,  # Expanded search
		MAX_SEARCH_WINDOW         # Maximum search
	]

	for window_size in search_windows:
		var match_result = _fuzzy_search_hunk(lines, operations, suggested_pos, window_size)
		if match_result["found"]:
			return match_result

	# No match found anywhere
	return {
		"found": false,
		"error": _generate_hunk_error_message(lines, operations, suggested_pos)
	}


## Fuzzy search for hunk within a window
static func _fuzzy_search_hunk(lines: Array, operations: Array, suggested_pos: int, window_size: int) -> Dictionary:
	var start_search := maxi(0, suggested_pos - window_size)
	var end_search := mini(lines.size(), suggested_pos + window_size)

	var best_match := {"found": false, "position": -1, "confidence": 0.0}

	for pos in range(start_search, end_search):
		var validation = _validate_hunk_at_position(lines, operations, pos)
		if validation["valid"] and validation["confidence"] > best_match["confidence"]:
			best_match = {"found": true, "position": pos, "confidence": validation["confidence"]}
			# If we find a perfect match, return immediately
			if validation["confidence"] >= 0.99:
				return best_match

	return best_match


## Validate if a hunk can be applied at a given position
static func _validate_hunk_at_position(lines: Array, operations: Array, start_pos: int) -> Dictionary:
	# Use a simple algorithm that allows skipping blank lines in diff or extra blank lines in code
	var actual_index := start_pos
	var op_index := 0
	var matched_contexts := 0
	var total_contexts := 0
	var issues := []
	var delete_lines_matched := 0
	var total_delete_lines := 0

	while op_index < operations.size():
		var op = operations[op_index]
		var op_type = op["type"]
		var expected_content = op["content"]

		if op_type == "add":
			# Add operations don't consume actual lines
			op_index += 1
			continue

		# For context and delete operations, we need to match with actual lines
		total_contexts += 1
		if op_type == "delete":
			total_delete_lines += 1

		# Check if we've reached the end of actual lines
		if actual_index >= lines.size():
			# If this is a delete line and we're at EOF, that's an error
			# If it's a context line at EOF, maybe the file ends here
			if op_type == "delete":
				issues.append("Line %d: Expected to delete '%s' but reached end of file" % [op_index + 1, expected_content])
				# Can't delete non-existent line
				break
			else:
				# Context line at EOF - might be OK if file is shorter
				issues.append("Line %d: Expected context '%s' but reached end of file" % [op_index + 1, expected_content])
				# Count as matched to avoid penalizing shorter files
				matched_contexts += 1
				op_index += 1
				continue

		var actual_line = lines[actual_index]
		var line_match = _lines_match_with_tolerance(actual_line, expected_content)

		if line_match["match"]:
			# Lines match
			matched_contexts += 1
			if op_type == "delete":
				delete_lines_matched += 1
			actual_index += 1
			op_index += 1
		else:
			# Lines don't match
			if op_type == "delete":
				# Delete lines MUST match exactly - can't delete wrong line
				issues.append("Line %d: Expected to delete '%s' but got '%s'" % [op_index + 1, expected_content, actual_line])
				actual_index += 1
				op_index += 1
			else:
				# Context line mismatch
				# Check if this is a blank line issue
				var expected_is_blank = expected_content.strip_edges().is_empty()
				var actual_is_blank = actual_line.strip_edges().is_empty()

				# Check if this could be a missing/extra blank line issue
				# Try looking ahead to see if we can recover

				# Case 1: Expected blank line, actual has content
				if expected_is_blank and not actual_is_blank:
					# Check if the next operation matches the current actual line
					if op_index + 1 < operations.size():
						var next_op = operations[op_index + 1]
						if next_op["type"] != "add":  # Next op is context or delete
							var next_expected = next_op["content"]
							var next_match = _lines_match_with_tolerance(actual_line, next_expected)
							if next_match["match"]:
								# Next operation matches current line, so this blank line is optional
								matched_contexts += 1  # Count blank line as matched (optional)
								issues.append("Line %d: Optional blank line skipped (next line matches)" % [op_index + 1])
								op_index += 1  # Skip the blank line expectation
								# Don't advance actual_index - current line will match next operation
								continue

					# If we get here, blank line doesn't seem optional
					# Skip it anyway for robustness
					matched_contexts += 1
					issues.append("Line %d: Expected blank line, skipping (code has: '%s')" % [op_index + 1, actual_line])
					op_index += 1
					# Don't advance actual_index

				# Case 2: Expected content, actual is blank line
				elif not expected_is_blank and actual_is_blank:
					# Check if skipping this blank line helps
					if actual_index + 1 < lines.size():
						var next_actual = lines[actual_index + 1]
						var next_match = _lines_match_with_tolerance(next_actual, expected_content)
						if next_match["match"]:
							# Next actual line matches this operation, so extra blank line in code
							issues.append("Line %d: Extra blank line in code, skipping" % [op_index + 1])
							actual_index += 1  # Skip the blank line
							# Don't advance op_index - try same operation with next line
							continue

					# Can't recover by skipping blank line
					issues.append("Line %d: Expected '%s' but got blank line" % [op_index + 1, expected_content])
					actual_index += 1  # Skip the blank line
					op_index += 1  # This operation didn't match

				# Case 3: Both non-blank, but don't match
				else:
					# Try to see if this is just a small difference (like trailing whitespace)
					# or if we can skip ahead to find a match

					# First, check if lines are similar (e.g., differ only by whitespace)
					var norm1 = _normalize_whitespace(actual_line)
					var norm2 = _normalize_whitespace(expected_content)
					if norm1 == norm2:
						# Only whitespace difference - count as match
						matched_contexts += 1
						issues.append("Line %d: Whitespace difference: expected '%s', got '%s'" % [op_index + 1, expected_content, actual_line])
						actual_index += 1
						op_index += 1
						continue

					# Not a simple whitespace difference
					issues.append("Line %d: Expected '%s' but got '%s'" % [op_index + 1, expected_content, actual_line])
					actual_index += 1
					op_index += 1

	# Calculate confidence
	var confidence = 0.0
	if total_contexts > 0:
		confidence = float(matched_contexts) / float(total_contexts)
	else:
		confidence = 1.0  # No context lines to match

	# Determine validity
	# Delete lines must match exactly or we risk deleting wrong code
	# But allow small differences (e.g., whitespace) that we already counted as matches
	var delete_match_ok = total_delete_lines == 0 or delete_lines_matched == total_delete_lines

	# For context lines, be more tolerant, especially for small hunks
	# For 1-3 lines, require at least 50% match
	# For 4+ lines, require at least 60% match
	var min_confidence = 0.6  # Default for larger hunks
	if total_contexts <= 3:
		min_confidence = 0.5  # More tolerant for small hunks
	elif total_contexts <= 5:
		min_confidence = 0.55

	var context_valid = confidence >= min_confidence or total_contexts == 0

	var valid = delete_match_ok and context_valid

	return {
		"valid": valid,
		"confidence": confidence,
		"issues": issues,
		"matched_contexts": matched_contexts,
		"total_contexts": total_contexts,
		"delete_lines_matched": delete_lines_matched,
		"total_delete_lines": total_delete_lines,
		"final_actual_index": actual_index,
		"final_op_index": op_index
	}


## Check if two lines match with tolerance for whitespace differences
static func _lines_match_with_tolerance(line1: String, line2: String) -> Dictionary:
	# First, strip any trailing carriage returns or newlines for comparison
	var clean_line1 = line1.replace("\r", "").replace("\n", "")
	var clean_line2 = line2.replace("\r", "").replace("\n", "")

	# Handle empty lines (after cleaning)
	if clean_line1.strip_edges().is_empty() and clean_line2.strip_edges().is_empty():
		return {"match": true, "differences": []}

	# If INDENT_TOLERANCE is enabled, compare content ignoring leading whitespace
	if INDENT_TOLERANCE:
		var content1 = _strip_leading_whitespace(clean_line1)
		var content2 = _strip_leading_whitespace(clean_line2)
		if content1 == content2:
			return {"match": true, "differences": ["indentation"]}

	# Exact match (including whitespace, after cleaning)
	if clean_line1 == clean_line2:
		return {"match": true, "differences": []}

	# Try match ignoring trailing whitespace
	var rstrip1 = clean_line1.rstrip(" \t")
	var rstrip2 = clean_line2.rstrip(" \t")
	if rstrip1 == rstrip2:
		return {"match": true, "differences": ["trailing_whitespace"]}

	# Try normalized whitespace match (tabs vs spaces, collapse multiple spaces)
	var norm1 = _normalize_whitespace(clean_line1)
	var norm2 = _normalize_whitespace(clean_line2)
	if norm1 == norm2:
		return {"match": true, "differences": ["whitespace"]}

	return {"match": false, "differences": ["content"]}


## Strip leading whitespace from a line
static func _strip_leading_whitespace(line: String) -> String:
	for i in range(line.length()):
		if not (line[i] == ' ' or line[i] == '\t'):
			return line.substr(i)
	return ""


## Normalize whitespace (convert tabs to spaces, collapse multiple spaces, trim trailing whitespace)
static func _normalize_whitespace(line: String) -> String:
	var result := ""
	var in_whitespace := false

	for i in range(line.length()):
		var ch = line[i]
		if ch == ' ' or ch == '\t':
			if not in_whitespace:
				result += ' '
				in_whitespace = true
		else:
			result += ch
			in_whitespace = false

	# Remove trailing space if we added one
	if in_whitespace and result.length() > 0:
		result = result.substr(0, result.length() - 1)

	return result


## Apply hunk operations with validation
static func _apply_hunk_with_validation(lines: Array, operations: Array, start_pos: int) -> int:
	var current_pos := start_pos
	var offset := 0
	var op_index := 0

	while op_index < operations.size():
		var op = operations[op_index]
		var op_type = op["type"]
		var content = op["content"]

		if op_type == "add":
			# Insert new line
			lines.insert(current_pos, content)
			current_pos += 1
			offset += 1
			op_index += 1
		elif op_type == "delete":
			# Delete line - must exist and match
			if current_pos < lines.size():
				var actual_line = lines[current_pos]
				var line_match = _lines_match_with_tolerance(actual_line, content)
				if line_match["match"]:
					lines.remove_at(current_pos)
					offset -= 1
					op_index += 1
					# Don't advance current_pos since we removed the line
				else:
					push_warning("Attempted to delete mismatched line at position %d: expected '%s', got '%s'" % [current_pos, content, actual_line])
					# Still delete? This could be dangerous. For now, skip and continue.
					current_pos += 1
					op_index += 1
			else:
				push_warning("Attempted to delete non-existent line at position %d" % current_pos)
				op_index += 1
		else:  # context
			if current_pos < lines.size():
				var actual_line = lines[current_pos]
				var line_match = _lines_match_with_tolerance(actual_line, content)

				if line_match["match"]:
					# Lines match, advance both
					current_pos += 1
					op_index += 1
				else:
					# Check for blank line handling
					var expected_is_blank = content.strip_edges().is_empty()
					var actual_is_blank = actual_line.strip_edges().is_empty()

					if expected_is_blank and not actual_is_blank:
						# Diff expects blank line but code has content
						# Skip this expectation (don't advance current_pos)
						push_warning("Skipping blank line expectation at position %d (code has: '%s')" % [current_pos, actual_line])
						op_index += 1
					elif not expected_is_blank and actual_is_blank:
						# Code has blank line that diff doesn't expect
						# Skip the actual blank line
						push_warning("Skipping extra blank line in code at position %d" % current_pos)
						current_pos += 1
						# Don't advance op_index - try same operation with next line
					else:
						# Real mismatch
						push_warning("Context line mismatch at position %d: expected '%s', got '%s'" % [current_pos, content, actual_line])
						current_pos += 1
						op_index += 1
			else:
				# Reached end of file but still have context lines in diff
				# This might happen if file is shorter than expected
				push_warning("Reached end of file but diff expects more context lines")
				op_index += 1

	return offset


## Generate helpful error message when hunk cannot be applied
static func _generate_hunk_error_message(lines: Array, operations: Array, suggested_pos: int) -> String:
	# Extract sample context lines from the hunk
	var context_samples := []
	for i in range(mini(operations.size(), 3)):
		var op = operations[i]
		if op["type"] == "context" or op["type"] == "delete":
			context_samples.append(op["content"])

	if context_samples.is_empty():
		return "Hunk has no context lines to match"

	# Show what we're looking for
	var sample_text := ""
	for i in range(context_samples.size()):
		sample_text += "  %d. '%s'\n" % [i + 1, context_samples[i]]

	# Show lines around suggested position for comparison
	var context_start := maxi(0, suggested_pos - 2)
	var context_end := mini(lines.size(), suggested_pos + 3)
	var actual_context := ""
	for i in range(context_start, context_end):
		var prefix = "> " if i == suggested_pos else "  "
		actual_context += "%s%d. '%s'\n" % [prefix, i + 1, lines[i]]

	return """Could not find matching context near line %d.

Looking for:
%s
Actual context around line %d:
%s
Possible reasons:
1. The code has changed since the diff was generated
2. The diff format is incorrect (context lines must start with a space)
3. Indentation differences (try enabling INDENT_TOLERANCE)
""" % [suggested_pos + 1, sample_text, suggested_pos + 1, actual_context]


## Extract diff content from markdown code block
static func _extract_diff_from_markdown(text: String) -> String:
	var regex := RegEx.new()
	# Make trailing newline before closing backticks optional to handle AI responses
	# that don't include a newline before ```
	regex.compile("```(?:diff)?\\s*\\n([\\s\\S]*?)\\n?```")
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
	# Make trailing newline before closing backticks optional to handle AI responses
	# that don't include a newline before ```
	var code_block_regex := RegEx.new()
	code_block_regex.compile("```diff\\s*\\n([\\s\\S]*?)\\n?```")
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
	
	# Make trailing newline before closing backticks optional to handle AI responses
	# that don't include a newline before ```
	var code_block_regex := RegEx.new()
	code_block_regex.compile("```(?:gdscript|gd)?\\s*\\n([\\s\\S]*?)\\n?```")
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
