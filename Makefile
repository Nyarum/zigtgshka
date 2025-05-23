# Telegram Bot API Key
# Set this environment variable: export API_KEY=your_bot_token
# Or pass it when running: make run-advanced API_KEY=your_bot_token
API_KEY ?= test_api_key

pull/external:
	mkdir libraries && cd libraries && git clone git@github.com:go-telegram-bot-api/telegram-bot-api.git
	mkdir docs && cd docs && git clone git@github.com:jedisct1/zig-for-mcp.git

# Build targets
.PHONY: build clean test docs help

build:
	zig build

build-debug:
	zig build -Doptimize=Debug

clean:
	rm -rf zig-out .zig-cache

test:
	zig build test

docs:
	zig build docs

# Debug targets - compile with debug symbols for debugging
.PHONY: debug-advanced debug-run debug-info debug-setup

debug-setup:
	@echo "🛠️  Setting up debugging environment..."
	@echo "📋 Make sure you have lldb installed (should be available on macOS)"
	@echo "🔧 Building with debug symbols..."

debug-advanced: debug-setup
	@if [ -z "$(API_KEY)" ]; then echo "❌ Error: API_KEY not set. Use: make debug-advanced API_KEY=your_bot_token"; exit 1; fi
	@echo "🐛 Building advanced bot with debug symbols..."
	zig build run-advanced_bot -Doptimize=Debug -- $(API_KEY)

debug-run: debug-setup
	@if [ -z "$(API_KEY)" ]; then echo "❌ Error: API_KEY not set. Use: make debug-run API_KEY=your_bot_token"; exit 1; fi
	@echo "🐛 To debug with lldb, run these commands:"
	@echo ""
	@echo "1️⃣  First, build the debug executable:"
	@echo "    zig build -Doptimize=Debug"
	@echo ""
	@echo "2️⃣  Then start lldb with the executable:"
	@echo "    lldb ./zig-out/bin/advanced_bot"
	@echo ""
	@echo "3️⃣  In lldb, set breakpoints and run:"
	@echo "    (lldb) breakpoint set --name main"
	@echo "    (lldb) breakpoint set --file src/utils.zig --line 132"
	@echo "    (lldb) breakpoint set --name parseMessage"
	@echo "    (lldb) run $(API_KEY)"
	@echo ""
	@echo "4️⃣  When it stops at a breakpoint, you can:"
	@echo "    (lldb) bt              # Show backtrace"
	@echo "    (lldb) frame variable  # Show local variables"
	@echo "    (lldb) continue        # Continue execution"
	@echo "    (lldb) step            # Step into next line"
	@echo "    (lldb) next            # Step over next line"
	@echo ""
	@echo "5️⃣  To quit lldb:"
	@echo "    (lldb) quit"

debug-info:
	@echo "🔍 Debug Information:"
	@echo ""
	@echo "📍 Key places to set breakpoints:"
	@echo "   • src/utils.zig:132 (parseMessage pinned_message assignment)"
	@echo "   • Message.deinit() method"
	@echo "   • parseMessageWithDepth function"
	@echo ""
	@echo "🎯 Useful lldb commands:"
	@echo "   • p variable_name      - Print variable value"
	@echo "   • po object            - Print object description"
	@echo "   • memory read address  - Read memory at address"
	@echo "   • thread list          - Show all threads"
	@echo ""
	@echo "🚨 What to look for in the segfault:"
	@echo "   • Double-free errors"
	@echo "   • Null pointer dereferences" 
	@echo "   • Stack overflow from recursion"
	@echo "   • Use-after-free errors"

# Bot examples - all require API_KEY to be set
.PHONY: run-echo run-info run-sender run-polling run-advanced run-webhook run-webhook-cmd run-example

# Simple echo bot
run-echo:
	@if [ -z "$(API_KEY)" ]; then echo "❌ Error: API_KEY not set. Use: make run-echo API_KEY=your_bot_token"; exit 1; fi
	zig build run-echo_bot -- $(API_KEY)

# Get bot information
run-info:
	@if [ -z "$(API_KEY)" ]; then echo "❌ Error: API_KEY not set. Use: make run-info API_KEY=your_bot_token"; exit 1; fi
	zig build run-bot_info -- $(API_KEY)

# Send a simple message
run-sender:
	@if [ -z "$(API_KEY)" ]; then echo "❌ Error: API_KEY not set. Use: make run-sender API_KEY=your_bot_token"; exit 1; fi
	@echo "📤 Simple Sender requires chat_id and message parameters."
	@echo "Usage: zig build run-simple_sender -- $(API_KEY) <chat_id> <message>"
	@echo "Example: zig build run-simple_sender -- $(API_KEY) 123456789 \"Hello World\""
	@echo ""
	@echo "To get chat_id:"
	@echo "1. Start a conversation with your bot"
	@echo "2. Send a message to the bot"  
	@echo "3. Use 'make run-polling' to see the chat_id"

# Polling bot with commands
run-polling:
	@if [ -z "$(API_KEY)" ]; then echo "❌ Error: API_KEY not set. Use: make run-polling API_KEY=your_bot_token"; exit 1; fi
	zig build run-polling_bot -- $(API_KEY)

# Advanced bot with state management (recommended)
run-advanced:
	@if [ -z "$(API_KEY)" ]; then echo "❌ Error: API_KEY not set. Use: make run-advanced API_KEY=your_bot_token"; exit 1; fi
	zig build run-advanced_bot -- $(API_KEY)

# Webhook manager
run-webhook:
	@if [ -z "$(API_KEY)" ]; then echo "❌ Error: API_KEY not set. Use: make run-webhook API_KEY=your_bot_token"; exit 1; fi
	zig build run-webhook_manager -- $(API_KEY) delete

# Webhook manager with custom command
run-webhook-cmd:
	@if [ -z "$(API_KEY)" ]; then echo "❌ Error: API_KEY not set. Use: make run-webhook-cmd API_KEY=your_bot_token CMD=info"; exit 1; fi
	@if [ -z "$(CMD)" ]; then echo "❌ Error: CMD not set. Use: make run-webhook-cmd API_KEY=your_bot_token CMD=info"; exit 1; fi
	zig build run-webhook_manager -- $(API_KEY) $(CMD)

# Alias for echo bot (backward compatibility)
run-example: run-echo

# Default target (backward compatibility)
run: run-echo

# Help target
help:
	@echo "🤖 Telegram Bot Makefile Commands:"
	@echo ""
	@echo "📋 Setup:"
	@echo "  export API_KEY=your_bot_token    Set your bot token globally"
	@echo "  make run-advanced API_KEY=token  Pass token for single command"
	@echo ""
	@echo "🔧 Build Commands:"
	@echo "  make build                       Build the project"
	@echo "  make build-debug                 Build with debug symbols"
	@echo "  make clean                       Clean build artifacts"
	@echo "  make test                        Run tests"
	@echo "  make docs                        Generate documentation"
	@echo ""
	@echo "🐛 Debug Commands:"
	@echo "  make debug-run                   Show debugging instructions"
	@echo "  make debug-advanced              Run advanced bot with debug symbols"
	@echo "  make debug-info                  Show debugging tips and breakpoint suggestions"
	@echo ""
	@echo "🤖 Bot Examples:"
	@echo "  make run-echo                    Simple echo bot"
	@echo "  make run-info                    Get bot information"
	@echo "  make run-sender                  Show how to send messages (requires chat_id)"
	@echo "  make run-polling                 Polling bot with commands"
	@echo "  make run-advanced                Advanced bot with state management ⭐"
	@echo "  make run-webhook                 Delete webhook (default command)"
	@echo "  make run-webhook-cmd CMD=info    Webhook manager with custom command"
	@echo ""
	@echo "🔗 Aliases:"
	@echo "  make run                         Same as run-echo"
	@echo "  make run-example                 Same as run-echo"
	@echo ""
	@echo "💡 Tips:"
	@echo "  • Get your bot token from @BotFather on Telegram"
	@echo "  • run-advanced is recommended for full feature demo"
	@echo "  • Use run-polling first to get your chat_id for run-sender"
	@echo "  • Set API_KEY environment variable to avoid typing it each time"
	@echo "  • Use debug-* commands to investigate segmentation faults"
	@echo ""
	@echo "📤 For sending messages manually:"
	@echo "  zig build run-simple_sender -- \$$API_KEY <chat_id> \"<message>\""