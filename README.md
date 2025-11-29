# Godot Copilot

AI-assisted development plugin for the Godot Engine. Chat with AI models and apply code changes directly in the editor.

## Features

- 🤖 **AI Chat Panel**: Chat with AI models directly in the Godot editor
- ⚙️ **Custom API Configuration**: Support for OpenAI and any OpenAI-compatible API (like Ollama, Azure OpenAI, etc.)
- 📖 **Read Current Code**: Automatically read the currently open script and add it to the conversation context
- ✏️ **Apply Code Changes**: Apply AI-generated code directly to your current script

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
2. Click **📖 Read Current Code** to add the current script to the conversation context
3. Type your question or request in the chat input
4. Click **Send** to get a response from the AI
5. If the AI provides code, click **✏ Apply Code** to apply it to your current script

## Tips

- When asking for code modifications, the AI will provide code in markdown code blocks
- The "Apply Code" button extracts code from the AI's response and replaces your current script content
- Use clear and specific prompts for best results
- You can clear the chat history with the **🗑** button

## License

MIT License - See [LICENSE](LICENSE) for details.
