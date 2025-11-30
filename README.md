# Godot Copilot

AI-assisted development plugin for the Godot Engine. Chat with AI models and apply code changes directly in the editor.

## Features

- 🤖 **AI Chat Panel**: Chat with AI models directly in the Godot editor
- ⚙️ **Custom API Configuration**: Support for OpenAI and any OpenAI-compatible API (like Ollama, Azure OpenAI, etc.)
- 📖 **Auto-Context**: Automatically reads the currently open script, scene, and project file structure
- 🎬 **Scene Awareness**: Understands your scene hierarchy and node structure
- ✏️ **Per-Block Apply**: Each code/diff block has its own Apply button for targeted changes
- 📝 **Diff Mode**: Use unified diff format for code changes to save output time and see exactly what changed
- 📁 **Multi-File Support**: Apply changes to any file in your project

## Installation

1. Download or clone this repository
2. Copy the `addons/copilot` folder to your Godot project's `addons/` directory
3. Open your project in Godot
4. Go to **Project** → **Project Settings** → **Plugins**
5. Enable **Godot Copilot**

## Configuration

1. Click the **⚙** (Settings) button in the Copilot panel
2. Configure your API settings:
   - **API Base URL**: The base URL for your API (default: `https://api.openai.com/v1`)
   - **API Key**: Your API key
   - **Model Name**: The model to use (e.g., `gpt-4o`, `gpt-3.5-turbo`)

### Using with Different Providers

#### OpenAI
- Base URL: `https://api.openai.com/v1`
- API Key: Your OpenAI API key
- Model: `gpt-4o`, `gpt-3.5-turbo`, etc.

#### Azure OpenAI
- Base URL: `https://YOUR-RESOURCE.openai.azure.com/openai/deployments/YOUR-DEPLOYMENT`
- API Key: Your Azure OpenAI API key
- Model: Your deployment name

#### Local Models (Ollama)
- Base URL: `http://localhost:11434/v1`
- API Key: `ollama` (or any string)
- Model: `codellama`, `deepseek-coder`, etc.

## Usage

1. Open a GDScript file and/or a scene in the Godot editor
2. Type your question or request in the chat input
3. Click **Send** to get a response from the AI
4. The AI automatically has context of:
   - Your currently open scene (.tscn file)
   - Your currently open script (.gd file)
   - Your project file structure
5. When the AI provides code changes:
   - Each code block shows the target file path (e.g., `res://player.gd`)
   - Click the **✏️ Apply Code** or **📝 Apply Diff** button below each code block to apply changes to that specific file

### Automatic Context

The plugin automatically reads and sends the following context to the AI with every message:
- **Current Scene**: The currently open scene file content
- **Current Script**: The currently open script content
- **File Tree**: Your project's file structure (scripts, scenes, resources)

This allows the AI to understand your project structure and provide file-specific code changes.

### Code Blocks with File Paths

The AI will provide code changes with file paths like this:

```gdscript:res://player.gd
extends CharacterBody2D
# Your code here
```

Or for diffs:

```diff:res://player.gd
@@ -1,3 +1,4 @@
 extends CharacterBody2D
+@export var speed := 200.0
 # ...
```

Each block has an **Apply** button that writes changes directly to the specified file.

## Tips

- The AI automatically knows about your open scene and script - just ask questions!
- Use clear and specific prompts for best results
- You can clear the chat history with the **🗑** button
- Enable "Traditional Full Text Mode" in settings if you prefer complete code blocks instead of diffs

## License

MIT License - See [LICENSE](LICENSE) for details.
