// ImGui - standalone example application for Glfw + Metal
// If you are new to ImGui, see examples/README.txt and documentation at the top of imgui.cpp.

#include <imgui.h>
#include "imgui_impl_mtl.h"
#include <stdio.h>
#include <GLFW/glfw3.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

static void error_callback(int error, const char* description)
{
    fprintf(stderr, "Error %d: %s\n", error, description);
}

int main(int, char**)
{
    // Setup window
    glfwSetErrorCallback(error_callback);
    if (!glfwInit())
        return 1;
    GLFWwindow* window = glfwCreateWindow(1280, 720, "ImGui Metal example", NULL, NULL);
    glfwMakeContextCurrent(window);

    // Setup ImGui binding
    ImGui_ImplMtl_Init(window, true);

    // Load Fonts
    // (there is a default font, this is only if you want to change it. see extra_fonts/README.txt for more details)
    //ImGuiIO& io = ImGui::GetIO();
    //io.Fonts->AddFontDefault();
    //io.Fonts->AddFontFromFileTTF("../../extra_fonts/Cousine-Regular.ttf", 15.0f);
    //io.Fonts->AddFontFromFileTTF("../../extra_fonts/DroidSans.ttf", 16.0f);
    //io.Fonts->AddFontFromFileTTF("../../extra_fonts/ProggyClean.ttf", 13.0f);
    //io.Fonts->AddFontFromFileTTF("../../extra_fonts/ProggyTiny.ttf", 10.0f);
    //io.Fonts->AddFontFromFileTTF("c:\\Windows\\Fonts\\ArialUni.ttf", 18.0f, NULL, io.Fonts->GetGlyphRangesJapanese());

    bool show_test_window = true;
    bool show_another_window = false;
    ImVec4 clear_color = ImColor(114, 144, 154);

    // Main loop
    while (!glfwWindowShouldClose(window))
    {
        glfwPollEvents();
        ImGui_ImplMtl_NewFrame();

        // 1. Show a simple window
        // Tip: if we don't call ImGui::Begin()/ImGui::End() the widgets appears in a window automatically called "Debug"
        {
            static float f = 0.0f;
            ImGui::Text("Hello, world!");
            ImGui::SliderFloat("float", &f, 0.0f, 1.0f);
            ImGui::ColorEdit3("clear color", (float*)&clear_color);
            if (ImGui::Button("Test Window")) show_test_window ^= 1;
            if (ImGui::Button("Another Window")) show_another_window ^= 1;
            ImGui::Text("Application average %.3f ms/frame (%.1f FPS)", 1000.0f / ImGui::GetIO().Framerate, ImGui::GetIO().Framerate);
        }

        // 2. Show another simple window, this time using an explicit Begin/End pair
        if (show_another_window)
        {
            ImGui::SetNextWindowSize(ImVec2(200,100), ImGuiSetCond_FirstUseEver);
            ImGui::Begin("Another Window", &show_another_window);
            ImGui::Text("Hello");
            ImGui::End();
        }

        // 3. Show the ImGui test window. Most of the sample code is in ImGui::ShowTestWindow()
        if (show_test_window)
        {
            ImGui::SetNextWindowPos(ImVec2(650, 20), ImGuiSetCond_FirstUseEver);
            ImGui::ShowTestWindow(&show_test_window);
        }

        // Rendering

        id<MTLCommandQueue> commandQueue = ImGui_ImplMtl_CommandQueue();
        id<CAMetalDrawable> currentDrawable = ImGui_ImplMtl_CurrentDrawable();
        id<MTLCommandBuffer> clearBuffer = [commandQueue commandBuffer];
        MTLRenderPassDescriptor *clearPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
        clearPassDescriptor.colorAttachments[0].texture = [currentDrawable texture];
        clearPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        clearPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        clearPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(clear_color.x, clear_color.y, clear_color.z, clear_color.w);
        id<MTLRenderCommandEncoder> clearEncoder = [clearBuffer renderCommandEncoderWithDescriptor:clearPassDescriptor];
        // You could draw your scene or anything else in here; GUI is drawn in a separate pass below
        [clearEncoder endEncoding];
        [clearBuffer commit];

        ImGui::Render();

        id<MTLCommandBuffer> presentationBuffer = [commandQueue commandBuffer];
        [presentationBuffer presentDrawable:currentDrawable];
        [presentationBuffer commit];
    }

    // Cleanup
    ImGui_ImplMtl_Shutdown();
    glfwTerminate();

    return 0;
}
