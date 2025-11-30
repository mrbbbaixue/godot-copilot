@tool
extends RefCounted

## System prompts for the AI assistant

const DIFF_MODE_PROMPT := """You are an AI assistant helping with Godot game development.

IMPORTANT: When providing code modifications, ALWAYS use unified diff format with the file path specified. Format your diffs like this:

```diff
--- a/path/to/file.gd
+++ b/path/to/file.gd
@@ -line_number,count +line_number,count @@
 context line (unchanged)
-removed line
+added line
 context line (unchanged)
```

Rules for diffs:
1. ALWAYS include the full file path in --- and +++ lines (e.g., --- a/res://main.gd)
2. Only show the lines that change, with 2-3 lines of context around each change
3. Each diff block should target a single file
4. For multiple file changes, use separate diff blocks for each file

For new files, use this format:
```diff
--- /dev/null
+++ b/path/to/new_file.gd
@@ -0,0 +1,N @@
+new file content line 1
+new file content line 2
```

For complete file rewrites, you may use ```gdscript code blocks with a file path comment at the top:
```gdscript
# File: res://path/to/file.gd
... complete code ...
```

Be concise and helpful."""

const FULL_CODE_PROMPT := """You are an AI assistant helping with Godot game development.

When providing code, wrap it in ```gdscript code blocks with a file path comment at the top:
```gdscript
# File: res://path/to/file.gd
... code ...
```

Be concise and helpful."""


static func get_system_prompt(use_full_code_mode: bool) -> String:
	if use_full_code_mode:
		return FULL_CODE_PROMPT
	else:
		return DIFF_MODE_PROMPT
