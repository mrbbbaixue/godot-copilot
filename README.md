# Godot Copilot

AI-assisted development plugin for the Godot Engine. Chat with AI models and apply code changes directly in the editor.

## Features

- 🤖 **AI Chat Panel**: Chat with AI models directly in the Godot editor
- ⚙️ **Custom API Configuration**: Support for OpenAI and any OpenAI-compatible API (like Ollama, Azure OpenAI, etc.)
- 📖 **Read Current Code**: Automatically read the currently open script and add it to the conversation context
- 🎬 **Read Scene Context**: Automatically find and read the scene file (.tscn) that uses the current script
- ✏️ **Apply Code Changes**: Apply AI-generated code directly to your current script
- 📝 **Diff Mode**: Use unified diff format for code changes to save output time and see exactly what changed

## Installation

1. Download or clone this repository
2. Copy the `addons/godot_copilot` folder to your Godot project's `addons/` directory
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

1. Open a GDScript file in the Godot editor
2. Click **📖 Read Code** to add the current script to the conversation context
3. (Optional) Click **🎬 Read Scene** to add the associated scene file (.tscn) to the context
4. Type your question or request in the chat input
5. Click **Send** to get a response from the AI
6. If the AI provides code:
   - Click **✏ Apply Code** to replace your current script with the AI-generated code
   - Or click **📝 Apply Diff** to apply only the changed lines (when in diff mode)

### Diff Mode

Enable **Diff Mode** checkbox for more efficient code changes:
- AI will respond with unified diff format showing only changed lines
- Saves output time for large files
- Makes changes more visible with context
- Use **📝 Apply Diff** button to apply the changes

## Tips

- When asking for code modifications, the AI will provide code in markdown code blocks
- The "Apply Code" button extracts code from the AI's response and replaces your current script content
- The "Apply Diff" button applies only the changed lines when using diff format
- Use clear and specific prompts for best results
- You can clear the chat history with the **🗑** button
- Reading the scene file provides context about node structure, exported properties, and resources

## License

MIT License - See [LICENSE](LICENSE) for details.
