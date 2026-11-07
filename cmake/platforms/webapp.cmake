# Build JS versions of the puzzles for the web platform.
# This is adapted from:
# - emscripten.cmake, removing the KaiOS-specific parts
# - the portion of windows.cmake that generates gamedesc.txt

enable_language(CXX)

# (Can't include webapp.cpp in platform_common_sources -- see note below.)
set(platform_common_sources)
set(platform_gui_libs)
set(platform_libs embind)
set(CMAKE_EXECUTABLE_SUFFIX ".js")

find_program(HALIBUT halibut)
if(NOT HALIBUT)
    message(WARNING "HTML documentation cannot be built (did not find halibut)")
endif()
set(HALIBUT_OPTIONS
        "-Chtml-template-fragment:%k"
        "-Chtml-chapter-shownumber:false"
        "-Chtml-section-shownumber:0:false"
)

find_program(JQ jq)
find_program(PYTHON3 python3)
if(NOT JQ)
    message(WARNING "dependencies.json cannot be built (did not find jq)")
endif()
if(NOT PYTHON3)
    message(WARNING "dependencies.json cannot be built (did not find python3)")
endif()

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_compile_options(
    # Add debug info for source maps and license extraction.
    # [As of emsdk 4.0.15, -g3 does not disable optimizations.]
    -g
)

set(build_cli_programs FALSE)
set(build_gui_programs FALSE)

function(get_platform_puzzle_extra_source_files OUTVAR NAME AUXILIARY)
    # webapp.cpp is here, rather than platform_common_sources,
    # because the common sources end up in libcore, and EMSCRIPTEN_BINDINGS
    # are lost from libraries without a bunch of extra work.
    set(${OUTVAR} "${CMAKE_SOURCE_DIR}/webapp.cpp" PARENT_SCOPE)
endfunction()

function(set_platform_gui_target_properties TARGET)
endfunction()

function(set_platform_puzzle_target_properties NAME TARGET)
    target_compile_definitions(${TARGET} PRIVATE
        $<$<COMPILE_LANGUAGE:C>:NARROW_BORDERS>
    )
    target_link_options(${TARGET} PRIVATE
        # Generate TypeScript .d.ts files for emcc exports
        --emit-tsd "${NAME}.d.ts"
        # Have llvm include build-id that Sentry can use as debug id
        "LINKER:--build-id"
        # Prevent wasmImports name minification, to allow reusing a single emcc runtime
        # wrapper for all <puzzle>.wasm. (It's ok that exports.js doesn't exist.
        # See https://github.com/emscripten-core/emscripten/issues/16695)
        -lexports.js
        # Don't fail malloc if possible (allows larger puzzle sizes)
        -sALLOW_MEMORY_GROWTH=1
        # Disable anything that would require CSP script-src 'unsafe-eval'
        -sDYNAMIC_EXECUTION=0
        # Limit environments to reduce wrapper code size
        -sENVIRONMENT=web,worker
        # Make the wrapper an es6 module (rather than UMD)
        -sEXPORT_ES6=1
        # Export an init function from the wrapper (rather than loading <puzzle>.wasm 
        # immediately at import, to allow sharing single wrapper between puzzles)
        -sMODULARIZE=1
        # Generate DWARF source maps. [Currently debug builds only. We'd like to
        # also enable this for release, to improve Chrome debugging and Sentry stack
        # traces, but that currently disables important Binaryen optimizations.
        # See https://github.com/emscripten-core/emscripten/issues/25239.]
        $<$<CONFIG:Debug>:-gseparate-dwarf>
        # Build source maps for extracting dependency licenses
        -gsource-map
    )
endfunction()

function(build_platform_extras)
    if(HALIBUT)
        set(help_dir ${CMAKE_CURRENT_BINARY_DIR}/help)
        add_custom_command(OUTPUT ${help_dir}/en
                COMMAND ${CMAKE_COMMAND} -E make_directory ${help_dir}/en)
        add_custom_command(OUTPUT ${help_dir}/en/index.html
                COMMAND ${HALIBUT} --html ${HALIBUT_OPTIONS}
                ${CMAKE_CURRENT_SOURCE_DIR}/puzzles.but
                DEPENDS
                ${help_dir}/en
                ${CMAKE_CURRENT_SOURCE_DIR}/puzzles.but
                WORKING_DIRECTORY ${help_dir}/en)
        add_custom_target(doc ALL
                DEPENDS ${help_dir}/en/index.html)
    endif()

    # Generate catalog.json
    list(SORT puzzle_names)
    set(puzzles_map "{}")
    set(puzzle_ids_arr "[]")
    foreach(name ${puzzle_names})
        # Build puzzles[name]: {name: displayname, description, objective, unfinished?}
        string(JSON obj SET "{}" "name" "\"${displayname_${name}}\"")
        string(JSON obj SET "${obj}" "description" "\"${description_${name}}\"")
        string(JSON obj SET "${obj}" "objective" "\"${objective_${name}}\"")
        string(JSON obj SET "${obj}" "collection" "\"${collection_${name}}\"")
        list(FIND PUZZLES_ENABLE_UNFINISHED ${name} unfinished_pos)
        # (Also treat puzzles-unreleased's "abandoned" Crossing and Seismic as unfinished.)
        if (unfinished_pos GREATER -1 OR name STREQUAL "crossing" OR name STREQUAL "seismic")
            string(JSON obj SET "${obj}" "unfinished" "true")
        endif()
        string(JSON puzzles_map SET "${puzzles_map}" "${name}" "${obj}")

        # Build puzzleIds[]
        # string(JSON ... APPEND) is available in CMake 3.28+; for compatibility:
        string(JSON puzzle_ids_arr SET "${puzzle_ids_arr}" 1000000 "\"${name}\"")
    endforeach()

    file(READ ${CMAKE_CURRENT_SOURCE_DIR}/upstream-id.json puzzles_upstream_id)
    file(READ ${CMAKE_CURRENT_SOURCE_DIR}/unreleased/upstream-id.json unreleased_upstream_id)
    string(JSON versions SET "{}" "puzzles" "${puzzles_upstream_id}")
    string(JSON versions SET "${versions}" "puzzles-unreleased" "${unreleased_upstream_id}")

    string(JSON catalog_json SET "{}" "versions" "${versions}")
    string(JSON catalog_json SET "${catalog_json}" "puzzles" "${puzzles_map}")
    string(JSON catalog_json SET "${catalog_json}" "puzzleIds" "${puzzle_ids_arr}")
    file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/catalog.json "${catalog_json}")

    # Generate dependencies.json from wasm source maps
    if(JQ AND PYTHON3)
        set(puzzle_map_files)
        foreach(name ${puzzle_names})
            list(APPEND puzzle_map_files "$<TARGET_FILE_DIR:${name}>/${name}.wasm.map")
        endforeach()

        add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/dependencies.json
                COMMENT "Generating dependencies.json from source maps"
                COMMAND ${JQ} -r .sources[] ${puzzle_map_files}
                | sed -E -e "s=^(\\.\\./)+=/="
                         -e "s=^/emsdk/(emscripten|lib)=/emsdk/upstream/\\1="
                | grep -v "/puzzles"
                | sort -u
                | ${PYTHON3} ${CMAKE_CURRENT_SOURCE_DIR}/emcc-dependency-info.py
                    --sources -
                    --output ${CMAKE_CURRENT_BINARY_DIR}/dependencies.json
                DEPENDS
                ${puzzle_names}
                ${CMAKE_CURRENT_SOURCE_DIR}/emcc-dependency-info.py
                VERBATIM)
        add_custom_target(dependencies ALL
                DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/dependencies.json)
    endif()
endfunction()
