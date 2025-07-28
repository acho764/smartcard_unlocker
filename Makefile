CXX = g++
CXXFLAGS = -std=c++11 -Wall -Wextra -O2
PCSC_CFLAGS = -I/usr/include/PCSC -pthread
PCSC_LIBS = -lpcsclite

TARGET = smartcard_monitor
CONFIG_TARGET = smartcard_config_monitor
EVENT_TARGET = smartcard_event_monitor

SOURCE = smartcard_monitor.cpp
CONFIG_SOURCE = smartcard_config_monitor.cpp
EVENT_SOURCE = smartcard_event_monitor.cpp

all: $(TARGET) $(CONFIG_TARGET) $(EVENT_TARGET)

$(TARGET): $(SOURCE)
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(SOURCE)

$(CONFIG_TARGET): $(CONFIG_SOURCE)
	$(CXX) $(CXXFLAGS) -o $(CONFIG_TARGET) $(CONFIG_SOURCE)

$(EVENT_TARGET): $(EVENT_SOURCE)
	$(CXX) $(CXXFLAGS) $(PCSC_CFLAGS) -o $(EVENT_TARGET) $(EVENT_SOURCE) $(PCSC_LIBS)

clean:
	rm -f $(TARGET) $(CONFIG_TARGET) $(EVENT_TARGET)

install: all
	cp $(TARGET) /usr/local/bin/
	cp $(CONFIG_TARGET) /usr/local/bin/
	cp $(EVENT_TARGET) /usr/local/bin/

.PHONY: all clean install