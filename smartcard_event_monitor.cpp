#include <iostream>
#include <string>
#include <chrono>
#include <thread>
#include <cstdlib>
#include <memory>
#include <stdexcept>
#include <array>
#include <iomanip>
#include <fstream>
#include <sstream>
#include <map>
#include <vector>
#include <signal.h>
#include <unistd.h>
#include <cstring>

// PC/SC includes
#include <wintypes.h>
#include <pcsclite.h>
#include <winscard.h>

struct CardConfig {
    std::string atr;
    std::string insert_script;
    std::string remove_script;
};

class EventBasedSmartCardMonitor {
private:
    const std::string DEFAULT_CONFIG_FILE = "smartcard.conf";
    bool debug_mode = false;
    std::map<std::string, std::string> current_cards; // reader -> ATR
    std::map<std::string, CardConfig> card_configs;
    volatile bool running = true;
    
    SCARDCONTEXT hContext = 0;
    
    std::string bytes_to_hex(const BYTE* bytes, DWORD length) {
        std::stringstream ss;
        for (DWORD i = 0; i < length; i++) {
            ss << std::hex << std::uppercase << std::setfill('0') << std::setw(2) << (int)bytes[i];
        }
        return ss.str();
    }
    
    std::string exec_command(const char* cmd) {
        std::array<char, 128> buffer;
        std::string result;
        std::unique_ptr<FILE, decltype(&pclose)> pipe(popen(cmd, "r"), pclose);
        
        if (!pipe) {
            return "";
        }
        
        while (fgets(buffer.data(), buffer.size(), pipe.get()) != nullptr) {
            result += buffer.data();
        }
        
        return result;
    }
    
    CardConfig* find_card_config(const std::string& atr) {
        auto it = card_configs.find(atr);
        if (it != card_configs.end()) {
            return &it->second;
        }
        return nullptr;
    }
    
    void debug_log(const std::string& message) {
        if (debug_mode) {
            auto now = std::chrono::system_clock::now();
            auto time_t = std::chrono::system_clock::to_time_t(now);
            auto tm = *std::localtime(&time_t);
            
            std::cout << "[" << std::put_time(&tm, "%H:%M:%S") << "] " << message << std::endl;
        }
    }
    
    void log_with_timestamp(const std::string& message) {
        auto now = std::chrono::system_clock::now();
        auto time_t = std::chrono::system_clock::to_time_t(now);
        auto tm = *std::localtime(&time_t);
        
        std::cout << std::put_time(&tm, "%H:%M:%S") << " - " << message << std::endl;
    }
    
    void execute_script(const std::string& script_path, const std::string& action, const std::string& atr) {
        if (script_path.empty()) {
            debug_log("No script configured for " + action + " action");
            return;
        }

        log_with_timestamp("🎯 " + action + " event for card " + atr.substr(0, 8) + "... → " + script_path);
        
        if (access(script_path.c_str(), X_OK) != 0) {
            log_with_timestamp("❌ Script not executable: " + script_path);
            return;
        }

        std::string command = script_path + " 2>/dev/null &";
        int result = system(command.c_str());
        
        debug_log(action + " script executed: " + script_path + " (result: " + std::to_string(result) + ")");
    }
    
    bool load_config(const std::string& config_file) {
        std::ifstream file(config_file);
        if (!file.is_open()) {
            std::cerr << "Error: Cannot open config file: " << config_file << std::endl;
            return false;
        }

        std::string line;
        std::string current_atr;
        CardConfig current_config;

        while (std::getline(file, line)) {
            line.erase(0, line.find_first_not_of(" \t"));
            line.erase(line.find_last_not_of(" \t") + 1);

            if (line.empty() || line[0] == '#' || line[0] == ';') {
                continue;
            }

            if (line[0] == '[' && line.back() == ']') {
                if (!current_atr.empty()) {
                    current_config.atr = current_atr;
                    card_configs[current_atr] = current_config;
                }

                current_atr = line.substr(1, line.length() - 2);
                current_config = CardConfig();
                debug_log("Found ATR config: " + current_atr);
                continue;
            }

            size_t equals_pos = line.find('=');
            if (equals_pos != std::string::npos && !current_atr.empty()) {
                std::string key = line.substr(0, equals_pos);
                std::string value = line.substr(equals_pos + 1);

                key.erase(0, key.find_first_not_of(" \t"));
                key.erase(key.find_last_not_of(" \t") + 1);
                value.erase(0, value.find_first_not_of(" \t"));
                value.erase(value.find_last_not_of(" \t") + 1);

                if (key == "insert") {
                    current_config.insert_script = value;
                } else if (key == "remove") {
                    current_config.remove_script = value;
                }
            }
        }

        if (!current_atr.empty()) {
            current_config.atr = current_atr;
            card_configs[current_atr] = current_config;
        }

        file.close();
        return !card_configs.empty();
    }
    
    void handle_card_event(const std::string& reader, const std::string& new_atr, bool card_present) {
        std::string old_atr = current_cards[reader];
        
        if (card_present && new_atr != old_atr) {
            // Card inserted or changed
            if (!old_atr.empty()) {
                // Previous card removed
                CardConfig* old_config = find_card_config(old_atr);
                if (old_config) {
                    execute_script(old_config->remove_script, "remove", old_atr);
                }
            }
            
            // New card inserted
            CardConfig* new_config = find_card_config(new_atr);
            if (new_config) {
                execute_script(new_config->insert_script, "insert", new_atr);
                debug_log("Card inserted: " + reader + " → " + new_atr);
            } else {
                debug_log("Unknown card inserted: " + reader + " → " + new_atr);
            }
            current_cards[reader] = new_atr;
            
        } else if (!card_present && !old_atr.empty()) {
            // Card removed
            CardConfig* old_config = find_card_config(old_atr);
            if (old_config) {
                execute_script(old_config->remove_script, "remove", old_atr);
            }
            debug_log("Card removed: " + reader + " (was: " + old_atr + ")");
            current_cards[reader] = "";
        }
    }

public:
    EventBasedSmartCardMonitor(bool debug = false) : debug_mode(debug) {}
    
    ~EventBasedSmartCardMonitor() {
        if (hContext) {
            SCardReleaseContext(hContext);
        }
    }
    
    void set_signal_handler() {
        signal(SIGINT, [](int) {
            std::cout << "\nStopping event monitor..." << std::endl;
            exit(0);
        });
        signal(SIGTERM, [](int) {
            std::cout << "\nStopping event monitor..." << std::endl;
            exit(0);
        });
    }
    
    void start_monitoring(const std::string& config_file = "") {
        std::string config_path = config_file.empty() ? DEFAULT_CONFIG_FILE : config_file;
        
        std::cout << "⚡ Event-Based Smart Card Monitor" << std::endl;
        std::cout << "Config file: " << config_path << std::endl;
        std::cout << "Method: PC/SC SCardGetStatusChange() events" << std::endl;
        if (debug_mode) {
            std::cout << "Debug mode: ON" << std::endl;
        }
        std::cout << "Press Ctrl+C to stop" << std::endl << std::endl;

        if (!load_config(config_path)) {
            return;
        }

        // Initialize PC/SC context
        LONG rv = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &hContext);
        if (rv != SCARD_S_SUCCESS) {
            std::cerr << "Failed to establish PC/SC context: " << std::hex << rv << std::endl;
            return;
        }
        
        log_with_timestamp("✅ PC/SC context established");
        log_with_timestamp("📋 Loaded " + std::to_string(card_configs.size()) + " card configurations");

        // Main event loop
        while (running) {
            // Get list of readers
            DWORD readers_len = SCARD_AUTOALLOCATE;
            LPSTR readers = nullptr;
            
            rv = SCardListReaders(hContext, NULL, (LPSTR)&readers, &readers_len);
            if (rv != SCARD_S_SUCCESS) {
                debug_log("No readers found, retrying in 2 seconds...");
                std::this_thread::sleep_for(std::chrono::seconds(2));
                continue;
            }
            
            // Parse reader names
            std::vector<std::string> reader_names;
            for (LPSTR reader = readers; *reader; reader += strlen(reader) + 1) {
                reader_names.push_back(std::string(reader));
            }
            SCardFreeMemory(hContext, readers);
            
            if (reader_names.empty()) {
                debug_log("No readers available, retrying...");
                std::this_thread::sleep_for(std::chrono::seconds(2));
                continue;
            }
            
            // Set up reader states for monitoring
            std::vector<SCARD_READERSTATE> reader_states(reader_names.size());
            for (size_t i = 0; i < reader_names.size(); i++) {
                reader_states[i].szReader = reader_names[i].c_str();
                reader_states[i].dwCurrentState = SCARD_STATE_UNAWARE;
            }
            
            debug_log("Monitoring " + std::to_string(reader_names.size()) + " readers for events...");
            
            // Event monitoring loop
            while (running) {
                rv = SCardGetStatusChange(hContext, 1000, reader_states.data(), reader_states.size());
                
                if (rv == SCARD_E_TIMEOUT) {
                    continue; // Normal timeout, keep monitoring
                }
                
                if (rv != SCARD_S_SUCCESS) {
                    debug_log("SCardGetStatusChange error: " + std::to_string(rv));
                    break; // Exit inner loop to refresh readers
                }
                
                // Process state changes
                for (auto& state : reader_states) {
                    if (state.dwEventState & SCARD_STATE_CHANGED) {
                        std::string reader_name(state.szReader);
                        bool card_present = (state.dwEventState & SCARD_STATE_PRESENT);
                        
                        debug_log("Event: " + reader_name + " → " + 
                                (card_present ? "PRESENT" : "ABSENT"));
                        
                        if (card_present) {
                            // Get ATR
                            std::string atr = bytes_to_hex(state.rgbAtr, state.cbAtr);
                            handle_card_event(reader_name, atr, true);
                        } else {
                            handle_card_event(reader_name, "", false);
                        }
                        
                        // Update current state
                        state.dwCurrentState = state.dwEventState;
                    }
                }
            }
        }
    }
};

int main(int argc, char* argv[]) {
    bool debug = false;
    std::string config_file = "";
    
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--debug" || arg == "-d") {
            debug = true;
        } else if (arg == "--config" || arg == "-c") {
            if (i + 1 < argc) {
                config_file = argv[++i];
            }
        } else if (arg == "--help" || arg == "-h") {
            std::cout << "Event-Based Smart Card Monitor" << std::endl;
            std::cout << "Usage: " << argv[0] << " [options]" << std::endl;
            std::cout << "Options:" << std::endl;
            std::cout << "  --debug, -d           Enable debug output" << std::endl;
            std::cout << "  --config FILE, -c     Use custom config file" << std::endl;
            std::cout << "  --help, -h            Show this help" << std::endl;
            std::cout << std::endl;
            std::cout << "This version uses PC/SC SCardGetStatusChange() for instant" << std::endl;
            std::cout << "event detection with zero CPU usage when idle." << std::endl;
            return 0;
        }
    }
    
    EventBasedSmartCardMonitor monitor(debug);
    monitor.set_signal_handler();
    monitor.start_monitoring(config_file);
    
    return 0;
}