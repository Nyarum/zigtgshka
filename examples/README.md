# zigtgshka Examples

This directory contains comprehensive examples demonstrating all the features of the zigtgshka Telegram Bot API library. Each example focuses on different aspects of the library and shows how to use it in real-world scenarios.

## Prerequisites

1. **Create a Telegram Bot**:
   - Message [@BotFather](https://t.me/BotFather) on Telegram
   - Send `/newbot` and follow the instructions
   - Save the bot token (format: `123456789:ABCdefGhiJklmnoPQRstuv222`)

2. **Build the Examples**:
   ```bash
   # From the project root
   zig build
   ```

3. **Get Your Chat ID** (needed for some examples):
   - Start a conversation with your bot
   - Send any message to your bot
   - Run the `polling_bot` example to see your chat ID

## Examples Overview

### 1. Bot Info (`bot_info.zig`)
**Purpose**: Get basic information about your bot
**Demonstrates**: `getMe()` method, bot properties, error handling

```bash
# Usage
./zig-out/bin/bot_info <bot_token>

# Example
./zig-out/bin/bot_info 123456789:ABCdefGhiJklmnoPQRstuv222
```

**What it shows**:
- Bot ID, name, username
- Bot capabilities (groups, inline queries, etc.)
- Premium features availability
- Basic connectivity testing

### 2. Simple Sender (`simple_sender.zig`)
**Purpose**: Send a message to a specific chat
**Demonstrates**: `sendMessage()` method, message parsing, error handling

```bash
# Usage
./zig-out/bin/simple_sender <bot_token> <chat_id> <message>

# Example
./zig-out/bin/simple_sender 123456789:ABC... 123456789 "Hello, World!"
```

**What it shows**:
- How to send messages programmatically
- Message response parsing
- Chat and user information extraction
- Error handling for invalid chat IDs

### 3. Polling Bot (`polling_bot.zig`)
**Purpose**: Complete bot that receives and processes messages
**Demonstrates**: `getUpdates()`, message handling, interactive commands

```bash
# Usage
./zig-out/bin/polling_bot <bot_token>

# Example
./zig-out/bin/polling_bot 123456789:ABCdefGhiJklmnoPQRstuv222
```

**Features**:
- **Long polling** (30-second timeout)
- **Multiple update types**: messages, edited messages, channel posts
- **Interactive commands**:
  - `/start` - Welcome message
  - `/help` - Help information
  - `/info` - Chat and user details
  - `/echo <text>` - Echo messages
- **Message analysis**: Shows entities, formatting, links
- **Real-time processing**: Displays detailed information about each message

### 4. Webhook Manager (`webhook_manager.zig`)
**Purpose**: Manage webhook settings and test bot connectivity
**Demonstrates**: `deleteWebhook()`, bot status checking, API testing

```bash
# Usage
./zig-out/bin/webhook_manager <bot_token> [command]

# Commands
./zig-out/bin/webhook_manager 123456789:ABC... delete  # Delete webhook (default)
./zig-out/bin/webhook_manager 123456789:ABC... status  # Check bot status
./zig-out/bin/webhook_manager 123456789:ABC... info    # Get webhook info (not implemented)
```

**What it does**:
- **Delete webhooks** to enable polling mode
- **Test bot connectivity** and API access
- **Show comprehensive bot status**
- **Verify all endpoints** are working

### 5. Advanced Bot (`advanced_bot.zig`)
**Purpose**: Full-featured bot with state management and statistics
**Demonstrates**: All library features in a production-ready bot

```bash
# Usage
./zig-out/bin/advanced_bot <bot_token>

# Example
./zig-out/bin/advanced_bot 123456789:ABCdefGhiJklmnoPQRstuv222
```

**Advanced Features**:
- **User state management**: Track conversation flows per user
- **Statistics tracking**: Messages, users, uptime, response rates
- **Interactive modes**: Echo mode with state persistence
- **Message analysis**: Word count, URL detection, mentions, hashtags
- **Comprehensive commands**:
  - `/start` - Welcome with feature overview
  - `/help` - Detailed command reference
  - `/echo` - Interactive echo mode
  - `/info` - User and chat information
  - `/stats` - Detailed bot statistics
  - `/ping` - Responsiveness test
  - `/time` - Current timestamp
  - `/cancel` - Cancel current action
- **Error recovery**: Robust error handling with automatic retries
- **Memory management**: Proper cleanup and leak prevention

### 6. Echo Bot (`echo_bot.zig`)
**Purpose**: Simple echo bot (original example)
**Demonstrates**: Basic message echoing

```bash
# Usage
./zig-out/bin/echo_bot <bot_token>
```

## Building and Running Examples

### Build All Examples
```bash
# From project root
zig build

# Or build specific example
zig build-exe examples/bot_info.zig -lc --dep telegram --mod telegram:src/telegram.zig
```

### Run Examples with Make
```bash
# The default make target runs echo_bot
make run TOKEN=your_bot_token

# For other examples, use the binary directly
./zig-out/bin/polling_bot your_bot_token
```

## Example Progression

**Recommended learning order**:

1. **bot_info.zig** - Start here to test your token and see basic API usage
2. **simple_sender.zig** - Learn how to send messages
3. **webhook_manager.zig** - Understand webhook management
4. **polling_bot.zig** - See complete message handling
5. **advanced_bot.zig** - Explore advanced features
6. **echo_bot.zig** - Reference the original simple implementation

## Common Use Cases by Example

### Testing Bot Setup
- Use `bot_info.zig` to verify your token
- Use `webhook_manager.zig status` to check connectivity

### Learning the API
- Start with `simple_sender.zig` for basic operations
- Progress to `polling_bot.zig` for message handling

### Production Bots
- Use `advanced_bot.zig` as a template
- Implement similar state management and error handling

### Debugging
- `polling_bot.zig` shows detailed message information
- `webhook_manager.zig` helps troubleshoot connectivity issues

## Key Features Demonstrated

### Memory Management
All examples show proper Zig memory management:
- Allocator usage patterns
- `defer` statements for cleanup
- `deinit()` calls for all structures

### Error Handling
- Telegram API error responses
- Network connectivity issues
- Invalid input handling
- Graceful degradation

### JSON Processing
- Response parsing
- Field extraction
- Optional field handling
- Type conversion

### API Methods Coverage
- `getMe()` - Bot information
- `getUpdates()` - Message polling
- `sendMessage()` - Sending messages
- `deleteWebhook()` - Webhook management

### Real-world Patterns
- Long polling implementation
- State management per user
- Statistics tracking
- Interactive command handling
- Message analysis and processing

## Troubleshooting

### Common Issues

1. **Invalid token error**: Check your bot token format
2. **No updates**: Make sure webhook is deleted (use webhook_manager)
3. **Network errors**: Check internet connectivity
4. **Chat ID not found**: Use polling_bot to discover chat IDs

### Debug Tips

- All examples include detailed debug output
- Check console logs for API responses
- Use webhook_manager to test connectivity
- Verify bot permissions in chats/groups

## Next Steps

After running these examples:

1. **Modify** existing examples to add features
2. **Combine** patterns from different examples
3. **Implement** additional Telegram API methods
4. **Create** your own bot using these patterns as templates

Each example is self-contained and well-documented, making it easy to understand and extend for your specific use cases. 