// ImGui GLFW binding with Metal
// In this binding, ImTextureID is used to store a pointer to a Metal texture. Read the FAQ about ImTextureID in imgui.cpp.

// You can copy and use unmodified imgui_impl_* files in your project. See main.cpp for an example of using this.
// If you use this binding you'll need to call 4 functions: ImGui_ImplXXXX_Init(), ImGui_ImplXXXX_NewFrame(), ImGui::Render() and ImGui_ImplXXXX_Shutdown().
// If you are new to ImGui, see examples/README.txt and documentation at the top of imgui.cpp.
// https://github.com/ocornut/imgui

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <imgui.h>
#include "imgui_impl_mtl.h"

// GLFW
#include <GLFW/glfw3.h>
#ifdef TARGET_OS_MAC
#define GLFW_EXPOSE_NATIVE_COCOA
#define GLFW_EXPOSE_NATIVE_NSGL // Don't really need this, but GLFW won't let us not specify it
#include <GLFW/glfw3native.h>
#endif

// Data
static GLFWwindow*  g_Window = NULL;
static double       g_Time = 0.0f;
static bool         g_MousePressed[3] = { false, false, false };
static float        g_MouseWheel = 0.0f;

static CAMetalLayer *g_MtlLayer;
static id<MTLDevice> g_MtlDevice;
static id<MTLCommandQueue> g_MtlCommandQueue;
static id<MTLRenderPipelineState> g_MtlRenderPipelineState;
static id<MTLTexture> g_MtlFontTexture;
static id<MTLSamplerState> g_MtlLinearSampler;
static NSMutableArray<id<MTLBuffer>> *g_MtlBufferPool;
static id<CAMetalDrawable> g_MtlCurrentDrawable;

static id<MTLBuffer> ImGui_ImplMtl_DequeueReusableBuffer(NSUInteger size) {
    for (int i = 0; i < [g_MtlBufferPool count]; ++i) {
        id<MTLBuffer> candidate = g_MtlBufferPool[i];
        if ([candidate length] >= size) {
            [g_MtlBufferPool removeObjectAtIndex:i];
            return candidate;
        }
    }

    return [g_MtlDevice newBufferWithLength:size options:MTLResourceCPUCacheModeDefaultCache];
}

static void ImGui_ImplMtl_EnqueueReusableBuffer(id<MTLBuffer> buffer) {
    [g_MtlBufferPool insertObject:buffer atIndex:0];
}


// This is the main rendering function that you have to implement and provide to ImGui (via setting up 'RenderDrawListsFn' in the ImGuiIO structure)
// If text or lines are blurry when integrating ImGui in your engine:
// - in your Render function, try translating your projection matrix by (0.5f,0.5f) or (0.375f,0.375f)
void ImGui_ImplMtl_RenderDrawLists(ImDrawData* draw_data)
{
    // Avoid rendering when minimized, scale coordinates for retina displays (screen coordinates != framebuffer coordinates)
    ImGuiIO& io = ImGui::GetIO();
    int fb_width = (int)(io.DisplaySize.x * io.DisplayFramebufferScale.x);
    int fb_height = (int)(io.DisplaySize.y * io.DisplayFramebufferScale.y);
    if (fb_width == 0 || fb_height == 0)
        return;
    draw_data->ScaleClipRects(io.DisplayFramebufferScale);

    id<MTLCommandBuffer> commandBuffer = [g_MtlCommandQueue commandBuffer];

    MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0].texture = [(id<CAMetalDrawable>)g_MtlCurrentDrawable texture];
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);

    id<MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

    [commandEncoder setRenderPipelineState:g_MtlRenderPipelineState];

    MTLViewport viewport = {
        .originX = 0, .originY = 0, .width = (double)fb_width, .height = (double)fb_height, .znear = 0, .zfar = 1
    };
    [commandEncoder setViewport:viewport];

    float left = 0, right = io.DisplaySize.x, top = 0, bottom = io.DisplaySize.y;
    float near = 0;
    float far = 1;
    float sx = 2 / (right - left);
    float sy = 2 / (top - bottom);
    float sz = 1 / (far - near);
    float tx = (right + left) / (left - right);
    float ty = (top + bottom) / (bottom - top);
    float tz = near / (far - near);
    float orthoMatrix[] = {
        sx,  0,  0, 0,
         0, sy,  0, 0,
         0,  0, sz, 0,
        tx, ty, tz, 1
    };

    [commandEncoder setVertexBytes:orthoMatrix length:sizeof(float) * 16 atIndex:1];

    // Render command lists
    for (int n = 0; n < draw_data->CmdListsCount; n++)
    {
        const ImDrawList* cmd_list = draw_data->CmdLists[n];
        const unsigned char* vtx_buffer = (const unsigned char*)&cmd_list->VtxBuffer.front();
        const ImDrawIdx* idx_buffer = &cmd_list->IdxBuffer.front();

        NSUInteger vertexBufferSize = sizeof(ImDrawVert) * cmd_list->VtxBuffer.size();
        id<MTLBuffer> vertexBuffer = ImGui_ImplMtl_DequeueReusableBuffer(vertexBufferSize);
        memcpy([vertexBuffer contents], vtx_buffer, vertexBufferSize);

        NSUInteger indexBufferSize = sizeof(ImDrawIdx) * cmd_list->IdxBuffer.size();
        id<MTLBuffer> indexBuffer = ImGui_ImplMtl_DequeueReusableBuffer(indexBufferSize);
        memcpy([indexBuffer contents], idx_buffer, indexBufferSize);

        [commandEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];

        int idx_buffer_offset = 0;
        for (int cmd_i = 0; cmd_i < cmd_list->CmdBuffer.size(); cmd_i++)
        {
            const ImDrawCmd* pcmd = &cmd_list->CmdBuffer[cmd_i];
            if (pcmd->UserCallback)
            {
                pcmd->UserCallback(cmd_list, pcmd);
            }
            else
            {
                MTLScissorRect scissorRect = {
                    .x = (NSUInteger)pcmd->ClipRect.x,
                    .y = (NSUInteger)(pcmd->ClipRect.y),
                    .width = (NSUInteger)(pcmd->ClipRect.z - pcmd->ClipRect.x),
                    .height = (NSUInteger)(pcmd->ClipRect.w - pcmd->ClipRect.y)
                };

                if (scissorRect.x + scissorRect.width <= fb_width && scissorRect.y + scissorRect.height <= fb_height)
                {
                    [commandEncoder setScissorRect:scissorRect];
                }

                [commandEncoder setFragmentTexture:(__bridge id<MTLTexture>)pcmd->TextureId atIndex:0];

                [commandEncoder setFragmentSamplerState:g_MtlLinearSampler atIndex:0];

                glBindTexture(GL_TEXTURE_2D, (GLuint)(intptr_t)pcmd->TextureId);

                [commandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                           indexCount:(GLsizei)pcmd->ElemCount
                                            indexType:sizeof(ImDrawIdx) == 2 ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32
                                          indexBuffer:indexBuffer
                                    indexBufferOffset:sizeof(ImDrawIdx) * idx_buffer_offset];
            }

            idx_buffer_offset += pcmd->ElemCount;
        }

        dispatch_queue_t queue = dispatch_get_current_queue();
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> commandBuffer) {
            dispatch_async(queue, ^{
                ImGui_ImplMtl_EnqueueReusableBuffer(vertexBuffer);
                ImGui_ImplMtl_EnqueueReusableBuffer(indexBuffer);
            });
        }];
    }

    [commandEncoder endEncoding];

    [commandBuffer commit];
}

static const char* ImGui_ImplMtl_GetClipboardText()
{
    return glfwGetClipboardString(g_Window);
}

static void ImGui_ImplMtl_SetClipboardText(const char* text)
{
    glfwSetClipboardString(g_Window, text);
}

void ImGui_ImplMtl_MouseButtonCallback(GLFWwindow*, int button, int action, int /*mods*/)
{
    if (action == GLFW_PRESS && button >= 0 && button < 3)
        g_MousePressed[button] = true;
}

void ImGui_ImplMtl_ScrollCallback(GLFWwindow*, double /*xoffset*/, double yoffset)
{
    g_MouseWheel += (float)yoffset; // Use fractional mouse wheel, 1.0 unit 5 lines.
}

void ImGui_ImplMtl_KeyCallback(GLFWwindow*, int key, int, int action, int mods)
{
    ImGuiIO& io = ImGui::GetIO();
    if (action == GLFW_PRESS)
        io.KeysDown[key] = true;
    if (action == GLFW_RELEASE)
        io.KeysDown[key] = false;

    (void)mods; // Modifiers are not reliable across systems
    io.KeyCtrl = io.KeysDown[GLFW_KEY_LEFT_CONTROL] || io.KeysDown[GLFW_KEY_RIGHT_CONTROL];
    io.KeyShift = io.KeysDown[GLFW_KEY_LEFT_SHIFT] || io.KeysDown[GLFW_KEY_RIGHT_SHIFT];
    io.KeyAlt = io.KeysDown[GLFW_KEY_LEFT_ALT] || io.KeysDown[GLFW_KEY_RIGHT_ALT];
    io.KeySuper = io.KeysDown[GLFW_KEY_LEFT_SUPER] || io.KeysDown[GLFW_KEY_RIGHT_SUPER];
}

void ImGui_ImplMtl_CharCallback(GLFWwindow*, unsigned int c)
{
    ImGuiIO& io = ImGui::GetIO();
    if (c > 0 && c < 0x10000)
        io.AddInputCharacter((unsigned short)c);
}

bool ImGui_ImplMtl_CreateDeviceObjects()
{
    // Build texture atlas
    ImGuiIO& io = ImGui::GetIO();
    unsigned char* pixels;
    int width, height;
    io.Fonts->GetTexDataAsAlpha8(&pixels, &width, &height);

    g_MtlDevice = MTLCreateSystemDefaultDevice();

    if (!g_MtlDevice) {
        NSLog(@"Metal is not supported");
        return false;
    }

    [g_MtlLayer setDevice:g_MtlDevice];

    g_MtlCommandQueue = [g_MtlDevice newCommandQueue];

    MTLTextureDescriptor *fontTextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                                                                                     width:width
                                                                                                    height:height
                                                                                                 mipmapped:NO];
    g_MtlFontTexture = [g_MtlDevice newTextureWithDescriptor:fontTextureDescriptor];
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [g_MtlFontTexture replaceRegion:region mipmapLevel:0 withBytes:pixels bytesPerRow:width * sizeof(uint8_t)];

    // Store our identifier
    io.Fonts->TexID = (void *)(intptr_t)g_MtlFontTexture;

    MTLSamplerDescriptor *samplerDescriptor = [[MTLSamplerDescriptor alloc] init];
    samplerDescriptor.minFilter = MTLSamplerMinMagFilterNearest;
    samplerDescriptor.magFilter = MTLSamplerMinMagFilterNearest;
    samplerDescriptor.sAddressMode = MTLSamplerAddressModeRepeat;
    samplerDescriptor.tAddressMode = MTLSamplerAddressModeRepeat;

    g_MtlLinearSampler = [g_MtlDevice newSamplerStateWithDescriptor:samplerDescriptor];

    NSString *shaders = @"#include <metal_stdlib>\n\
    using namespace metal;                                                                  \n\
                                                                                            \n\
    struct vertex_t {                                                                       \n\
        float2 position [[attribute(0)]];                                                   \n\
        float2 tex_coords [[attribute(1)]];                                                 \n\
        uchar4 color [[attribute(2)]];                                                      \n\
    };                                                                                      \n\
                                                                                            \n\
    struct frag_data_t {                                                                    \n\
        float4 position [[position]];                                                       \n\
        float4 color;                                                                       \n\
        float2 tex_coords;                                                                  \n\
    };                                                                                      \n\
                                                                                            \n\
    vertex frag_data_t vertex_function(vertex_t vertex_in [[stage_in]],                     \n\
                                       constant float4x4 &proj_matrix [[buffer(1)]])        \n\
    {                                                                                       \n\
        float2 position = vertex_in.position;                                               \n\
                                                                                            \n\
        frag_data_t out;                                                                    \n\
        out.position = proj_matrix * float4(position.xy, 0, 1);                             \n\
        out.color = float4(vertex_in.color) * (1 / 255.0);                                  \n\
        out.tex_coords = vertex_in.tex_coords;                                              \n\
        return out;                                                                         \n\
    }                                                                                       \n\
                                                                                            \n\
    fragment float4 fragment_function(frag_data_t frag_in [[stage_in]],                     \n\
                                      texture2d<float, access::sample> tex [[texture(0)]],  \n\
                                      sampler tex_sampler [[sampler(0)]])                   \n\
    {                                                                                       \n\
        return frag_in.color * float4(tex.sample(tex_sampler, frag_in.tex_coords).r);       \n\
    }";

    NSError *error = nil;
    id<MTLLibrary> library = [g_MtlDevice newLibraryWithSource:shaders options:nil error:&error];
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_function"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_function"];

    if (!library || !vertexFunction || !fragmentFunction) {
        NSLog(@"Could not create library from shader source and retrieve functions");
        return false;
    }

#define OFFSETOF(TYPE, ELEMENT) ((size_t)&(((TYPE *)0)->ELEMENT))
    MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
    vertexDescriptor.attributes[0].offset = OFFSETOF(ImDrawVert, pos);
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[0].bufferIndex = 0;
    vertexDescriptor.attributes[1].offset = OFFSETOF(ImDrawVert, uv);
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[1].bufferIndex = 0;
    vertexDescriptor.attributes[2].offset = OFFSETOF(ImDrawVert, col);
    vertexDescriptor.attributes[2].format = MTLVertexFormatUChar4;
    vertexDescriptor.attributes[2].bufferIndex = 0;
    vertexDescriptor.layouts[0].stride = sizeof(ImDrawVert);
    vertexDescriptor.layouts[0].stepRate = 1;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
#undef OFFSETOF

    MTLRenderPipelineDescriptor *renderPipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    renderPipelineDescriptor.vertexFunction = vertexFunction;
    renderPipelineDescriptor.fragmentFunction = fragmentFunction;
    renderPipelineDescriptor.vertexDescriptor = vertexDescriptor;
    renderPipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    renderPipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    renderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    renderPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    renderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    renderPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    g_MtlRenderPipelineState = [g_MtlDevice newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error:&error];

    if (!g_MtlRenderPipelineState) {
        NSLog(@"Error when creating pipeline state: %@", error);
        return false;
    }

    g_MtlBufferPool = [NSMutableArray array];

    return true;
}

void    ImGui_ImplMtl_InvalidateDeviceObjects()
{
    ImGui::GetIO().Fonts->TexID = 0;

    g_MtlFontTexture = nil;
    g_MtlLinearSampler = nil;
    g_MtlBufferPool = nil;
    g_MtlRenderPipelineState = nil;
    g_MtlCommandQueue = nil;
    g_MtlDevice = nil;
}

bool    ImGui_ImplMtl_Init(GLFWwindow* window, bool install_callbacks)
{
    g_Window = window;

    g_MtlLayer = [CAMetalLayer layer];
    NSWindow *nativeWindow = glfwGetCocoaWindow(g_Window);
    [[nativeWindow contentView] setLayer:g_MtlLayer];
    [[nativeWindow contentView] setWantsLayer:YES];

    ImGuiIO& io = ImGui::GetIO();
    io.KeyMap[ImGuiKey_Tab] = GLFW_KEY_TAB;                     // Keyboard mapping. ImGui will use those indices to peek into the io.KeyDown[] array.
    io.KeyMap[ImGuiKey_LeftArrow] = GLFW_KEY_LEFT;
    io.KeyMap[ImGuiKey_RightArrow] = GLFW_KEY_RIGHT;
    io.KeyMap[ImGuiKey_UpArrow] = GLFW_KEY_UP;
    io.KeyMap[ImGuiKey_DownArrow] = GLFW_KEY_DOWN;
    io.KeyMap[ImGuiKey_PageUp] = GLFW_KEY_PAGE_UP;
    io.KeyMap[ImGuiKey_PageDown] = GLFW_KEY_PAGE_DOWN;
    io.KeyMap[ImGuiKey_Home] = GLFW_KEY_HOME;
    io.KeyMap[ImGuiKey_End] = GLFW_KEY_END;
    io.KeyMap[ImGuiKey_Delete] = GLFW_KEY_DELETE;
    io.KeyMap[ImGuiKey_Backspace] = GLFW_KEY_BACKSPACE;
    io.KeyMap[ImGuiKey_Enter] = GLFW_KEY_ENTER;
    io.KeyMap[ImGuiKey_Escape] = GLFW_KEY_ESCAPE;
    io.KeyMap[ImGuiKey_A] = GLFW_KEY_A;
    io.KeyMap[ImGuiKey_C] = GLFW_KEY_C;
    io.KeyMap[ImGuiKey_V] = GLFW_KEY_V;
    io.KeyMap[ImGuiKey_X] = GLFW_KEY_X;
    io.KeyMap[ImGuiKey_Y] = GLFW_KEY_Y;
    io.KeyMap[ImGuiKey_Z] = GLFW_KEY_Z;

    io.RenderDrawListsFn = ImGui_ImplMtl_RenderDrawLists;      // Alternatively you can set this to NULL and call ImGui::GetDrawData() after ImGui::Render() to get the same ImDrawData pointer.
    io.SetClipboardTextFn = ImGui_ImplMtl_SetClipboardText;
    io.GetClipboardTextFn = ImGui_ImplMtl_GetClipboardText;
#ifdef _WIN32
    io.ImeWindowHandle = glfwGetWin32Window(g_Window);
#endif

    if (install_callbacks)
    {
        glfwSetMouseButtonCallback(window, ImGui_ImplMtl_MouseButtonCallback);
        glfwSetScrollCallback(window, ImGui_ImplMtl_ScrollCallback);
        glfwSetKeyCallback(window, ImGui_ImplMtl_KeyCallback);
        glfwSetCharCallback(window, ImGui_ImplMtl_CharCallback);
    }

    return true;
}

void ImGui_ImplMtl_Shutdown()
{
    ImGui_ImplMtl_InvalidateDeviceObjects();
    ImGui::Shutdown();
}

void ImGui_ImplMtl_NewFrame()
{
    if (!g_MtlFontTexture)
        ImGui_ImplMtl_CreateDeviceObjects();

    ImGuiIO& io = ImGui::GetIO();

    // Setup display size (every frame to accommodate for window resizing)
    int w, h;
    int display_w, display_h;
    glfwGetWindowSize(g_Window, &w, &h);
    glfwGetFramebufferSize(g_Window, &display_w, &display_h);
    io.DisplaySize = ImVec2((float)w, (float)h);
    io.DisplayFramebufferScale = ImVec2(w > 0 ? ((float)display_w / w) : 0, h > 0 ? ((float)display_h / h) : 0);

    CGRect bounds = CGRectMake(0, 0, w, h);
    CGRect nativeBounds = CGRectMake(0, 0, display_w, display_h);
    [g_MtlLayer setFrame:bounds];
    [g_MtlLayer setContentsScale:nativeBounds.size.width / bounds.size.width];
    [g_MtlLayer setDrawableSize:nativeBounds.size];

    g_MtlCurrentDrawable = [g_MtlLayer nextDrawable];

    // Setup time step
    double current_time =  glfwGetTime();
    io.DeltaTime = g_Time > 0.0 ? (float)(current_time - g_Time) : (float)(1.0f/60.0f);
    g_Time = current_time;

    // Setup inputs
    // (we already got mouse wheel, keyboard keys & characters from glfw callbacks polled in glfwPollEvents())
    if (glfwGetWindowAttrib(g_Window, GLFW_FOCUSED))
    {
        double mouse_x, mouse_y;
        glfwGetCursorPos(g_Window, &mouse_x, &mouse_y);
        io.MousePos = ImVec2((float)mouse_x, (float)mouse_y);   // Mouse position in screen coordinates (set to -1,-1 if no mouse / on another screen, etc.)
    }
    else
    {
        io.MousePos = ImVec2(-1,-1);
    }

    for (int i = 0; i < 3; i++)
    {
        io.MouseDown[i] = g_MousePressed[i] || glfwGetMouseButton(g_Window, i) != 0;    // If a mouse press event came, always pass it as "mouse held this frame", so we don't miss click-release events that are shorter than 1 frame.
        g_MousePressed[i] = false;
    }

    io.MouseWheel = g_MouseWheel;
    g_MouseWheel = 0.0f;

    // Hide OS mouse cursor if ImGui is drawing it
    glfwSetInputMode(g_Window, GLFW_CURSOR, io.MouseDrawCursor ? GLFW_CURSOR_HIDDEN : GLFW_CURSOR_NORMAL);

    // Start the frame
    ImGui::NewFrame();
}

IMGUI_API id          ImGui_ImplMtl_CommandQueue()
{
    return g_MtlCommandQueue;
}

IMGUI_API id          ImGui_ImplMtl_CurrentDrawable()
{
    return g_MtlCurrentDrawable;
}
