cmake_minimum_required(VERSION 3.13)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# initalize pico_sdk from installed location
# (note this can come from environment, CMake cache etc)
set(PICO_SDK_PATH $ENV{PICO_SDK_PATH})

#include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)
#include($ENV{PICO_SDK_PATH}/tools/CMakeLists.txt)

# Pull in Raspberry Pi Pico SDK (must be before project)
include(pico_sdk_import.cmake)

project(usb-to-trs80-keyboard C CXX ASM)

# Initialise the Raspberry Pi Pico SDK
pico_sdk_init()

# Add executable. Default name is the project name, version 0.1
add_executable(usb-to-trs80-keyboard main.c)

target_sources(usb-to-trs80-keyboard PRIVATE
			main.c
			usb_hid.c
			trs80.c
			kbd_ringbuffer.c)

pico_set_program_name(usb-to-trs80-keyboard "usb-to-trs80-keyboard")
pico_set_program_version(usb-to-trs80-keyboard "0.1")

pico_enable_stdio_uart(usb-to-trs80-keyboard 0)

# Add the standard library to the build
target_link_libraries(usb-to-trs80-keyboard pico_stdlib)
target_include_directories (usb-to-trs80-keyboard PUBLIC .)

# Add any user requested libraries
target_link_libraries(usb-to-trs80-keyboard
        pico_stdlib			
        hardware_uart
        hardware_timer
        hardware_pio
	tinyusb_host			
	tinyusb_board
        )

pico_add_extra_outputs(usb-to-trs80-keyboard)



