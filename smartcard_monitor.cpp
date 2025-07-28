#include <iostream>
#include <string>
#include <chrono>
#include <thread>
#include <cstdlib>
#include <memory>
#include <stdexcept>
#include <array>
#include <iomanip>
#include <signal.h>
#include <unistd.h>

class SmartCardMonitor {
private:
    const std::string TARGET_ATR = "0081314544303832203655";
    const int CHECK_INTERVAL_MS = 500;
    bool debug_mode = false;
    bool card_present = false;
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

    bool is_target_card_present() {
        std::string current_atr = get_current_atr();
        
        if (debug_mode) {
            debug_log("Current ATR: '" + current_atr + "'");
        }
        
        return current_atr == TARGET_ATR;
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

    void unlock_screen() {
        log_with_timestamp("🔓 Smart card detected! Unlocking...");
        
        // Try multiple unlock methods
        system("loginctl unlock-session 2>/dev/null");
        system("gnome-screensaver-command -d 2>/dev/null");
        
        // Wake screen
        if (getenv("DISPLAY")) {
            system("xdotool key space 2>/dev/null");
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            system("xdotool key Escape 2>/dev/null");
        }
    }

    void lock_screen() {
        log_with_timestamp("🔒 Smart card removed! Locking...");
        
        // Try multiple lock methods
        int result = system("loginctl lock-session 2>/dev/null");
        if (result != 0) {
            system("gnome-screensaver-command -l 2>/dev/null");
        }
        if (result != 0) {
            system("xdg-screensaver lock 2>/dev/null");
        }
    }

public:
    SmartCardMonitor(bool debug = false) : debug_mode(debug) {}

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

    void start_monitoring() {
        std::cout << "C++ Smart Card Monitor" << std::endl;
        std::cout << "Target ATR: " << TARGET_ATR << std::endl;
        std::cout << "Check interval: " << CHECK_INTERVAL_MS << "ms" << std::endl;
        if (debug_mode) {
            std::cout << "Debug mode: ON" << std::endl;
        }
        std::cout << "Press Ctrl+C to stop" << std::endl << std::endl;

        // Initialize state
        card_present = is_target_card_present();
        if (card_present) {
            log_with_timestamp("Initial state: Target card present");
        } else {
            log_with_timestamp("Initial state: No target card");
        }

        // Main monitoring loop
        while (running) {
            bool current_state = is_target_card_present();
            
            if (current_state && !card_present) {
                unlock_screen();
                card_present = true;
            } else if (!current_state && card_present) {
                lock_screen();
                card_present = false;
            }
            
            debug_log(current_state ? "Card present ✓" : "Card absent ✗");
            
            std::this_thread::sleep_for(std::chrono::milliseconds(CHECK_INTERVAL_MS));
        }
    }
};

int main(int argc, char* argv[]) {
    bool debug = false;
    
    // Check for debug flag
    if (argc > 1 && std::string(argv[1]) == "--debug") {
        debug = true;
    }
    
    SmartCardMonitor monitor(debug);
    monitor.set_signal_handler();
    monitor.start_monitoring();
    
    return 0;
}