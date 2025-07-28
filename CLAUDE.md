# Smart Card Unlocker Project

## Overview
This project provides multiple implementations for automatically locking/unlocking Ubuntu 24 based on smart card presence. When the target smart card is inserted, the screen unlocks. When removed, the screen locks immediately.

## Target Smart Card
- **ATR**: `0081314544303832203655` (detected by opensc-tool)
- **Original ATR**: `3BE700FF8131FE454430382E32203655` (from pcsc_scan format)
- **Reader**: Alcor Micro AU9540 Smartcard Reader

## Project Files

### Working Scripts
1. **`simple_unlock.sh`** ✅ **RECOMMENDED** - Most reliable approach
   - Uses fast polling (0.5s intervals) with opensc-tool
   - Simple, no complex event monitoring
   - Proven to work consistently

2. **`smartcard_monitor`** (C++) ✅ **PERFORMANCE** - Compiled version
   - C++ implementation for better performance
   - Same functionality as bash version
   - Object-oriented design with proper error handling

3. **`smartcard_config_monitor`** (C++) ✅ **CONFIGURABLE** - Multi-card support
   - **NEW:** Configuration file based multi-card monitoring
   - Support for different cards with different actions
   - Custom script execution per card (insert/remove events)
   - INI-style config file for easy management
   - Perfect for unlock/lock + password pasting workflows

### Experimental Scripts
4. **`udev_unlock.sh`** ⚠️ - Event-based monitoring (fixed but complex)
   - Uses udev events + inotify + polling
   - Multiple detection methods
   - More complex but theoretically faster response

5. **`pcsc_unlock.sh`** ⚠️ - Uses pcsc_scan for detection
   - Based on pcsc_scan output parsing
   - Sometimes misses events

### Browser Opening Scripts
6. **`smartcard_monitor.sh`** - Opens mmc-bg.com when card detected
7. **`pcsc_monitor.sh`** - Browser opening with pcsc_scan

## Dependencies

### Required System Packages
```bash
# OpenSC tools (required for all versions)
sudo apt install opensc

# For better unlock functionality (recommended)
sudo apt install xdotool

# For enhanced monitoring (optional)
sudo apt install inotify-tools

# For development (C++ version)
sudo apt install build-essential g++ make
```

### System Requirements
- Ubuntu 24.04 LTS
- Smart card reader (USB)
- GNOME desktop environment (for screen lock/unlock)
- OpenSC compatible smart card

## Usage Instructions

### Quick Start (Recommended)
```bash
# Use the simple, reliable version
./simple_unlock.sh

# For debug output
DEBUG=1 ./simple_unlock.sh
```

### C++ Version
```bash
# Compile (first time only)
make

# Run
./smartcard_monitor

# Debug mode
./smartcard_monitor --debug
```

### Configurable Multi-Card Version ✨ **NEW**
```bash
# Compile the configurable version
make smartcard_config_monitor

# Run with default config (smartcard.conf)
./smartcard_config_monitor

# Run with debug output
./smartcard_config_monitor --debug

# Use custom config file
./smartcard_config_monitor --config my_cards.conf

# Help
./smartcard_config_monitor --help
```

#### Configuration File Format (smartcard.conf)
```ini
# Your main unlock/lock card
[3BE700FF8131FE454430382E32203655]
insert=./unlock.sh
remove=./lock.sh

# Revolut card for password pasting
[3BFF13000010003101F1564011001900000000000000]
insert=./paste_pass.sh
remove=

# Postbank card (no actions)
[3BFE1300001080351603528660C3A04A4345533332]
```

### Advanced Usage
```bash
# Try the enhanced udev version
DEBUG=1 ./udev_unlock.sh

# Browser opening version
./smartcard_monitor.sh
```

## Development Progress

### Phase 1: Initial Implementation ✅
- [x] Created basic pcsc_scan monitoring script
- [x] Added browser opening functionality (mmc-bg.com)
- [x] Identified correct ATR format from opensc-tool

### Phase 2: Reliability Improvements ✅
- [x] Implemented simple polling approach (most reliable)
- [x] Added proper screen lock/unlock methods
- [x] Fixed ATR detection issues
- [x] Added debug logging capabilities

### Phase 3: Advanced Monitoring ✅
- [x] Created udev event-based monitoring
- [x] Added inotify filesystem monitoring
- [x] Implemented multi-method detection
- [x] Added automatic process restart

### Phase 4: Performance Optimization ✅
- [x] Created C++ implementation
- [x] Added proper error handling
- [x] Implemented clean shutdown
- [x] Added compilation setup (Makefile)

### Phase 5: Documentation & Deployment ✅
- [x] Created comprehensive documentation
- [x] Documented all dependencies
- [x] Provided usage instructions
- [x] Set up git repository

### Phase 6: Multi-Card Configuration System ✅ **NEW**
- [x] Created configurable C++ version (`smartcard_config_monitor`)
- [x] Implemented INI-style configuration file parser
- [x] Added multi-card support with different actions per card
- [x] Created example scripts (unlock.sh, lock.sh, paste_pass.sh)
- [x] Added card swapping detection and handling
- [x] Documented configuration format and usage

## Technical Details

### Lock/Unlock Methods Used
1. **loginctl** - Primary method for Ubuntu 24
2. **gnome-screensaver-command** - Fallback for older systems
3. **xdotool** - Key simulation for wake/dismiss
4. **xdg-screensaver** - Generic desktop method

### Detection Methods
1. **Simple Polling** - Check every 0.5s with opensc-tool (most reliable)
2. **udev Events** - Kernel-level USB device monitoring
3. **inotify** - Filesystem change monitoring
4. **pcsc_scan** - PC/SC service output parsing
5. **Configurable Multi-Card** - Polling with custom script execution per card

### ATR Processing
- Raw pcsc_scan format: `3B E7 00 FF 81 31 FE 45 44 30 38 2E 32 20 36 55`  
- opensc-tool format: `0081314544303832203655` (spaces and some bytes removed)
- C++ versions use full format: `3BE700FF8131FE454430382E32203655`
- Scripts handle both formats appropriately

### Multi-Card Configuration
- **Configuration file**: INI-style format with [ATR] sections
- **Per-card actions**: Different insert/remove scripts for each card
- **Card swapping**: Automatic detection and script execution
- **Example use cases**: 
  - Main card: unlock/lock system
  - Second card: paste passwords
  - Third card: custom automation scripts
- **Script execution**: Runs in background, checks script exists and is executable

## Troubleshooting

### Common Issues
1. **Script exits immediately** - Check if opensc-tool is installed and working
2. **Card not detected** - Verify ATR with `opensc-tool --atr`
3. **Screen doesn't unlock** - Install xdotool, check DISPLAY variable
4. **Events missed** - Use simple_unlock.sh (most reliable)

### Debug Commands
```bash
# Test card detection
opensc-tool --list-readers
opensc-tool --atr

# Test screen lock methods
loginctl lock-session
gnome-screensaver-command -l

# Monitor USB events
DEBUG=1 ./udev_unlock.sh
```

## Installation for Auto-Start

### Systemd Service (Optional)
```bash
# Copy script to system location
sudo cp simple_unlock.sh /usr/local/bin/smartcard-unlock
sudo chmod +x /usr/local/bin/smartcard-unlock

# Create systemd service
sudo tee /etc/systemd/system/smartcard-unlock.service << EOF
[Unit]
Description=Smart Card Auto Lock/Unlock
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/smartcard-unlock
Restart=always
User=%i
Environment=DISPLAY=:0

[Install]
WantedBy=default.target
EOF

# Enable service
sudo systemctl enable smartcard-unlock.service
```

## Commands for Claude

### Build Commands
```bash
# Compile all versions
make all

# Compile specific version
make smartcard_monitor
make smartcard_config_monitor

# Clean build files  
make clean

# Install to system (optional)
sudo make install
```

### Test Commands
```bash
# Test simple version
./simple_unlock.sh

# Test with debug
DEBUG=1 ./simple_unlock.sh

# Test C++ version
./smartcard_monitor --debug

# Test configurable version
./smartcard_config_monitor --debug
```

### Lint/Check Commands
```bash
# Check shell scripts
shellcheck *.sh

# Check C++ compilation
make clean && make
```

This documentation serves as both user guide and development reference for the smart card unlocker project.