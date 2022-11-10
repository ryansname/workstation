// dear imgui: standalone example application for GLFW + OpenGL 3, using programmable pipeline
// If you are new to dear imgui, see examples/README.txt and documentation at the top of imgui.cpp.
// (GLFW is a cross-platform general purpose library for handling windows, inputs, OpenGL/Vulkan graphics context creation, etc.)

const std = @import("std");
const builtin = @import("builtin");
const gui = @import("gui.zig");
const imgui = @import("imgui");
const impl_glfw = @import("imgui_impl_glfw.zig");
const impl_gl3 = @import("imgui_impl_opengl3.zig");
const glfw = @import("include/glfw.zig");
const gl = @import("include/gl.zig");

const assert = std.debug.assert;
const Workstation = @import("Workstation.zig");

const is_darwin = builtin.os.tag.isDarwin();

fn glfw_error_callback(err: c_int, description: ?[*:0]const u8) callconv(.C) void {
    const description_safe = description orelse "<null>"[0..];
    std.debug.print("Glfw Error {}: {s}\n", .{ err, description_safe });
}

pub fn main() !void {

    // Setup window
    _ = glfw.glfwSetErrorCallback(&glfw_error_callback);
    if (glfw.glfwInit() == 0)
        return error.GlfwInitFailed;

    // Decide GL+GLSL versions
    const glsl_version = if (is_darwin) "#version 150" else "#version 130";
    if (is_darwin) {
        // GL 3.2 + GLSL 150
        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 2);
        glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE); // 3.2+ only
        glfw.glfwWindowHint(glfw.GLFW_OPENGL_FORWARD_COMPAT, gl.GL_TRUE); // Required on Mac
    } else {
        // GL 3.0 + GLSL 130
        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 0);
        //glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);  // 3.2+ only
        //glfw.glfwWindowHint(glfw.GLFW_OPENGL_FORWARD_COMPAT, gl.GL_TRUE);            // 3.0+ only
    }

    // Create window with graphics context
    const window = glfw.glfwCreateWindow(1280, 720, "Dear ImGui GLFW+OpenGL3 example", null, null) orelse return error.GlfwCreateWindowFailed;
    glfw.glfwMakeContextCurrent(window);
    glfw.glfwSwapInterval(1); // Enable vsync

    // Initialize OpenGL loader
    if (gl.gladLoadGL() == 0)
        return error.GladLoadGLFailed;

    // Setup Dear ImGui context
    imgui.CHECKVERSION();
    _ = imgui.CreateContext();

    const io = imgui.GetIO();
    io.ConfigFlags.NavEnableKeyboard = true; // Enable Keyboard Controls
    //io.ConfigFlags |= imgui.ConfigFlags.NavEnableGamepad;      // Enable Gamepad Controls

    // Setup Dear ImGui style
    imgui.StyleColorsDark();
    //imgui.StyleColorsClassic();

    // Setup Platform/Renderer bindings
    _ = impl_glfw.InitForOpenGL(window, true);
    _ = impl_gl3.Init(glsl_version);

    // Load Fonts
    // - If no fonts are loaded, dear imgui will use the default font. You can also load multiple fonts and use ImGui::PushFont()/PopFont() to select them.
    // - AddFontFromFileTTF() will return the ImFont* so you can store it if you need to select the font among multiple.
    // - If the file cannot be loaded, the function will return NULL. Please handle those errors in your application (e.g. use an assertion, or display an error and quit).
    // - The fonts will be rasterized at a given size (w/ oversampling) and stored into a texture when calling ImFontAtlas::Build()/GetTexDataAsXXXX(), which ImGui_ImplXXXX_NewFrame below will call.
    // - Read 'docs/FONTS.txt' for more instructions and details.
    // - Remember that in C/C++ if you want to include a backslash \ in a string literal you need to write a double backslash \\ !

    var font_config: gui.FontConfig = undefined;
    gui.FontConfig.init_ImFontConfig(&font_config);
    defer gui.FontConfig.deinit(&font_config);
    font_config.FontDataOwnedByAtlas = false; // In static memory, so it cannot be freed

    const font_data = @embedFile("fonts/Hack-Regular.ttf");
    assert(io.Fonts.?.AddFontFromMemoryTTFExt(@intToPtr(*u8, @ptrToInt(font_data)), font_data.len, 13.0, &font_config, null) != null);
    _ = io.Fonts.?.AddFontDefault();

    //io.Fonts.AddFontFromFileTTF("../../misc/fonts/Roboto-Medium.ttf", 16.0);
    //io.Fonts.AddFontFromFileTTF("../../misc/fonts/Cousine-Regular.ttf", 15.0);
    //io.Fonts.AddFontFromFileTTF("../../misc/fonts/DroidSans.ttf", 16.0);
    //io.Fonts.AddFontFromFileTTF("../../misc/fonts/ProggyTiny.ttf", 10.0);
    //ImFont* font = io.Fonts.AddFontFromFileTTF("c:\\Windows\\Fonts\\ArialUni.ttf", 18.0, null, io.Fonts->GetGlyphRangesJapanese());
    //IM_ASSERT(font != NULL);

    // Our state
    var show_demo_window = true;
    var clear_color = imgui.Vec4{ .x = 0.45, .y = 0.55, .z = 0.60, .w = 1.00 };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer assert(!gpa.deinit());
    const allocator = gpa.allocator();

    try gui.initTmpAllocator(allocator);
    defer gui.deinitTmpAllocator(allocator);

    var app = try Workstation.init(allocator);
    defer app.deinit(allocator);

    try app.start_workers();

    // Main loop
    while (glfw.glfwWindowShouldClose(window) == 0 and !app.exit_requested) {
        // Poll and handle events (inputs, window resize, etc.)
        // You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
        // - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application.
        // - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application.
        // Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
        glfw.glfwPollEvents();

        // Start the Dear ImGui frame
        impl_gl3.NewFrame();
        impl_glfw.NewFrame();
        imgui.NewFrame();

        // 1. Show the big demo window (Most of the sample code is in imgui.ShowDemoWindow()! You can browse its code to learn more about Dear ImGui!).
        if (show_demo_window)
            imgui.ShowDemoWindowExt(&show_demo_window);

        try app.processBackgroundWork();

        try app.render(io.*);

        // Rendering
        imgui.Render();
        var display_w: c_int = 0;
        var display_h: c_int = 0;
        glfw.glfwGetFramebufferSize(window, &display_w, &display_h);
        gl.glViewport(0, 0, display_w, display_h);
        gl.glClearColor(
            clear_color.x * clear_color.w,
            clear_color.y * clear_color.w,
            clear_color.z * clear_color.w,
            clear_color.w,
        );
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);
        impl_gl3.RenderDrawData(imgui.GetDrawData());

        glfw.glfwSwapBuffers(window);
    }

    // Cleanup
    impl_gl3.Shutdown();
    impl_glfw.Shutdown();
    imgui.DestroyContext();

    glfw.glfwDestroyWindow(window);
    glfw.glfwTerminate();
}
