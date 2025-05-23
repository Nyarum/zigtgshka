# Testing Inline Keyboard Functionality

This document describes how to test the new inline keyboard features in the `advanced_bot.zig` example.

## Prerequisites

1. Have a Telegram bot token (get one from @BotFather)
2. Build the project: `zig build`
3. Start the bot: `./zig-out/bin/advanced_bot <your_bot_token>`

## Test Scenarios

### 1. Basic Keyboard Demo
**Command**: `/keyboard`

**Expected behavior**:
- Bot sends a message with a 3-row inline keyboard
- Row 1: "📋 Simple Demo" and "🎛️ Complex Demo" buttons
- Row 2: "🔗 URL Demo" button
- Row 3: "⚙️ Settings" button

**What to test**:
- Click each button to verify callback handling
- Verify proper navigation between different keyboard types

### 2. Simple Keyboard
**Trigger**: Click "📋 Simple Demo" from main keyboard

**Expected behavior**:
- Shows a Yes/No keyboard with "✅ Yes", "❌ No", and "🔙 Back" buttons
- Clicking Yes/No shows selection confirmation
- Back button returns to main keyboard

### 3. Complex Keyboard
**Trigger**: Click "🎛️ Complex Demo" from main keyboard

**Expected behavior**:
- Shows a 3x2 grid of numbered buttons (1️⃣ through 6️⃣)
- Has a "🔙 Back to Main" button
- Clicking any number shows which option was selected

### 4. URL Keyboard
**Trigger**: Click "🔗 URL Demo" from main keyboard

**Expected behavior**:
- Shows buttons that open external URLs (GitHub, Zig Language)
- Mixed with callback buttons for demo and back navigation
- URL buttons should open links in browser/Telegram

### 5. Settings Menu
**Trigger**: Click "⚙️ Settings" from main keyboard

**Expected behavior**:
- Shows a 2x2 grid of setting categories
- "🔔 Notifications", "🌍 Language", "🎨 Theme", "🔒 Privacy"
- Has "🔙 Back to Main" button
- Demonstrates hierarchical navigation

### 6. Confirmation Dialog
**Command**: `/confirm`

**Expected behavior**:
- Shows a confirmation message with "✅ Confirm" and "❌ Cancel" buttons
- Clicking Confirm shows success message
- Clicking Cancel shows cancellation message
- Demonstrates action confirmation pattern

### 7. Interactive Counter
**Command**: `/counter`

**Expected behavior**:
- Shows current count (starts at 0) with ➖, current value, ➕ buttons
- Has 🔄 Reset button below
- Clicking ➕/➖ updates the counter dynamically
- Current value button shows info message
- Reset button sets counter back to 0

## Callback Query Testing

### Debug Output
When testing, monitor the console for debug output showing:
- `🔘 Callback query from [user] with data: "[callback_data]"`
- `✅ Sent [keyboard_type] keyboard to chat [chat_id]`

### Memory Management
- All keyboards are properly allocated and deallocated
- No memory leaks should occur during testing
- Each button press is handled and responded to

### Error Handling
- Invalid callback data is handled gracefully
- Network errors are logged but don't crash the bot
- Callback queries are always answered to remove loading state

## Statistics Verification

After testing keyboards, check statistics with `/stats`:
- Should show increased callback query count
- Callback ratio percentage should be displayed
- User interaction metrics should be accurate

## Integration Testing

Test the keyboard functionality alongside other bot features:
1. Use `/echo` mode and then keyboards - state should be managed correctly
2. Mix keyboard interactions with regular messages
3. Test `/cancel` command during keyboard interactions
4. Verify all commands still work properly with keyboard state

## Expected Console Output

```
🚀 Advanced Telegram Bot Starting...
✅ Bot @your_bot is online!
📊 Features enabled:
   • Message handling with state management
   • Interactive commands
   • Inline keyboard support
   • Callback query handling
   • User statistics tracking
   • Conversation flow control
   • Error handling and recovery

🔄 Entering main loop (send /help to see available commands)...
💬 Message from User [ID: 123456] in chat 123456
   Text: "/keyboard"
✅ Sent main keyboard to chat 123456
🔘 Callback query from User [ID: 123456] with data: "demo_simple"
✅ Sent simple keyboard to chat 123456
```

## Success Criteria

The inline keyboard functionality is working correctly if:
1. All keyboard layouts render properly
2. Button presses trigger appropriate callback handlers
3. Navigation between keyboards works smoothly
4. URL buttons open correct links
5. Dynamic content (counter) updates correctly
6. Memory is managed properly (no leaks)
7. Statistics track callback queries accurately
8. Error handling prevents crashes
9. State management works with keyboard interactions
10. All debug output appears as expected 