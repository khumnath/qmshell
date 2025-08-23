cmake_minimum_required(VERSION 3.16)
project(qmshell LANGUAGES CXX)

# --- Run version script ---
execute_process(
    COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/update_version.sh"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    RESULT_VARIABLE VERSION_SCRIPT_RESULT
)
if(NOT VERSION_SCRIPT_RESULT EQUAL 0)
    message(WARNING "The version update script failed to run. Version info may be stale or incorrect.")
endif()

set(VERSION_FILE "${CMAKE_CURRENT_SOURCE_DIR}/data/version.conf")

if(EXISTS "${VERSION_FILE}")
    file(READ "${VERSION_FILE}" PROJECT_VERSION_STRING)
    string(STRIP "${PROJECT_VERSION_STRING}" PROJECT_VERSION_STRING)
else()
    set(PROJECT_VERSION_STRING "0.0.0")
    message(WARNING "Could not find version file: ${VERSION_FILE}. Defaulting to version ${PROJECT_VERSION_STRING}.")
endif()

message(STATUS "Configuring qmshell version: ${PROJECT_VERSION_STRING}")

# --- Build setup ---
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)  # automatically processes .qrc
set(CMAKE_AUTOUIC ON)

# --- Find Qt6 modules ---
find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets Quick QuickControls2)

# --- Executable ---
qt_add_executable(qmshell
    src/main.cpp
    src/settingsmanager.cpp
    src/terminalbackend.cpp
    src/terminalcolor.cpp
    src/settingsmanager.h
    src/terminalbackend.h
    src/terminalcolor.h
    qmshell.qrc        # qrc compiled automatically
)

# --- Link Qt libraries ---
target_link_libraries(qmshell PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::Quick
    Qt6::QuickControls2
)

# --- Install rules ---
install(TARGETS qmshell DESTINATION bin)
install(FILES data/qmshell.desktop DESTINATION share/applications)

# PNG icons (recursive)
if(EXISTS "${CMAKE_SOURCE_DIR}/data/icons")
    file(GLOB_RECURSE ICONS_PNG RELATIVE ${CMAKE_SOURCE_DIR} "data/icons/hicolor/*/*/qmshell.png")
    foreach(icon ${ICONS_PNG})
        get_filename_component(dir ${icon} DIRECTORY)
        install(FILES ${icon} DESTINATION share/icons/${dir})
    endforeach()
endif()

# SVG icon
install(FILES data/icons/hicolor/scalable/apps/qmshell.svg
        DESTINATION share/icons/hicolor/scalable/apps)
