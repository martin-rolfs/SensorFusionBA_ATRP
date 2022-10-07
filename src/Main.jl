using CImGui

using CImGui.GLFWBackend
using CImGui.OpenGLBackend
using CImGui.GLFWBackend.GLFW
using CImGui.OpenGLBackend.ModernGL

using CImGui.CSyntax
using CImGui.CSyntax.CStatic

using StructArrays
using LinearAlgebra

include("Structs.jl")

# Change this value to adjust font scale uniformly
globalFontScale = 1.0

# How many positional data points to save
const rawDataLength = 100
rawSaveDataLength = 1

# Booleans for the open windows
showHelperWindow = false
showConnectWindow = false
showDataPlots = false
renderRobot = false
recordDataWindow = false
showRecoredDataPlots = false
showLoadDataWindow = false
showAutomaticInputWindow = false
useAutomaticInput = false
automaticInputTimer = 0.0

isLeftMouseButtonDown = false
isRightMouseButtonDown = false
oldMousePosition = [0.0, 0.0]
windowSize = (1600, 900)

include("Camera.jl")
# Camera to render
cam = Camera()
cam.position = GLfloat[-4.0, -4.0, 3.0]

connectedTextDisplay = "Robot data\nSpeed:\nMax Speed:\nSteering Angle:"

include("Model.jl")
include("View.jl")

# Raw Data
rawPositionalData = StructArray(PositionalData[])
# Raw Data to save
rawSavePosData = StructArray(PositionalData[])

# initialize standard settings
settings = PredictionSettings(false, false, false, 5, false, 5, false, 1.0, 0.33, 0.66, 0, 0, 0, 0, 0, 0.1, 0.1, 1/3, false, 1.0, 1.0)

models = Vector{Model}(undef, 0)

function mainLoop(window::GLFW.Window, ctx, program)     
    saveDataLength = 0

    try
        while !GLFW.WindowShouldClose(window)
            updateFPS(window)
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
            ImGui_ImplOpenGL3_NewFrame()
            ImGui_ImplGlfw_NewFrame()            
            CImGui.NewFrame()

            if renderRobot
                # Before calculatin camera matrices check Inputs
                checkCameraMovement([CImGui.GetMousePos().x - windowSize[1] / 2, CImGui.GetMousePos().y - windowSize[2] / 2], cam)
                if connected
                    # if connected orientate robot according to camera orientation in x and z axis
                    positionalData = rawPositionalData[length(rawPositionalData)]
                    angles = convertQuaternionToEuler(positionalData.cameraOri) 
                    models[1].transform.eulerRotation = [angles[1], -π/8, π + angles[3]]

                    # Get the meshes of the robot model
                    leftWheel = models[1].meshes[2]                    
                    rightWheel = models[1].meshes[4]                    
                    rearAxis = models[1].meshes[1]

                    # change transform according to sensor values
                    # axis: [horizontal axis (left/right), vertical axis (up/down), longitudinal axis (forward/backward)]
                    leftWheel.transform.eulerRotation = [0.0, (positionalData.steerAngle - 120) * π/180, 0.0]
                    leftWheel.transform.matrix = transformAroundReference(leftWheel.transform, [0.0, 9.0, -12.0])
                    rightWheel.transform.eulerRotation = [0.0, (positionalData.steerAngle - 120) * π/180, 0.0]
                    rightWheel.transform.matrix = transformAroundReference(rightWheel.transform, [0.0, 9.0, -12.0])

                    rearAxis.transform.eulerRotation = [rearAxis.transform.eulerRotation[1] + positionalData.sensorSpeed * 5, 0.0, 0.0]
                    rearAxis.transform.matrix = transformAroundReference(rearAxis.transform, [0.0, 9.0, 10.0])
                end

                for model in models     
                    # prefer transfer matrix if it is present in model and mesh                    
                    modelTransformMatrix = isnothing(model.transform.matrix) ? transformToMatrix(model.transform) : model.transform.matrix
                    for mesh in model.meshes            
                        writeToUniforms(program, modelTransformMatrix * (isnothing(mesh.transform.matrix) ? transformToMatrix(mesh.transform) : mesh.transform.matrix), cam, GLfloat[1.0, 1.0, 1.0], mesh.material)

                        glBindVertexArray(mesh.vao)
                        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, mesh.ebo)
                        glDrawElements(GL_TRIANGLES, mesh.sizeOfIndices, GL_UNSIGNED_INT - 2, Ptr{Cvoid}(0))
                        # unbind
                        glBindVertexArray(0)
                    end
                end
            end

            # CImGui Stuff:
            # Menu Bar
            begin 
                CImGui.BeginMainMenuBar()
                CImGui.SetWindowFontScale(globalFontScale)
                CImGui.MenuItem("Help") && global showHelperWindow = !showHelperWindow
                CImGui.MenuItem("Connect") && global showConnectWindow = !showConnectWindow
                if connected 
                    CImGui.MenuItem("Data Plots") && global showDataPlots = !showDataPlots 
                    if CImGui.MenuItem("Render Robot")
                        # Load models when rendering
                        if isempty(models)
                            push!(models, loadGLTFModelInBuffers(robotSource, robotData))
                            push!(models, loadGLTFModelInBuffers(plateSource, plateData))
                            models[1].transform = Transform([0.0, 2.75, 0.0], [0.0, -π/8, π], [0.15, 0.15, 0.15])
                        end
                        global renderRobot = !renderRobot
                    end
                    CImGui.MenuItem("Automatic Inputs") && global showAutomaticInputWindow = !showAutomaticInputWindow
                    CImGui.MenuItem("Record Data") && global recordDataWindow = !recordDataWindow
                end
                CImGui.MenuItem("Load Data") && global showLoadDataWindow = !showLoadDataWindow
                CImGui.EndMainMenuBar()
            end

            # Helper Window         
            showHelperWindow && handleHelperWidow()

            # Connection Window  
            if showConnectWindow          
            @cstatic portData = ""*"\0"^115 i0=Cint(123) @cstatic ipData = ""*"\0"^115 i0=Cint(123) begin
                    handleConnectWindow(ipData, portData)
                end  
            end   

            # Record Data Window
            if recordDataWindow
            @cstatic amountDataPoints = ""*"\0"^115 begin
                    !recordData && (saveDataLength = handleRecordDataWindow(amountDataPoints))
                    recordData && handleRecordDataWindow(amountDataPoints)
                end
            end

            showLoadDataWindow && handleShowDataWindow()

            showAutomaticInputWindow && handleAutomaticInputWindow()
 
            if useAutomaticInput              
                posData = commandLoop(window, automaticInput=automaticInput[automaticInputIndex][1])
            
                time = automaticInput[automaticInputIndex][2]
                global automaticInputTimer += deltaTime
                if time <= automaticInputTimer
                    global automaticInputTimer = 0.0
                    global automaticInputIndex += 1

                    if automaticInputIndex >= length(automaticInput) global useAutomaticInput = !useAutomaticInput end
                end
            else 
                posData = commandLoop(window)
            end
            
            # Add Positional Data to storage
            if posData != 0 && !isnothing(posData)
                # Draw over everyting dummy window
                CImGui.SetNextWindowSize(windowSize)
                CImGui.SetNextWindowPos((0, 30))
                CImGui.Begin("##dummy_window", C_NULL, CImGui.ImGuiWindowFlags_NoResize | CImGui.ImGuiWindowFlags_NoTitleBar | CImGui.ImGuiWindowFlags_NoInputs | CImGui.ImGuiWindowFlags_NoMove | CImGui.ImGuiWindowFlags_NoSavedSettings | CImGui.ImGuiWindowFlags_NoScrollbar | CImGui.ImGuiWindowFlags_NoBackground)
                CImGui.SetWindowFontScale(2.0)
                CImGui.Text("Robot data\nSpeed: $(posData.sensorSpeed)\nMax Speed: $(posData.maxSpeed)\nSteering Angle: $(posData.steerAngle)")
                CImGui.End()

                push!(rawPositionalData, posData)
                if size(rawPositionalData, 1) > rawDataLength
                    popfirst!(rawPositionalData)
                end

                if recordData
                    push!(rawSavePosData, posData)
                    if size(rawSavePosData, 1) > saveDataLength
                        toggleRecordData("")
                        global rawSavePosData = StructArray(PositionalData[])
                    end
                end
            end

            if estSettingWindow
                let s = estimationSettingsWindow()
                global settings = (s == -1) ? settings : s
                end  
            end

            if showRecoredDataPlots
                plotData((1000, 700), rawSavePosData[1:rawSaveDataLength], "Recorded data Plot", settings)
            end

            if showDataPlots && size(rawPositionalData, 1) > 0
                plotData((1000, 700), rawPositionalData, "On time positional data", settings)
            end            

            CImGui.Render()
            ImGui_ImplOpenGL3_RenderDrawData(CImGui.GetDrawData())                 

            GLFW.SwapBuffers(window)
            GLFW.PollEvents()
        end
    finally
        CImGui.DestroyContext(ctx)
        GLFW.DestroyWindow(window)
    end
end

"""
This is the starting point of the program.
"""
function main()
    # Set global font scale on start up
    for args in ARGS
        global globalFontScale = tryparse(Float64, args)
        isnothing(globalFontScale) && global globalFontScale = 1.0
    end

    # Create window and start main loop
    window, ctx, program = setUpWindow(windowSize, "AT-RP Controller", "assets/icon_64.png")
    cam.aspectRatio = windowSize[1]/windowSize[2]
    mainLoop(window, ctx, program)
end

main()