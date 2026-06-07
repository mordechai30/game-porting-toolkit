#-------------------------------------------------------------------------------------------------------------------------------------------------------------
#
# Copyright 2025 Apple Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#-------------------------------------------------------------------------------------------------------------------------------------------------------------

cmake_minimum_required(VERSION 3.28)
project(gptksample)

set(SOURCES "01 - AppLifecycle/macOS/main.m"
            "01 - AppLifecycle/macOS/GameApplication.m"
            "01 - AppLifecycle/GameCoordinatorController.mm"
            "02 - GameInput/Controller.mm"
            "03 - Audio/PhaseAudio.mm"
            "04 - Physics/GameCollisions.cpp"
            "05 - Haptics/Haptics.m"
            "07 - ShaderLoading/ShaderPipelineBuilder.cpp"
            "08 - MetalRendering/BumpAllocator.cpp"
            "08 - MetalRendering/GameRendering.cpp"
            "10 - GameExample/Game.cpp"
            "10 - GameExample/GameCoordinator.cpp"
            "10 - GameExample/MathUtils.cpp"
            "10 - GameExample/MeshUtils.cpp"
            "10 - GameExample/TextureLoader.mm"
            "10 - GameExample/UI.cpp"
            "11 - CloudSaves/CloudSaveManager.m")

set(INCLUDES "01 - AppLifecycle"
             "02 - GameInput"
             "03 - Audio"
             "04 - Physics"
             "05 - Haptics"
             "07 - ShaderLoading"
             "08 - MetalRendering"
             "10 - GameExample"
             "11 - CloudSaves"
             "include/metal-cpp"
             "include")

set(LIBRARIES "-framework Foundation"
              "-framework Metal"
              "-framework QuartzCore"
              "-framework AppKit"
              "-framework MetalKit"
              "-framework MetalFX"
              "-framework GameController"
              "-framework Phase"
              "-framework CoreHaptics"
              "-framework AVFAudio"
              "-framework CloudKit")

set(DXC_PATH /usr/local/bin/dxc-3.7)
set(DXC_FLAGS -Zi -Qembed_debug)

set(MSC_PATH /usr/local/bin/metal-shaderconverter)
set(MSC_FLAGS --deployment-os=macOS --minimum-os-build-version=14)

set(CACHE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/Cache)
set(RESOURCES_DIR ${CMAKE_CURRENT_BINARY_DIR}/gptksample.app/Contents/Resources)

# Section: build shaders

set(SHADER_ASSETS ${RESOURCES_DIR}/present_vs.metallib
                  ${RESOURCES_DIR}/present_fs.metallib
                  ${RESOURCES_DIR}/sprite_instanced_vs.metallib
                  ${RESOURCES_DIR}/sprite_instanced_fs.metallib)

add_custom_command(OUTPUT ${RESOURCES_DIR}
                  COMMAND ${CMAKE_COMMAND} -E make_directory ${RESOURCES_DIR})

add_custom_command(OUTPUT present_vs.dxil
                   COMMAND ${DXC_PATH} "${CMAKE_SOURCE_DIR}/06 - ShaderConversion/present.hlsl" ${DXC_FLAGS} -T vs_6_0 -E MainVS -Fo ${CACHE_DIR}/present_vs.dxil
                   DEPENDS "${CMAKE_SOURCE_DIR}/06 - ShaderConversion/present.hlsl")

add_custom_command(OUTPUT present_fs.dxil
                   COMMAND ${DXC_PATH} "${CMAKE_SOURCE_DIR}/06 - ShaderConversion/present.hlsl" ${DXC_FLAGS} -T ps_6_0 -E MainFS -Fo ${CACHE_DIR}/present_fs.dxil
                   DEPENDS "${CMAKE_SOURCE_DIR}/06 - ShaderConversion/present.hlsl")

add_custom_command(OUTPUT sprite_instanced_vs.dxil
                   COMMAND ${DXC_PATH} "${CMAKE_SOURCE_DIR}/06 - ShaderConversion/sprite_instanced.hlsl" ${DXC_FLAGS} -T vs_6_0 -E MainVS -Fo ${CACHE_DIR}/sprite_instanced_vs.dxil
                   DEPENDS "${CMAKE_SOURCE_DIR}/06 - ShaderConversion/sprite_instanced.hlsl")

add_custom_command(OUTPUT sprite_instanced_fs.dxil
                   COMMAND ${DXC_PATH} "${CMAKE_SOURCE_DIR}/06 - ShaderConversion/sprite_instanced.hlsl" ${DXC_FLAGS} -T ps_6_0 -E MainFS -Fo ${CACHE_DIR}/sprite_instanced_fs.dxil
                   DEPENDS "${CMAKE_SOURCE_DIR}/06 - ShaderConversion/sprite_instanced.hlsl")

add_custom_command(OUTPUT ${RESOURCES_DIR}/present_vs.metallib
                   COMMAND ${MSC_PATH} ${CACHE_DIR}/present_vs.dxil ${MSC_FLAGS} -o ${RESOURCES_DIR}/present_vs.metallib
                   DEPENDS ${CACHE_DIR}/present_vs.dxil
                   COMMENT "Building present_vs.metallib")

add_custom_command(OUTPUT ${RESOURCES_DIR}/present_fs.metallib
                   COMMAND ${MSC_PATH} ${CACHE_DIR}/present_fs.dxil ${MSC_FLAGS} -o ${RESOURCES_DIR}/present_fs.metallib
                   DEPENDS ${CACHE_DIR}/present_fs.dxil
                   COMMENT "Building present_fs.metallib")

add_custom_command(OUTPUT ${RESOURCES_DIR}/sprite_instanced_vs.metallib
                   COMMAND ${MSC_PATH} ${CACHE_DIR}/sprite_instanced_vs.dxil ${MSC_FLAGS} -o ${RESOURCES_DIR}/sprite_instanced_vs.metallib
                   DEPENDS ${CACHE_DIR}/sprite_instanced_vs.dxil
                   COMMENT "Building sprite_instanced_vs.metallib")
                   
add_custom_command(OUTPUT ${RESOURCES_DIR}/sprite_instanced_fs.metallib
                   COMMAND ${MSC_PATH} ${CACHE_DIR}/sprite_instanced_fs.dxil ${MSC_FLAGS} -o ${RESOURCES_DIR}/sprite_instanced_fs.metallib
                   DEPENDS ${CACHE_DIR}/sprite_instanced_fs.dxil
                   COMMENT "Building sprite_instanced_fs.metallib")

# Section: copy textures and sounds

set(OTHER_ASSETS
    ${CMAKE_CURRENT_SOURCE_DIR}/PrecompiledAssets/Icon.png
    ${CMAKE_CURRENT_SOURCE_DIR}/PrecompiledAssets/background.png
    ${CMAKE_CURRENT_SOURCE_DIR}/PrecompiledAssets/bullet0.png
    ${CMAKE_CURRENT_SOURCE_DIR}/PrecompiledAssets/enemy0.png
    ${CMAKE_CURRENT_SOURCE_DIR}/PrecompiledAssets/enemy1.png
    ${CMAKE_CURRENT_SOURCE_DIR}/PrecompiledAssets/enemy2.png
    ${CMAKE_CURRENT_SOURCE_DIR}/PrecompiledAssets/explosion0.png
    ${CMAKE_CURRENT_SOURCE_DIR}/PrecompiledAssets/explosion1.png
    ${CMAKE_CURRENT_SOURCE_DIR}/PrecompiledAssets/failure.mp3
    ${CMAKE_CURRENT_SOURCE_DIR}/PrecompiledAssets/impact2.mp3
    ${CMAKE_CURRENT_SOURCE_DIR}/PrecompiledAssets/laser2.mp3
    ${CMAKE_CURRENT_SOURCE_DIR}/PrecompiledAssets/player.png
    ${CMAKE_CURRENT_SOURCE_DIR}/PrecompiledAssets/success.mp3
)

# Section: macOS app

add_executable(gptksample MACOSX_BUNDLE ${SOURCES} ${RESOURCES_DIR} ${SHADER_ASSETS} ${OTHER_ASSETS})
target_compile_features(gptksample PRIVATE cxx_std_20)
target_compile_options(gptksample PRIVATE "-fobjc-arc")
target_include_directories(gptksample PRIVATE ${INCLUDES})
target_link_libraries(gptksample PRIVATE ${LIBRARIES})
foreach(ASSET ${OTHER_ASSETS})
    set_property(SOURCE ${ASSET} PROPERTY MACOSX_PACKAGE_LOCATION Resources)
endforeach()
