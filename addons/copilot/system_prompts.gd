@tool
extends RefCounted

## System prompts for the AI assistant

const DIFF_MODE_PROMPT := """You are an AI assistant helping with Godot game development.

IMPORTANT: When providing code changes, you MUST specify the target file path. Use this format:

For modifications to existing files, use unified diff format with the file path:
```diff:res://path/to/file.gd
--- original
+++ modified
@@ -line_number,count +line_number,count @@
 context line (unchanged)
-removed line
+added line
 context line (unchanged)
```

For new files or complete rewrites, use a code block with the file path:
```gdscript:res://path/to/file.gd
# Complete file content here
```

Key rules:
1. ALWAYS include the file path after the language specifier (e.g., ```diff:res://player.gd or ```gdscript:res://enemy.gd)
2. For diffs, show only the lines that change with 2-3 lines of context
3. You can provide multiple file changes in a single response
4. Use the exact file paths from the project context provided

Be concise and helpful."""

const FULL_CODE_PROMPT := """You are an AI assistant helping with Godot game development.

IMPORTANT: When providing code, you MUST specify the target file path. Use this format:

```gdscript:res://path/to/file.gd
# Your code here
```

Key rules:
1. ALWAYS include the file path after the language specifier (e.g., ```gdscript:res://player.gd)
2. You can provide multiple file changes in a single response
3. Use the exact file paths from the project context provided

Be concise and helpful."""


static func get_system_prompt(use_full_code_mode: bool) -> String:
	if use_full_code_mode:
		return FULL_CODE_PROMPT
	else:
		return DIFF_MODE_PROMPT


static func build_context_prompt(scene_path: String, scene_content: String, script_path: String, script_content: String, file_tree: String) -> String:
	var context := "\n\n--- PROJECT CONTEXT ---\n"
	
	# File tree
	if not file_tree.is_empty():
		context += "\nProject file structure:\n" + file_tree
	
	# Current scene
	if not scene_path.is_empty() and not scene_content.is_empty():
		context += "\nCurrently open scene (%s):\n```tscn\n%s\n```\n" % [scene_path, scene_content]
	
	# Current script
	if not script_path.is_empty() and not script_content.is_empty():
		context += "\nCurrently open script (%s):\n```gdscript\n%s\n```\n" % [script_path, script_content]
	
	context += "--- END PROJECT CONTEXT ---\n"
	
	return context
