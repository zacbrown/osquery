#  Copyright (c) 2014-present, Facebook, Inc.
#  All rights reserved.
#
#  This source code is licensed under both the Apache 2.0 license (found in the
#  LICENSE file in the root directory of this source tree) and the GPLv2 (found
#  in the COPYING file in the root directory of this source tree).
#  You may select, at your option, one of the above-listed licenses.

# osquery-specific helper macros
macro(LOG_PLATFORM NAME)
  if(NOT DEFINED ENV{SKIP_DEPS})
    set(LINK "http://osquery.readthedocs.io/en/stable/development/building/")
    LOG("Welcome to osquery's build -- thank you for your patience! :)")
    LOG("For a brief tutorial see: ${ESC}[1m${LINK}${ESC}[m")
    if(WINDOWS)
      LOG("If at first you dont succeed, perhaps re-run make-win64-dev-env.bat and make-win64-binaries.bat")
    else()
      LOG("If at first you dont succeed, perhaps: make distclean; make depsclean")
    endif()
  endif()
  LOG("Building for platform ${ESC}[36;1m${NAME} (${OSQUERY_BUILD_PLATFORM}, ${OSQUERY_BUILD_DISTRO})${ESC}[m")
  LOG("Building osquery version ${ESC}[36;1m ${OSQUERY_BUILD_VERSION} sdk ${OSQUERY_BUILD_SDK_VERSION}${ESC}[m")
endmacro(LOG_PLATFORM)

macro(LOG_LIBRARY NAME PATH)
  set(CACHE_NAME "LOG_LIBRARY_${NAME}")
  if(NOT DEFINED ${CACHE_NAME} OR NOT ${${CACHE_NAME}})
    set(${CACHE_NAME} TRUE CACHE BOOL "Write log line for ${NAME} library.")
    set(BUILD_POSITION -1)
    string(FIND "${PATH}" "${CMAKE_BINARY_DIR}" BUILD_POSITION)
    string(FIND "${PATH}" "NOTFOUND" NOTFOUND_POSITION)
    if(${NOTFOUND_POSITION} GREATER 0)
      WARNING_LOG("Could not find library: ${NAME}")
    else()
      if(${BUILD_POSITION} EQUAL 0)
        string(LENGTH "${CMAKE_BINARY_DIR}" BUILD_DIR_LENGTH)
        string(SUBSTRING "${PATH}" ${BUILD_DIR_LENGTH} -1 LIB_PATH)
        LOG("Found osquery-built library ${ESC}[32m${LIB_PATH}${ESC}[m")
      else()
        LOG("Found library ${ESC}[32m${PATH}${ESC}[m")
      endif()
    endif()
  endif()
endmacro(LOG_LIBRARY)

macro(SET_OSQUERY_COMPILE TARGET)
  set(OPTIONAL_FLAGS ${ARGN})
  list(LENGTH OPTIONAL_FLAGS NUM_OPTIONAL_FLAGS)
  if(${NUM_OPTIONAL_FLAGS} GREATER 0)
    set_target_properties(${TARGET} PROPERTIES COMPILE_FLAGS "${OPTIONAL_FLAGS}")
  endif()
  if(DO_CLANG_TIDY AND NOT "${TARGET}" STREQUAL "osquery_extensions")
    set_target_properties(${TARGET} PROPERTIES CXX_CLANG_TIDY "${DO_CLANG_TIDY}")
  endif()
endmacro(SET_OSQUERY_COMPILE)

macro(ADD_DEFAULT_LINKS TARGET ADDITIONAL)
  if(DEFINED ENV{OSQUERY_BUILD_SHARED})
    target_link_libraries(${TARGET} libosquery_shared)
    if(${ADDITIONAL})
      target_link_libraries(${TARGET} libosquery_additional_shared)
    endif()
    target_link_libraries(${TARGET} "-Wl,-rpath,${CMAKE_BINARY_DIR}/osquery")
    target_link_libraries(${TARGET} ${OSQUERY_LINKS})
    if(${ADDITIONAL})
      target_link_libraries(${TARGET} ${OSQUERY_ADDITIONAL_LINKS})
    endif()
  else()
    TARGET_OSQUERY_LINK_WHOLE(${TARGET} libosquery)
    if(${ADDITIONAL})
      TARGET_OSQUERY_LINK_WHOLE(${TARGET} libosquery_additional)
    endif()
  endif()
endmacro()

macro(ADD_OSQUERY_PYTHON_TEST TEST_NAME SOURCE)
  if(NOT DEFINED ENV{SKIP_INTEGRATION_TESTS})
    add_test(NAME python_${TEST_NAME}
      COMMAND ${PYTHON_EXECUTABLE} "${CMAKE_SOURCE_DIR}/tools/tests/${SOURCE}"
        --verbose --build "${CMAKE_BINARY_DIR}"
      WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/tools/tests/")
  endif()
endmacro(ADD_OSQUERY_PYTHON_TEST)

# Add a static or dynamic link to libosquery.a (the core library)
macro(ADD_OSQUERY_LINK_CORE LINK)
  ADD_OSQUERY_LINK(TRUE ${LINK} ${ARGN})
endmacro(ADD_OSQUERY_LINK_CORE)

# Add a static or dynamic link to libosquery_additional.a (the non-sdk library)
macro(ADD_OSQUERY_LINK_ADDITIONAL LINK)
  ADD_OSQUERY_LINK(FALSE ${LINK} ${ARGN})
endmacro(ADD_OSQUERY_LINK_ADDITIONAL)

# Core/non core link helping macros (tell the build to link ALL).
macro(ADD_OSQUERY_LINK IS_CORE LINK)
  if(${IS_CORE})
    ADD_OSQUERY_LINK_INTERNAL("${LINK}" "${ARGN}" OSQUERY_LINKS)
  elseif(NOT OSQUERY_BUILD_SDK_ONLY)
    ADD_OSQUERY_LINK_INTERNAL("${LINK}" "${ARGN}" OSQUERY_ADDITIONAL_LINKS)
  endif()
endmacro(ADD_OSQUERY_LINK)

macro(ADD_OSQUERY_LINK_INTERNAL LINK LINK_PATHS LINK_SET)
  # The relative linking set is used for static libraries.
  set(LINK_PATHS_RELATIVE
    "${BUILD_DEPS}/lib"
    ${LINK_PATHS}
    ${OS_LIB_DIRS}
    "$ENV{HOME}"
  )

  # The system linking set is for legacy ABI compatibility links and libraries
  # known to exist on the system.
  set(LINK_PATHS_SYSTEM
    ${LINK_PATHS}
    "${BUILD_DEPS}/legacy/lib"
  )
  if(LINUX)
    # Allow the build to search the 'default' dependency home for libgcc_s.
    list(APPEND LINK_PATHS_SYSTEM "${BUILD_DEPS}/lib")
  endif()
  # The OS library paths are very important for system linking.
  list(APPEND LINK_PATHS_SYSTEM ${OS_LIB_DIRS})

  if(NOT "${LINK}" MATCHES "(^[-/].*)")
    string(REPLACE " " ";" ITEMS "${LINK}")
    foreach(ITEM ${ITEMS})
      if(NOT DEFINED ${${ITEM}_library})
        if("${ITEM}" MATCHES "(^lib.*)" OR "${ITEM}" MATCHES "(.*lib$)" OR DEFINED ENV{BUILD_LINK_SHARED})
          # Use a system-provided library
          set(ITEM_SYSTEM TRUE)
        else()
          set(ITEM_SYSTEM FALSE)
        endif()
        if(NOT ${ITEM_SYSTEM})
          find_library("${ITEM}_library"
            NAMES
              "${ITEM}.lib"
              "lib${ITEM}.lib"
              "lib${ITEM}-mt.a"
              "lib${ITEM}.a"
              "${ITEM}"
            HINTS ${LINK_PATHS_RELATIVE})
        else()
          find_library("${ITEM}_library"
            NAMES
              "${ITEM}.lib"
              "lib${ITEM}.lib"
              "lib${ITEM}-mt.so"
              "lib${ITEM}.so"
              "lib${ITEM}-mt.dylib"
              "lib${ITEM}.dylib"
              "${ITEM}-mt.so"
              "${ITEM}.so"
              "${ITEM}-mt.dylib"
              "${ITEM}.dylib"
              "${ITEM}"
            HINTS ${LINK_PATHS_SYSTEM})
        endif()
        LOG_LIBRARY(${ITEM} "${${ITEM}_library}")
        if("${${ITEM}_library}" STREQUAL "${ITEM}_library-NOTFOUND")
          WARNING_LOG("Dependent library '${ITEM}' not found")
          list(APPEND ${LINK_SET} ${ITEM})
        else()
          list(APPEND ${LINK_SET} "${${ITEM}_library}")
        endif()
      endif()
      if("${${ITEM}_library}" MATCHES "/usr/local/lib.*")
        if(NOT FREEBSD AND NOT DEFINED ENV{SKIP_DEPS})
          WARNING_LOG("Dependent library '${ITEM}' installed locally (beware!)")
        endif()
      endif()
    endforeach()
  else()
    list(APPEND ${LINK_SET} ${LINK})
  endif()
  set(${LINK_SET} "${${LINK_SET}}" PARENT_SCOPE)
endmacro(ADD_OSQUERY_LINK_INTERNAL)

# Add a test and sources for components in libosquery.a (the core library)
macro(ADD_OSQUERY_TEST_CORE)
  ADD_OSQUERY_TEST(TRUE ${ARGN})
endmacro(ADD_OSQUERY_TEST_CORE)

# Add a test and sources for components in libosquery_additional.a (the non-sdk library)
macro(ADD_OSQUERY_TEST_ADDITIONAL)
  ADD_OSQUERY_TEST(FALSE ${ARGN})
endmacro(ADD_OSQUERY_TEST_ADDITIONAL)

# Core/non core test names and sources macros.
macro(ADD_OSQUERY_TEST IS_CORE)
  if(NOT SKIP_TESTS AND (${IS_CORE} OR NOT OSQUERY_BUILD_SDK_ONLY))
    if(${IS_CORE})
      list(APPEND OSQUERY_TESTS ${ARGN})
      set(OSQUERY_TESTS ${OSQUERY_TESTS} PARENT_SCOPE)
    else()
      list(APPEND OSQUERY_ADDITIONAL_TESTS ${ARGN})
      set(OSQUERY_ADDITIONAL_TESTS ${OSQUERY_ADDITIONAL_TESTS} PARENT_SCOPE)
    endif()
  endif()
endmacro(ADD_OSQUERY_TEST)

macro(ADD_OSQUERY_TABLE_TEST)
  if(NOT SKIP_TESTS AND NOT OSQUERY_BUILD_SDK_ONLY)
    list(APPEND OSQUERY_TABLES_TESTS ${ARGN})
    set(OSQUERY_TABLES_TESTS ${OSQUERY_TABLES_TESTS} PARENT_SCOPE)
  endif()
endmacro(ADD_OSQUERY_TABLE_TEST)

# Add benchmark macro.
macro(ADD_OSQUERY_BENCHMARK)
  if(NOT SKIP_TESTS)
    list(APPEND OSQUERY_BENCHMARKS ${ARGN})
    set(OSQUERY_BENCHMARKS ${OSQUERY_BENCHMARKS} PARENT_SCOPE)
  endif()
endmacro(ADD_OSQUERY_BENCHMARK)

# Add sources to libosquery.a (the core library)
macro(ADD_OSQUERY_LIBRARY_CORE TARGET)
  ADD_OSQUERY_LIBRARY(TRUE ${TARGET} ${ARGN})
endmacro(ADD_OSQUERY_LIBRARY_CORE)

# Add sources to libosquery_additional.a (the non-sdk library)
macro(ADD_OSQUERY_LIBRARY_ADDITIONAL TARGET)
  ADD_OSQUERY_LIBRARY(FALSE ${TARGET} ${ARGN})
endmacro(ADD_OSQUERY_LIBRARY_ADDITIONAL)

function(add_darwin_compile_flag_if_needed file) 
  set(EXT_POSITION -1)
  string(FIND "${SOURCE_FILE}" ".mm" EXT_POSITION)
  if(EXT_POSITION GREATER 0)
    set_source_files_properties("${file}"
      PROPERTIES COMPILE_FLAGS ${OBJCXX_COMPILE_FLAGS})
  endif()
endfunction()

# Core/non core lists of target source files.
macro(ADD_OSQUERY_LIBRARY IS_CORE TARGET)
  if(${IS_CORE} OR NOT OSQUERY_BUILD_SDK_ONLY)
    foreach(SOURCE_FILE ${ARGN})
      add_darwin_compile_flag_if_needed(${SOURCE_FILE})
    endforeach()
    add_library(${TARGET} OBJECT ${ARGN})
    add_dependencies(${TARGET} osquery_extensions)
    if(${IS_CORE})
      list(APPEND OSQUERY_SOURCES $<TARGET_OBJECTS:${TARGET}>)
      set(OSQUERY_SOURCES ${OSQUERY_SOURCES} PARENT_SCOPE)
    else()
      list(APPEND OSQUERY_ADDITIONAL_SOURCES $<TARGET_OBJECTS:${TARGET}>)
      set(OSQUERY_ADDITIONAL_SOURCES ${OSQUERY_ADDITIONAL_SOURCES} PARENT_SCOPE)
    endif()
  endif()
endmacro(ADD_OSQUERY_LIBRARY TARGET)

function(darwin_target_sources target ...)
  target_sources(${ARGV})
  get_target_property(files ${target} SOURCES)
  foreach(file ${files})
    add_darwin_compile_flag_if_needed(${file})
  endforeach(file)
endfunction()

macro(ADD_OSQUERY_EXTENSION TARGET)
  add_executable(${TARGET} ${ARGN})
  TARGET_OSQUERY_LINK_WHOLE(${TARGET} libosquery)
  set_target_properties(${TARGET} PROPERTIES OUTPUT_NAME "${TARGET}.ext")
endmacro(ADD_OSQUERY_EXTENSION)

function(add_osquery_extension_ex class_name extension_type extension_name ${ARGN})
  # Make sure the extension type is valid
  if(NOT "${extension_type}" STREQUAL "config" AND NOT "${extension_type}" STREQUAL "table")
    message(FATAL_ERROR "Invalid extension type specified")
  endif()

  # Update the initializer list; this will be added to the main.cpp file of the extension
  # group
  set_property(GLOBAL APPEND_STRING
    PROPERTY OSQUERY_EXTENSION_GROUP_INITIALIZERS
    "REGISTER_EXTERNAL(${class_name}, \"${extension_type}\", \"${extension_name}\");\n"
  )

  # Loop through each argument
  foreach(argument ${ARGN})
    if("${argument}" STREQUAL "SOURCES" OR "${argument}" STREQUAL "LIBRARIES" OR
      "${argument}" STREQUAL "INCLUDEDIRS" OR "${argument}" STREQUAL "MAININCLUDES")

      set(current_scope "${argument}")
      continue()
    endif()

    if("${current_scope}" STREQUAL "SOURCES")
      if(NOT IS_ABSOLUTE "${argument}")
        set(argument "${CMAKE_CURRENT_SOURCE_DIR}/${argument}")
      endif()

      list(APPEND source_file_list "${argument}")

    elseif("${current_scope}" STREQUAL "INCLUDEDIRS")
      if(NOT IS_ABSOLUTE "${argument}")
        set(argument "${CMAKE_CURRENT_SOURCE_DIR}/${argument}")
      endif()

      list(APPEND include_folder_list "${argument}")

    elseif("${current_scope}" STREQUAL "LIBRARIES")
      list(APPEND library_list "${argument}")
    elseif("${current_scope}" STREQUAL "MAININCLUDES")
      list(APPEND main_include_list "${argument}")
    else()
      message(FATAL_ERROR "Invalid scope")
    endif()
  endforeach()

  # Validate the arguments
  if("${source_file_list}" STREQUAL "")
    message(FATAL_ERROR "Source files are missing")
  endif()

  if("${main_include_list}" STREQUAL "")
    message(FATAL_ERROR "The main include list is missing")
  endif()

  # Update the global properties
  set_property(GLOBAL APPEND
    PROPERTY OSQUERY_EXTENSION_GROUP_SOURCES
    ${source_file_list}
  )

  set_property(GLOBAL APPEND
    PROPERTY OSQUERY_EXTENSION_GROUP_MAIN_INCLUDES
    ${main_include_list}
  )

  if(NOT "${library_list}" STREQUAL "")
    set_property(GLOBAL APPEND
      PROPERTY OSQUERY_EXTENSION_GROUP_LIBRARIES
      ${library_list}
    )
  endif()

  if(NOT "${include_folder_list}" STREQUAL "")
    set_property(GLOBAL APPEND
      PROPERTY OSQUERY_EXTENSION_GROUP_INCLUDE_FOLDERS
      ${include_folder_list}
    )
  endif()
endfunction()

# This function takes the global properties saved by add_osquery_extension_ex and generates
# a single extenion executable containing all the user code
function(generate_osquery_extension_group)
  get_property(extension_source_files GLOBAL PROPERTY OSQUERY_EXTENSION_GROUP_SOURCES)
  if("${extension_source_files}" STREQUAL "")
    return()
  endif()

  # Allow the user to customize the extension name and version using
  # environment variables
  if(DEFINED ENV{OSQUERY_EXTENSION_GROUP_NAME})
    set(OSQUERY_EXTENSION_GROUP_NAME $ENV{OSQUERY_EXTENSION_GROUP_NAME})
  else()
    set(OSQUERY_EXTENSION_GROUP_NAME "osquery_extension_group")
  endif()

  if(DEFINED ENV{OSQUERY_EXTENSION_GROUP_VERSION})
    set(OSQUERY_EXTENSION_GROUP_VERSION $ENV{OSQUERY_EXTENSION_GROUP_VERSION})
  else()
    set(OSQUERY_EXTENSION_GROUP_VERSION "1.0")
  endif()

  # Build the include list; this contains the files required to declare
  # the classes used in the REGISTER_EXTERNAL directives
  #
  # Note: The variables in uppercase are used by the template
  get_property(main_include_list GLOBAL PROPERTY OSQUERY_EXTENSION_GROUP_MAIN_INCLUDES)
  foreach(include_file ${main_include_list})
    set(OSQUERY_EXTENSION_GROUP_INCLUDES "${OSQUERY_EXTENSION_GROUP_INCLUDES}\n#include <${include_file}>")
  endforeach()

  # We need to generate the main.cpp file, containing all the required
  # REGISTER_EXTERNAL directives
  get_property(OSQUERY_EXTENSION_GROUP_INITIALIZERS GLOBAL PROPERTY OSQUERY_EXTENSION_GROUP_INITIALIZERS)
  configure_file(
    "${CMAKE_SOURCE_DIR}/tools/codegen/templates/osquery_extension_group_main.cpp.in"
    "${CMAKE_CURRENT_BINARY_DIR}/osquery_extension_group_main.cpp"
  )

  # Extensions can no longer control which compilation flags to use here (as they are shared) so
  # we are going to enforce sane defaults
  if(UNIX)
    set(extension_cxx_flags
      -pedantic -Wall -Wcast-align -Wcast-qual -Wctor-dtor-privacy -Wdisabled-optimization
      -Wformat=2 -Winit-self -Wlong-long -Wmissing-declarations -Wmissing-include-dirs -Wcomment
      -Wold-style-cast -Woverloaded-virtual -Wredundant-decls -Wshadow -Wsign-conversion
      -Wsign-promo -Wstrict-overflow=5 -Wswitch-default -Wundef -Werror -Wunused -Wuninitialized
      -Wconversion
    )

    if(CMAKE_BUILD_TYPE STREQUAL "Debug" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
      list(APPEND extension_cxx_flags -g3 --gdwarf-2)
    endif()
  else()
    set(extension_cxx_flags /W4)
  endif()

  # Generate the extension target
  add_executable("${OSQUERY_EXTENSION_GROUP_NAME}"
    "${CMAKE_CURRENT_BINARY_DIR}/osquery_extension_group_main.cpp"
    ${extension_source_files}
  )

  set_property(TARGET "${OSQUERY_EXTENSION_GROUP_NAME}" PROPERTY INCLUDE_DIRECTORIES "")
  target_compile_features("${OSQUERY_EXTENSION_GROUP_NAME}" PUBLIC cxx_std_14)
  target_compile_options("${OSQUERY_EXTENSION_GROUP_NAME}" PRIVATE ${extension_cxx_flags})

  set_target_properties("${OSQUERY_EXTENSION_GROUP_NAME}" PROPERTIES
    OUTPUT_NAME "${OSQUERY_EXTENSION_GROUP_NAME}.ext"
  )

  # Import the core libraries; note that we are going to inherit include directories
  # with the wrong scope, so we'll have to fix it
  set_property(TARGET "${OSQUERY_EXTENSION_GROUP_NAME}" PROPERTY INCLUDE_DIRECTORIES "")

  get_property(include_folder_list TARGET libosquery PROPERTY INCLUDE_DIRECTORIES)
  target_include_directories("${OSQUERY_EXTENSION_GROUP_NAME}" SYSTEM PRIVATE ${include_folder_list})

  TARGET_OSQUERY_LINK_WHOLE("${OSQUERY_EXTENSION_GROUP_NAME}" libosquery)

  # Apply the user (extension) settings
  get_property(library_list GLOBAL PROPERTY OSQUERY_EXTENSION_GROUP_LIBRARIES)
  if(NOT "${library_list}" STREQUAL "")
    target_link_libraries("${OSQUERY_EXTENSION_GROUP_NAME}" ${library_list})
  endif()

  get_property(include_folder_list GLOBAL PROPERTY OSQUERY_EXTENSION_GROUP_INCLUDE_FOLDERS)
  if(NOT "${include_folder_list}" STREQUAL "")
    target_include_directories("${OSQUERY_EXTENSION_GROUP_NAME}" PRIVATE
      ${include_folder_list}
    )
  endif()
endfunction()

# Helper to abstract OS/Compiler whole linking.
macro(TARGET_OSQUERY_LINK_WHOLE TARGET OSQUERY_LIB)
  if(WINDOWS)
      target_link_libraries(${TARGET} "${OS_WHOLELINK_PRE}$<TARGET_FILE_NAME:${OSQUERY_LIB}>")
      target_link_libraries(${TARGET} ${OSQUERY_LIB})
  else()
      target_link_libraries(${TARGET} "${OS_WHOLELINK_PRE}")
      target_link_libraries(${TARGET} ${OSQUERY_LIB})
      target_link_libraries(${TARGET} "${OS_WHOLELINK_POST}")
  endif()
endmacro(TARGET_OSQUERY_LINK_WHOLE)

set(GLOBAL PROPERTY AMALGAMATE_TARGETS "")
macro(GET_GENERATION_DEPS BASE_PATH)
  # Depend on the generation code.
  set(GENERATION_DEPENDENCIES "")
  file(GLOB TABLE_FILES_TEMPLATES "${BASE_PATH}/tools/codegen/templates/*.in")
  file(GLOB CODEGEN_PYTHON_FILES "${BASE_PATH}/tools/codegen/*.py")
  set(GENERATION_DEPENDENCIES
    "${BASE_PATH}/specs/blacklist"
  )
  list(APPEND GENERATION_DEPENDENCIES ${CODEGEN_PYTHON_FILES})
  list(APPEND GENERATION_DEPENDENCIES ${TABLE_FILES_TEMPLATES})
endmacro()

# Find and generate table plugins from .table syntax
macro(GENERATE_TABLES TABLES_PATH)
  # Get all matching files for all platforms.
  set(TABLES_SPECS "${TABLES_PATH}/specs")
  set(TABLE_CATEGORIES "")
  if(APPLE)
    list(APPEND TABLE_CATEGORIES "darwin" "posix" "macwin")
  elseif(FREEBSD)
    list(APPEND TABLE_CATEGORIES "freebsd" "posix")
  elseif(LINUX)
    list(APPEND TABLE_CATEGORIES "linux" "posix" "linwin")
  elseif(WINDOWS)
    list(APPEND TABLE_CATEGORIES "windows" "macwin" "linwin")
  else()
    message( FATAL_ERROR "Unknown platform detected, cannot generate tables")
  endif()

  # Features optionally disabled.
  if(NOT SKIP_LLDPD AND NOT WINDOWS)
    list(APPEND TABLE_CATEGORIES "lldpd")
  endif()
  if(NOT SKIP_YARA AND NOT WINDOWS)
    list(APPEND TABLE_CATEGORIES "yara")
  endif()
  if(NOT SKIP_TSK AND NOT WINDOWS)
    list(APPEND TABLE_CATEGORIES "sleuthkit")
  endif()

  file(GLOB TABLE_FILES "${TABLES_SPECS}/*.table")
  set(TABLE_FILES_FOREIGN "")
  file(GLOB ALL_CATEGORIES RELATIVE "${TABLES_SPECS}" "${TABLES_SPECS}/*")
  foreach(CATEGORY ${ALL_CATEGORIES})
    if(IS_DIRECTORY "${TABLES_SPECS}/${CATEGORY}" AND NOT "${CATEGORY}" STREQUAL "utility")
      file(GLOB TABLE_FILES_PLATFORM "${TABLES_SPECS}/${CATEGORY}/*.table")
      list(FIND TABLE_CATEGORIES "${CATEGORY}" INDEX)
      if(${INDEX} EQUAL -1)
        # Append inner tables to foreign
        list(APPEND TABLE_FILES_FOREIGN ${TABLE_FILES_PLATFORM})
      else()
        # Append inner tables to TABLE_FILES.
        list(APPEND TABLE_FILES ${TABLE_FILES_PLATFORM})
      endif()
    endif()
  endforeach()

  # Generate a set of targets, comprised of table spec file.
  get_property(TARGETS GLOBAL PROPERTY AMALGAMATE_TARGETS)
  set(NEW_TARGETS "")
  foreach(TABLE_FILE ${TABLE_FILES})
    list(FIND TARGETS "${TABLE_FILE}" INDEX)
    if (${INDEX} EQUAL -1)
      # Do not set duplicate targets.
      list(APPEND NEW_TARGETS "${TABLE_FILE}")
    endif()
  endforeach()
  set_property(GLOBAL PROPERTY AMALGAMATE_TARGETS "${NEW_TARGETS}")
  set_property(GLOBAL PROPERTY AMALGAMATE_FOREIGN_TARGETS "${TABLE_FILES_FOREIGN}")
endmacro()

macro(GENERATE_UTILITIES TABLES_PATH)
  file(GLOB TABLE_FILES_UTILITY "${TABLES_PATH}/specs/utility/*.table")
  set_property(GLOBAL APPEND PROPERTY AMALGAMATE_TARGETS "${TABLE_FILES_UTILITY}")
endmacro(GENERATE_UTILITIES)

macro(GENERATE_TABLE TABLE_FILE FOREIGN NAME BASE_PATH OUTPUT)
  GET_GENERATION_DEPS(${BASE_PATH})
  set(TABLE_FILE_GEN "${TABLE_FILE}")
  string(REGEX REPLACE
    ".*/specs.*/(.*)\\.table"
    "${CMAKE_BINARY_DIR}/generated/tables_${NAME}/\\1.cpp"
    TABLE_FILE_GEN
    ${TABLE_FILE_GEN}
  )

  add_custom_command(
    OUTPUT "${TABLE_FILE_GEN}"
    COMMAND "${PYTHON_EXECUTABLE}"
      "${BASE_PATH}/tools/codegen/gentable.py"
      "${FOREIGN}"
      "${TABLE_FILE}"
      "${TABLE_FILE_GEN}"
    DEPENDS ${TABLE_FILE} ${GENERATION_DEPENDENCIES}
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
  )

  list(APPEND ${OUTPUT} "${TABLE_FILE_GEN}")
endmacro(GENERATE_TABLE)

macro(AMALGAMATE BASE_PATH NAME OUTPUT)
  GET_GENERATION_DEPS(${BASE_PATH})
  if("${NAME}" STREQUAL "foreign")
    get_property(TARGETS GLOBAL PROPERTY AMALGAMATE_FOREIGN_TARGETS)
    set(FOREIGN "--foreign")
  else()
    get_property(TARGETS GLOBAL PROPERTY AMALGAMATE_TARGETS)
  endif()

  set(GENERATED_TARGETS "")

  foreach(TARGET ${TARGETS})
    GENERATE_TABLE("${TARGET}" "${FOREIGN}" "${NAME}" "${BASE_PATH}" GENERATED_TARGETS)
  endforeach()

  # Include the generated folder in make clean.
  set_directory_properties(PROPERTY
    ADDITIONAL_MAKE_CLEAN_FILES "${CMAKE_BINARY_DIR}/generated")

  # Append all of the code to a single amalgamation.
  set(AMALGAMATION_FILE_GEN "${CMAKE_BINARY_DIR}/generated/${NAME}_amalgamation.cpp")
  add_custom_command(
    OUTPUT ${AMALGAMATION_FILE_GEN}
    COMMAND "${PYTHON_EXECUTABLE}"
      "${BASE_PATH}/tools/codegen/amalgamate.py"
      "${FOREIGN}"
      "${BASE_PATH}/tools/codegen/"
      "${CMAKE_BINARY_DIR}/generated"
      "${NAME}"
    DEPENDS ${GENERATED_TARGETS} ${GENERATION_DEPENDENCIES}
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
  )

  set(${OUTPUT} ${AMALGAMATION_FILE_GEN})
  set_property(GLOBAL PROPERTY AMALGAMATE_TARGETS "")
endmacro(AMALGAMATE)

function(JOIN VALUES GLUE OUTPUT)
  string(REPLACE ";" "${GLUE}" _TMP_STR "${VALUES}")
  set(${OUTPUT} "${_TMP_STR}" PARENT_SCOPE)
endfunction(JOIN)
