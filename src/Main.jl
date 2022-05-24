using CImGui

using CImGui.GLFWBackend
using CImGui.OpenGLBackend
using CImGui.GLFWBackend.GLFW
using CImGui.OpenGLBackend.ModernGL

using CImGui.CSyntax
using CImGui.CSyntax.CStatic

include("Client.jl")
include("View.jl")

#running = true

# Status Text for connection Window
connectStatus = ""

function mainLoop(window::GLFW.Window, ctx)
    glClear() = ccall(@eval(GLFW.GetProcAddress("glClear")), Cvoid, (Cuint,), 0x00004000)
    
    try
        while !GLFW.WindowShouldClose(window)
            ImGui_ImplOpenGL3_NewFrame()
            ImGui_ImplGlfw_NewFrame()            
            CImGui.NewFrame()

            # Helper Window
            begin
                CImGui.Begin("Help")
                CImGui.ShowUserGuide()
                CImGui.End()
            end

            # Connection Window            
            @cstatic portData = ""*"\0"^115 i0=Cint(123) @cstatic ipData = ""*"\0"^115 i0=Cint(123) begin
                # Create a window
                CImGui.Begin("Connect to Jetson")

                CImGui.Text("Please Enter the IP Adress and Port for the Jetson")
               
                CImGui.Text("Enter IP:")
                CImGui.SameLine()
                CImGui.InputText("", ipData, length(ipData), CImGui.ImGuiInputTextFlags_EnterReturnsTrue) && inputTextCallback()                   
                CImGui.Text("Enter Port:")
                CImGui.SameLine()
                CImGui.InputText(" ", portData, length(portData), CImGui.ImGuiInputTextFlags_EnterReturnsTrue) && inputTextCallback()                             
                CImGui.Button("Connect") && buttonPress(ipData, portData)
                CImGui.Text(connectStatus)

                CImGui.End()
            end            

            CImGui.Render()
            glClear()
            ImGui_ImplOpenGL3_RenderDrawData(CImGui.GetDrawData())

            GLFW.SwapBuffers(window)
            GLFW.WaitEvents()
        end
    finally
        CImGui.DestroyContext(ctx)
        GLFW.DestroyWindow(window)
    end
end

function buttonPress(ipData::String, portData::String)
    ip = ""
    port = ""

    for char in ipData
        if char === '.' || isdigit(char)
            ip = ip * char
        end
    end

    for char in portData
        if isdigit(char)
            port = port * char
        end
    end

    global connectStatus = "Trying to connect to: " * ip * " on " * port
    global connectStatus = checkConnction(ip, port)
end

function inputTextCallback()
    println("Im here")
end

"""
This is the starting point of the program.
"""
function main()
    # Create window and start main loop
    window, ctx = setUpWindow((600, 400), "AT-RP Controller")
    mainLoop(window, ctx)
end

main()