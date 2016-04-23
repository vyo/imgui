// ImGui GLFW binding with OpenGL
// In this binding, ImTextureID is used to store an OpenGL 'GLuint' texture identifier. Read the FAQ about ImTextureID in imgui.cpp.

// You can copy and use unmodified imgui_impl_* files in your project. See main.cpp for an example of using this.
// If you use this binding you'll need to call 4 functions: ImGui_ImplXXXX_Init(), ImGui_ImplXXXX_NewFrame(), ImGui::Render() and ImGui_ImplXXXX_Shutdown().
// If you are new to ImGui, see examples/README.txt and documentation at the top of imgui.cpp.
// https://github.com/ocornut/imgui

struct GLFWwindow;

IMGUI_API bool        ImGui_ImplMtl_Init(GLFWwindow* window, bool install_callbacks);
IMGUI_API void        ImGui_ImplMtl_Shutdown();
IMGUI_API void        ImGui_ImplMtl_NewFrame();

IMGUI_API id          ImGui_ImplMtl_CommandQueue();
IMGUI_API id          ImGui_ImplMtl_CurrentDrawable();

// Use if you want to reset your rendering device without losing ImGui state.
IMGUI_API void        ImGui_ImplMtl_InvalidateDeviceObjects();
IMGUI_API bool        ImGui_ImplMtl_CreateDeviceObjects();

// GLFW callbacks (installed by default if you enable 'install_callbacks' during initialization)
// Provided here if you want to chain callbacks.
// You can also handle inputs yourself and use those as a reference.
IMGUI_API void        ImGui_ImplMtl_MouseButtonCallback(GLFWwindow* window, int button, int action, int mods);
IMGUI_API void        ImGui_ImplMtl_ScrollCallback(GLFWwindow* window, double xoffset, double yoffset);
IMGUI_API void        ImGui_ImplMtl_KeyCallback(GLFWwindow* window, int key, int scancode, int action, int mods);
IMGUI_API void        ImGui_ImplMtl_CharCallback(GLFWwindow* window, unsigned int c);
