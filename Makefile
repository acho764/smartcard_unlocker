CXX = g++
CXXFLAGS = -std=c++11 -Wall -Wextra -O2
TARGET = smartcard_monitor
CONFIG_TARGET = smartcard_config_monitor
SOURCE = smartcard_monitor.cpp
CONFIG_SOURCE = smartcard_config_monitor.cpp

all: $(TARGET) $(CONFIG_TARGET)

$(TARGET): $(SOURCE)
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(SOURCE)

$(CONFIG_TARGET): $(CONFIG_SOURCE)
	$(CXX) $(CXXFLAGS) -o $(CONFIG_TARGET) $(CONFIG_SOURCE)

clean:
	rm -f $(TARGET) $(CONFIG_TARGET)

install: all
	cp $(TARGET) /usr/local/bin/
	cp $(CONFIG_TARGET) /usr/local/bin/

.PHONY: all clean install