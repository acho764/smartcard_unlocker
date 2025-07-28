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

struct CardConfig {
    std::string atr;
    std::string insert_script;
    std::string remove_script;
};

class ConfigurableSmartCardMonitor {
private:
    const int CHECK_INTERVAL_MS = 500;
    const std::string DEFAULT_CONFIG_FILE = "smartcard.conf";
    bool debug_mode = false;
    std::string current_card_atr = "";
    std::map<std::string, CardConfig> card_configs;
    volatile bool running = true;

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

    std::string get_current_atr() {
        std::string output = exec_command("timeout 2 opensc-tool --atr 2>/dev/null");
        
        // Extract hex digits and remove spaces
        std::string atr;
        for (char c : output) {
            if (std::isxdigit(c)) {
                atr += std::toupper(c);
            } else if (c == ' ' && !atr.empty() && std::isxdigit(atr.back())) {
                // Skip spaces between hex digits
                continue;
            }
        }
        
        return atr;
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

        log_with_timestamp("🎯 Card " + atr.substr(0, 8) + "... detected! Executing " + action + " script: " + script_path);
        
        // Check if script exists and is executable
        if (access(script_path.c_str(), X_OK) != 0) {
            log_with_timestamp("❌ Script not found or not executable: " + script_path);
            return;
        }

        // Execute the script
        std::string command = script_path + " 2>/dev/null";
        int result = system(command.c_str());
        
        if (result == 0) {
            debug_log("Script executed successfully: " + script_path);
        } else {
            debug_log("Script execution failed: " + script_path + " (exit code: " + std::to_string(result) + ")");
        }
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
            // Remove leading/trailing whitespace
            line.erase(0, line.find_first_not_of(" \t"));
            line.erase(line.find_last_not_of(" \t") + 1);

            // Skip empty lines and comments
            if (line.empty() || line[0] == '#' || line[0] == ';') {
                continue;
            }

            // Check for ATR section header [ATR]
            if (line[0] == '[' && line.back() == ']') {
                // Save previous config if valid
                if (!current_atr.empty()) {
                    current_config.atr = current_atr;
                    card_configs[current_atr] = current_config;
                }

                // Start new config
                current_atr = line.substr(1, line.length() - 2);
                current_config = CardConfig();
                debug_log("Found ATR config: " + current_atr);
                continue;
            }

            // Parse key=value pairs
            size_t equals_pos = line.find('=');
            if (equals_pos != std::string::npos && !current_atr.empty()) {
                std::string key = line.substr(0, equals_pos);
                std::string value = line.substr(equals_pos + 1);

                // Remove whitespace around key and value
                key.erase(0, key.find_first_not_of(" \t"));
                key.erase(key.find_last_not_of(" \t") + 1);
                value.erase(0, value.find_first_not_of(" \t"));
                value.erase(value.find_last_not_of(" \t") + 1);

                if (key == "insert") {
                    current_config.insert_script = value;
                    debug_log("  Insert script: " + value);
                } else if (key == "remove") {
                    current_config.remove_script = value;
                    debug_log("  Remove script: " + value);
                }
            }
        }

        // Save last config
        if (!current_atr.empty()) {
            current_config.atr = current_atr;
            card_configs[current_atr] = current_config;
        }

        file.close();

        if (card_configs.empty()) {
            std::cerr << "Error: No valid card configurations found in " << config_file << std::endl;
            return false;
        }

        log_with_timestamp("Loaded " + std::to_string(card_configs.size()) + " card configurations");
        return true;
    }

public:
    ConfigurableSmartCardMonitor(bool debug = false) : debug_mode(debug) {}

    void set_signal_handler() {
        signal(SIGINT, [](int) {
            std::cout << "\nStopping monitor..." << std::endl;
            exit(0);
        });
        signal(SIGTERM, [](int) {
            std::cout << "\nStopping monitor..." << std::endl;
            exit(0);
        });
    }

    void start_monitoring(const std::string& config_file = "") {
        std::string config_path = config_file.empty() ? DEFAULT_CONFIG_FILE : config_file;
        
        std::cout << "Configurable Smart Card Monitor" << std::endl;
        std::cout << "Config file: " << config_path << std::endl;
        std::cout << "Check interval: " << CHECK_INTERVAL_MS << "ms" << std::endl;
        if (debug_mode) {
            std::cout << "Debug mode: ON" << std::endl;
        }
        std::cout << "Press Ctrl+C to stop" << std::endl << std::endl;

        // Load configuration
        if (!load_config(config_path)) {
            return;
        }

        // Display loaded configurations
        std::cout << "Configured cards:" << std::endl;
        for (const auto& pair : card_configs) {
            std::cout << "  ATR: " << pair.first << std::endl;
            std::cout << "    Insert: " << (pair.second.insert_script.empty() ? "(none)" : pair.second.insert_script) << std::endl;
            std::cout << "    Remove: " << (pair.second.remove_script.empty() ? "(none)" : pair.second.remove_script) << std::endl;
        }
        std::cout << std::endl;

        // Initialize state
        std::string initial_atr = get_current_atr();
        CardConfig* initial_config = find_card_config(initial_atr);
        
        if (initial_config) {
            current_card_atr = initial_atr;
            log_with_timestamp("Initial state: Card present (" + initial_atr.substr(0, 8) + "...)");
        } else {
            current_card_atr = "";
            log_with_timestamp("Initial state: No configured card detected");
        }

        // Main monitoring loop
        while (running) {
            std::string detected_atr = get_current_atr();
            CardConfig* detected_config = find_card_config(detected_atr);
            
            debug_log("Current ATR: '" + detected_atr + "'");

            if (detected_config && current_card_atr.empty()) {
                // Card inserted
                current_card_atr = detected_atr;
                execute_script(detected_config->insert_script, "insert", detected_atr);
                debug_log("Card inserted: " + detected_atr);
                
            } else if (detected_config && current_card_atr != detected_atr) {
                // Different card inserted (swap)
                CardConfig* previous_config = find_card_config(current_card_atr);
                if (previous_config) {
                    execute_script(previous_config->remove_script, "remove", current_card_atr);
                }
                current_card_atr = detected_atr;
                execute_script(detected_config->insert_script, "insert", detected_atr);
                debug_log("Card swapped: " + current_card_atr + " -> " + detected_atr);
                
            } else if (!detected_config && !current_card_atr.empty()) {
                // Card removed
                CardConfig* previous_config = find_card_config(current_card_atr);
                if (previous_config) {
                    execute_script(previous_config->remove_script, "remove", current_card_atr);
                }
                debug_log("Card removed: " + current_card_atr);
                current_card_atr = "";
            }
            
            std::this_thread::sleep_for(std::chrono::milliseconds(CHECK_INTERVAL_MS));
        }
    }
};

int main(int argc, char* argv[]) {
    bool debug = false;
    std::string config_file = "";
    
    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--debug" || arg == "-d") {
            debug = true;
        } else if (arg == "--config" || arg == "-c") {
            if (i + 1 < argc) {
                config_file = argv[++i];
            } else {
                std::cerr << "Error: --config requires a filename" << std::endl;
                return 1;
            }
        } else if (arg == "--help" || arg == "-h") {
            std::cout << "Usage: " << argv[0] << " [options]" << std::endl;
            std::cout << "Options:" << std::endl;
            std::cout << "  --debug, -d           Enable debug output" << std::endl;
            std::cout << "  --config FILE, -c     Use custom config file (default: smartcard.conf)" << std::endl;
            std::cout << "  --help, -h            Show this help" << std::endl;
            return 0;
        } else {
            std::cerr << "Unknown argument: " << arg << std::endl;
            return 1;
        }
    }
    
    ConfigurableSmartCardMonitor monitor(debug);
    monitor.set_signal_handler();
    monitor.start_monitoring(config_file);
    
    return 0;
}