-- Import necessary modules
local ui = fu.UIManager
local disp = bmd.UIDispatcher(ui)
local json = require('dkjson')
math.randomseed(os.time())

-- Function to get the script path
local function get_script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[\\/])")  -- Match everything up to the last slash or backslash
end

-- Function to check if a file exists, and create it if it doesn't
local function check_or_create_file(filePath)
    local file = io.open(filePath, "r")
    if file then
        file:close()
    else
        file = io.open(filePath, "w")
        if file then
            file:write('{}')  -- Write an empty JSON object to initialize the file
            file:close()
        else
            error("Cannot create file: " .. filePath)
        end
    end
end

-- Load settings from a file
local function load_settings(filePath)
    local file = io.open(filePath, 'r')
    if file then
        local content = file:read('*a')
        file:close()
        if content and content ~= '' then
            local settings, _, err = json.decode(content)
            if err then
                print('Error decoding settings: ', err)
                return nil
            end
            return settings
        end
    end
    return nil
end

-- Save settings to a file
local function save_settings(filePath, settings)
    local file = io.open(filePath, 'w+')
    if file then
        local content = json.encode(settings, {indent = true})
        if content then
            file:write(content)
            print("Settings saved to file successfully.")
        else
            print("Error: Unable to encode settings to JSON.")
        end
        file:close()
    else
        print("Error: Unable to open file for writing: " .. filePath)
    end
end

-- Function to add media to DaVinci Resolve's media pool
local function AddToMediaPool(filename)
    local resolve = Resolve()
    local projectManager = resolve:GetProjectManager()
    local project = projectManager:GetCurrentProject()
    local mediaPool = project:GetMediaPool()
    local rootFolder = mediaPool:GetRootFolder()
    local aiImageFolder = nil

    -- Check if AiImage folder exists
    local folders = rootFolder:GetSubFolders()
    for _, folder in pairs(folders) do
        if folder:GetName() == "AiImage" then
            aiImageFolder = folder
            break
        end
    end

    if not aiImageFolder then
        aiImageFolder = mediaPool:AddSubFolder(rootFolder, "AiImage")
    end

    if aiImageFolder then
        print("AiImage folder is available: ", aiImageFolder:GetName())
    else
        print("Failed to create or find AiImage folder.")
        return false
    end

    local ms = resolve:GetMediaStorage()
    local mappedPath = fusion:MapPath(filename)
    mappedPath = mappedPath:gsub('\\\\', '\\')
    mediaPool:SetCurrentFolder(aiImageFolder)
    return mediaPool:ImportMedia(mappedPath)
end

-- Function to load image in Fusion
local function loadImageInFusion(image_path)
    comp:Lock()
    local loader = comp:AddTool("Loader")
    loader.Clip[comp.CurrentTime] = image_path
    loader:SetAttrs({TOOLS_RegenerateCache = true})
    comp:Unlock()
end

-- Initialize settings
local script_path = get_script_path()
local settings_file = ''
if package.config:sub(1, 1) == '\\' then
    settings_file = script_path .. '\\Flux_settings.json'
else
    settings_file = script_path .. '/Flux_settings.json'
end
check_or_create_file(settings_file)

local saved_settings = load_settings(settings_file) -- Try to load saved settings

local default_settings = {
    API_KEY = "",
    USE_FU = false,
    USE_DR = true,
    PROMPT = "",
    WIDTH = 1024,
    HEIGHT = 768,
    PROMPT_UPSAMPLING = false,
    SEED = 0,
    SAFETY_TOLERANCE = 2,
    STEPS = 20,
    GUIDANCE = 2.5,
    INTERVAL = 2.0,
    MODEL = 0,
    OUTPUT_DIRECTORY = "",
    STATUS = "",
    USE_RANDOM_SEED = true,
    OUTPUT_FORMAT = "jpeg",
    ASPECT_RATIO = "16:9",
    LANGUAGE = "cn" -- default language
}

-- Use saved settings if they exist, otherwise use default settings
local settings = saved_settings or default_settings

-- Save settings to the file
save_settings(settings_file, settings)

-- Function to encode a table into a JSON string
local function encode_json(tbl)
    local json_str = json.encode(tbl)
    if not json_str then
        error("Failed to encode JSON.")
    end
    return json_str
end

-- Function to send an HTTP POST request using curl
local function http_post(url, headers, body)
    -- Prepare headers for curl command
    local header_args = ''
    for key, value in pairs(headers) do
        header_args = header_args .. string.format('-H "%s: %s" ', key, value)
    end

    -- Use temporary files to store the request body and response
    local request_body_file = os.tmpname()
    local response_body_file = os.tmpname()
    local error_file = os.tmpname()

    -- Write the request body to a temporary file
    local body_file = io.open(request_body_file, "w")
    body_file:write(body)
    body_file:close()

    -- Construct the curl command
    local command = string.format('curl -s -X POST %s -d @"%s" "%s" -o "%s" 2> "%s"',
        header_args, request_body_file, url, response_body_file, error_file)
    print(body)
    print("Executing command: " .. command)
    local result = os.execute(command)

    -- Read the response body
    local response_file = io.open(response_body_file, "r")
    local response_body = response_file:read("*a")
    response_file:close()

    -- Clean up temporary files
    os.remove(request_body_file)
    os.remove(response_body_file)
    os.remove(error_file)

    return response_body
end

-- Function to send an HTTP GET request using curl
local function http_get(url)
    local response_body_file = os.tmpname()
    local error_file = os.tmpname()

    -- Construct the curl command
    local command = string.format('curl -s -X GET "%s" -o "%s" 2> "%s"',
        url, response_body_file, error_file)

    print("Executing command: " .. command)
    local result = os.execute(command)

    -- Read the response body
    local response_file = io.open(response_body_file, "r")
    local response_body = response_file:read("*a")
    response_file:close()

    -- Clean up temporary files
    os.remove(response_body_file)
    os.remove(error_file)

    return response_body
end

-- Function to generate an image by making a POST request to the API
local function generate_image(settings)
    -- Validate required parameters
    assert(settings.API_KEY and settings.API_KEY ~= "", "API key is required.")
    assert(settings.PROMPT and settings.PROMPT ~= "", "Prompt is required.")
    assert(settings.SAFETY_TOLERANCE ~= nil, "Safety tolerance is required.")
    assert(settings.SEED ~= nil, "Seed is required.")
    assert(settings.MODEL ~= nil, "Model is required.")

    local payload = {}
    local url

    if settings.MODEL == 3 then
        -- Ultra model
        url = "https://api.bfl.ml/v1/flux-pro-1.1-ultra"
        payload = {
            prompt = settings.PROMPT:gsub('[\r\n]', ' '),
            seed = settings.SEED,
            aspect_ratio = settings.ASPECT_RATIO or "16:9",
            safety_tolerance = settings.SAFETY_TOLERANCE,
            output_format = settings.OUTPUT_FORMAT or "jpeg",
            raw = settings.PROMPT_UPSAMPLING
        }
    else
        -- For other models, validate width and height
        assert(settings.WIDTH, "Image width is required.")
        assert(settings.HEIGHT, "Image height is required.")
        assert(settings.PROMPT_UPSAMPLING ~= nil, "Prompt upsampling (true/false) is required.")

        payload = {
            prompt = settings.PROMPT:gsub('[\r\n]', ' '),
            width = settings.WIDTH,
            height = settings.HEIGHT,
            prompt_upsampling = settings.PROMPT_UPSAMPLING,
            seed = settings.SEED,
            safety_tolerance = settings.SAFETY_TOLERANCE,
            output_format = settings.OUTPUT_FORMAT or "jpeg"
        }

        if settings.MODEL == 0 then
            -- flux-pro-1.1
            url = "https://api.bfl.ml/v1/flux-pro-1.1"
        elseif settings.MODEL == 1 then
            -- flux-pro
            url = "https://api.bfl.ml/v1/flux-pro"
            assert(settings.STEPS, "Steps are required for flux-pro model.")
            assert(settings.GUIDANCE, "Guidance is required for flux-pro model.")
            assert(settings.INTERVAL, "Interval is required for flux-pro model.")
            payload.steps = settings.STEPS
            payload.guidance = settings.GUIDANCE
            payload.interval = settings.INTERVAL
        elseif settings.MODEL == 2 then
            -- flux-dev
            url = "https://api.bfl.ml/v1/flux-dev"
            assert(settings.STEPS, "Steps are required for flux-dev model.")
            assert(settings.GUIDANCE, "Guidance is required for flux-dev model.")
            payload.steps = settings.STEPS
            payload.guidance = settings.GUIDANCE
        else
            error("Invalid model type: " .. tostring(settings.MODEL))
        end
    end

    -- Convert the payload to JSON
    local request_body = encode_json(payload)

    -- Prepare the headers
    local headers = {
        ["Content-Type"] = "application/json",
        ["X-Key"] = settings.API_KEY,
        ["Content-Length"] = tostring(#request_body)
    }

    -- Send the POST request
    update_Status("Sending request to generate image...")
    local response = http_post(url, headers, request_body)

    -- Parse the response
    local response_table, pos, err = json.decode(response)
    if not response_table then
        error("Failed to parse API response: " .. tostring(err))
    end

    if response_table.id then
        return response_table.id  -- Return the ID to be used for polling the result
    else
        error("Failed to generate image: " .. (response_table.detail or "Unknown error."))
    end
end

-- Function to get the result of the generated image by polling the API
local function get_image_result(id)
    assert(id, "ID is required to get the result.")

    local url = "https://api.bfl.ml/v1/get_result?id=" .. id
    local max_attempts = 10
    local attempt = 0
    local wait_time = 5  -- seconds

    while attempt < max_attempts do
        local response = http_get(url)

        -- Parse the response
        local response_table, pos, err = json.decode(response)
        if not response_table then
            error("Failed to parse API response: " .. tostring(err))
        end

        local status = response_table.status
        local result = response_table.result

        if status == "Ready" and result and result.sample then
            return result.sample  -- Return the image URL
        elseif status == "Pending" then
            attempt = attempt + 1
            update_Status("Attempt " .. attempt .. " of " .. max_attempts .. ": Image generation is still pending.")
            print("Attempt " .. attempt .. " of " .. max_attempts .. ": Image generation is still pending.")
            if package.config:sub(1, 1) == '\\' then  -- Windows
                os.execute("timeout " .. wait_time)
            else  -- macOS and Unix-like systems
                os.execute("sleep " .. wait_time)
            end
        elseif status == "Task not found" then
            update_Status("Task not found: The given task ID is invalid or expired.")
            error("Task not found: The given task ID is invalid or expired.")
        elseif status == "Request Moderated" then
            update_Status("Request Moderated: The request was moderated and cannot be processed.")
            error("Request Moderated: The request was moderated and cannot be processed.")
        elseif status == "Content Moderated" then
            update_Status("Content Moderated: The generated content was moderated and cannot be processed.")
            error("Content Moderated: The generated content was moderated and cannot be processed.")
        elseif status == "Error" then
            update_Status("Error: There was an error while processing the request.")
            error("Error: There was an error while processing the request.")
        else
            update_Status("Unexpected response status: " .. (status or "unknown") .. ". Full response: " .. response)
            error("Unexpected response status: " .. (status or "unknown") .. ". Full response: " .. response)
        end
    end

    update_Status("Failed to get image result after multiple attempts. Status remains 'Pending'.")
    error("Failed to get image result after multiple attempts. Status remains 'Pending'.")
end

-- Function to download an image from a given URL and save it as a file
local function download_image(image_url, output_path)
    assert(image_url, "Image URL is required to download the image.")
    assert(output_path, "Output path is required.")

    -- Ensure the output path uses double backslashes for Windows systems
    output_path = output_path:gsub("\\", "\\\\")

    -- Create the output directory if it doesn't exist
    local directory = output_path:match("^(.*)[/\\]")
    if directory then
        if package.config:sub(1, 1) == '\\' then  -- Windows
            os.execute(string.format('mkdir "%s" 2>nul || exit 0', directory))
        else  -- Unix-like systems
            os.execute(string.format('mkdir -p "%s"', directory))
        end
    end

    -- Use curl to download the image
    local command = string.format('curl -s "%s" -o "%s"', image_url, output_path)
    print("Executing command: " .. command)
    local result = os.execute(command)

    -- Check if the file was downloaded successfully
    local file = io.open(output_path, "r")
    if file then
        file:close()
        print("Image saved as " .. output_path)
        return true
    else
        print("Failed to download the image.")
        update_Status("Failed to download the image.")
        return false
    end
end

-- Function to generate the output file name
local function generate_output_file_name(settings)
    local unique_suffix = tostring(os.time()) .. tostring(math.random(1000, 9999))
    local output_directory = settings.OUTPUT_DIRECTORY
    local os_name = package.config:sub(1, 1)  -- Get the OS-specific path separator

    if os_name == '\\' then  -- Windows
        if output_directory:sub(-1) ~= "\\" then
            output_directory = output_directory .. "\\"
        end
    else  -- Unix-like systems
        if output_directory:sub(-1) ~= "/" then
            output_directory = output_directory .. "/"
        end
    end

    local extension = settings.OUTPUT_FORMAT == "png" and ".png" or ".jpg"
    return output_directory .. "image" .. tostring(settings.SEED) .. "_" .. unique_suffix .. extension
end

-- Function to update the status label
function update_Status(message)
    itm.StatusLabel.Text = message
end

-- Function to show warning messages to the user
function showWarningMessage(text)
    local msgbox = disp:AddWindow({
        ID = 'msg',
        WindowTitle = 'Warning',
        Geometry = {750, 400, 350, 100},
        Spacing = 10,
        ui:VGroup {
            ui:Label {ID = 'WarningLabel', Text = text},
            ui:HGroup {
                Weight = 0,
                ui:Button {ID = 'OkButton', Text = 'OK'},
            },
        },
    })

    function msgbox.On.OkButton.Clicked(ev)
        disp:ExitLoop()
    end

    msgbox:Show()
    disp:RunLoop()
    msgbox:Hide()
end

-- Function to extract concise error messages
local function extract_error_message(error_msg)
    -- Try to match the pattern ":%d+: (.+)$" to extract the error message after the line number
    local msg = error_msg:match(":%d+: (.+)$")
    if msg then
        return msg
    else
        return error_msg
    end
end

-- Function to validate user inputs
local function validate_inputs(settings)
    -- Validate safety tolerance
    if settings.SAFETY_TOLERANCE < 0 or settings.SAFETY_TOLERANCE > 6 then
        error("Safety Tolerance must be between 0 and 6.")
    end

    -- Validate aspect ratio for ultra model
    if settings.MODEL == 3 then
        local valid_aspect_ratios = {
            ["21:9"] = true, ["16:9"] = true, ["9:16"] = true,
            ["1:1"] = true, ["9:21"] = true, ["2:3"] = true,
            ["3:2"] = true, ["4:5"] = true, ["5:4"] = true,
        }
        if not valid_aspect_ratios[settings.ASPECT_RATIO] then
            error("Invalid aspect ratio. Valid options are: '1:1', '16:9', '21:9', '2:3', '3:2', '4:5', '5:4', '9:16', '9:21'.")
        end
    else
        -- For other models, validate width and height
        if settings.WIDTH % 32 ~= 0 or settings.HEIGHT % 32 ~= 0 then
            error("Width and Height must be multiples of 32.")
        end
        -- Validate guidance
        if settings.GUIDANCE and (settings.GUIDANCE < 1.5 or settings.GUIDANCE > 5.0) then
            error("Guidance must be between 1.5 and 5.0.")
        end
        -- Validate steps
        if settings.STEPS and (settings.STEPS < 1 or settings.STEPS > 50) then
            error("Steps must be between 1 and 50.")
        end
    end
end

-- Create the user interface

-- Load information messages based on language
local infomsg_en = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            font-family: Arial, sans-serif;
            color: #ffffff;
            padding: 20px;
        }
        h3 {
            font-weight: bold;
            font-size: 1.5em;
            margin-top: 15px;
            margin-bottom: 0px;
            border-bottom: 2px solid #f0f0f0;
            padding-bottom: 5px;
            color: #c7a364; /* Yellow */
        }
        p {
            font-size: 1.2em;
            margin-top: 5px;
            margin-bottom: 0px;
            color: #a3a3a3; /* Light grey */
        }
        a {
            color: #1e90ff;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <h3>FLUX1.1 [pro] Ultra</h3>
    <p>New RAW mode captures the genuine feel of candid photography</p>
    <h3>FLUX 1.1 [pro]</h3>
    <p>Top-of-the-line image generation with blazing speed and quality.</p>

    <h3>FLUX 1 [pro]</h3>
    <p>High-speed image generation with excellent quality and diversity. </p>

    <h3>FLUX 1 [dev]</h3>
    <p>An open-weight model for non-commercial use, distilled from FLUX.1 [pro] for efficiency.</p>
</body>
</html>
]]

local infomsg_cn = [[
<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            font-family: Arial, sans-serif;
            color: #ffffff;
            padding: 20px;
        }
        h3 {
            font-weight: bold;
            font-size: 1.5em;
            margin-top: 15px;
            margin-bottom: 0px;
            border-bottom: 2px solid #f0f0f0;
            padding-bottom: 5px;
            color: #c7a364; /* 黄色 */
        }
        p {
            font-size: 1.2em;
            margin-top: 5px;
            margin-bottom: 0px;
            color: #a3a3a3; /* 浅灰色 */
        }
        a {
            color: #1e90ff;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <h3>FLUX1.1 [pro] Ultra</h3>
    <p>新 Raw 模式可以捕捉偷拍摄影的真实感觉。</p>

    <h3>FLUX1.1 [pro]</h3>
    <p>顶级图像生成，速度与质量俱佳。</p>

    <h3>FLUX.1 [pro]</h3>
    <p>高速图像生成，质量和多样性表现卓越。</p>

    <h3>FLUX.1 [dev]</h3>
    <p>一个用于非商业用途的开源模型，由 FLUX.1 [pro] 精简优化而来，注重效率。</p>
</body>
</html>
]]

-- Initialize the window and UI elements
win = disp:AddWindow({
    ID = 'MyWin',
    WindowTitle = 'Flux AI Version 1.0',
    Geometry = {700, 300, 400, 500},
    Spacing = 10,
    ui:VGroup{
        ui:TabBar { Weight = 0.0, ID = "MyTabs", },
        ui:Stack{
            Weight = 1.0,
            ID = "MyStack",

            ui:VGroup { -- Tab 1: Generate
                Weight = 1,
                ui:HGroup {
                    Weight = 0.1,
                    ui:Label {ID = 'ModelLabel', Text = '模型', Alignment = { AlignRight = false }, Weight = 0.2},
                    ui:ComboBox{ID = 'ModelCombo', Text = 'Model', Weight = 0.8},
                },
                ui:HGroup {
                    Weight = 0.6,
                    ui:TextEdit{ID='PromptTxt', Text = '', PlaceholderText = '请输入提示词', Weight = 0.5},
                },
                ui:HGroup {
                    Weight = 0.1,
                    ui:CheckBox {ID = 'RandomSeed', Text = '使用随机种子', Checked = true, Weight = 0.4},
                    ui:CheckBox {ID = 'PromptUpsampling', Text = '提示超采样', Checked = true, Weight = 0.3},
                },
                ui:HGroup {
                    Weight = 0.1,
                    ui:Label {ID = 'OutputFormatLabel', Text = '格式', Alignment = { AlignRight = false }, Weight = 0.1,},
                    ui:ComboBox{ID = 'OutputFormatCombo', Weight = 0.4},
                    ui:Label {ID = 'AspectRatioLabel', Text = '宽高比', Alignment = { AlignRight = false }, Weight = 0.1,},
                    ui:ComboBox{ID = 'AspectRatioCombo', Weight = 0.4},
                },
                ui:HGroup {
                    Weight = 0.1,
                    ui:Label {ID = 'SafetyToleranceLabel', Text = '安全度', Alignment = { AlignRight = false }, Weight = 0.1},
                    ui:SpinBox{ID = "SafetyTolerance", Value = 2, Minimum = 0, Maximum = 6, SingleStep = 1, Weight = 0.4},
                    ui:Label {ID = 'SeedLabel', Text = '种子',  Alignment = { AlignRight = false }, Weight = 0.1},
                    ui:SpinBox{ID = "Seed", Value = 0, Minimum = 0, Maximum = 4999999999, SingleStep = 1, Weight = 0.4}
                },
                ui:HGroup {
                    Weight = 0.1,
                    ui:Label {ID = 'WidthLabel', Text = '宽度', Alignment = { AlignRight = false }, Weight = 0.1,},
                    ui:SpinBox{ID = "Width", Value = 768 , Minimum = 256, Maximum = 1440, SingleStep = 32, Weight = 0.4},
                    ui:Label {ID = 'HeightLabel', Text = '高度', Alignment = { AlignRight = false }, Weight = 0.1,},
                    ui:SpinBox{ID = "Height", Value = 1024 , Minimum = 256, Maximum = 1440, SingleStep = 32, Weight = 0.4}
                },
                ui:HGroup {
                    Weight = 0.1,
                    ui:Label {ID = 'StepsLabel', Text = '步数', Alignment = { AlignRight = false }, Weight = 0.1,},
                    ui:SpinBox{ID = "Steps", Value = 20 , Minimum = 1, Maximum = 50, SingleStep = 1, Weight = 0.4},
                    ui:Label {ID = 'GuidanceLabel', Text = '指导度', Alignment = { AlignRight = false }, Weight = 0.1,},
                    ui:DoubleSpinBox{ID = "Guidance", Value = 2.5 , Minimum = 1.5, Maximum =5.0, SingleStep = 0.1, Weight = 0.4}
                },
                ui:HGroup {
                    Weight = 0.1,
                    ui:Label {ID = 'IntervalLabel', Text = '间隔', Alignment = { AlignRight = false }, Weight = 0.1,},
                    ui:DoubleSpinBox{ID = "Interval", Value = 2.0 , Minimum = 1.0, Maximum =4.0, SingleStep = 0.1, Weight = 0.4},
                    
                },
                
                
                ui:HGroup {
                    Weight = 0.1,
                    ui:Button {ID = 'GenerateButton', Text = '生成'},
                    ui:Button {ID = 'ResetButton', Text = '重置'},
                },
                ui:HGroup {
                    Weight = 0.1,
                    ui:Label {ID = 'StatusLabel', Text = ' ', Alignment = { AlignHCenter = true, AlignVCenter = true }},
                },
                ui:Button {
                    ID = 'OpenLinkButton',
                    Text = '😃请作者喝杯咖啡😃，© 2024, 版权所有 HB。',
                    Alignment = { AlignHCenter = true, AlignVCenter = true },
                    Font = ui:Font {
                        PixelSize = 12,
                        StyleName = 'Bold'
                    },
                    Flat = true,
                    TextColor = {0.1, 0.3, 0.9, 1},
                    BackgroundColor = {1, 1, 1, 0},
                    Weight = 0.1
                },
            },
            ui:VGroup{ -- Tab 2: Configuration
                ui:HGroup {
                    Weight = 0.05,
                    ui:CheckBox {ID = 'DRCheckBox', Text = '在DaVinci Resolve中使用', Checked = true, Weight = 0.5},
                    ui:CheckBox {ID = 'FUCheckBox', Text = '在Fusion Studio中使用', Checked = false, Weight = 0.5},
                },
                ui:HGroup {
                    Weight = 0.05,
                    ui:Label {ID = 'PathLabel', Text = '保存路径', Alignment = { AlignRight = false }, Weight = 0.2},
                    ui:LineEdit {ID = 'Path', Text = '', PlaceholderText = '', ReadOnly = false , Weight = 0.6},
                    ui:Button{ ID = 'Browse', Text = '打开', Weight = 0.2, },
                },
                ui:HGroup {
                    Weight = 0.05,
                    ui:Label {ID = 'ApiKeyLabel', Text = 'API Key', Alignment = { AlignRight = false }, Weight = 0.2},
                    ui:LineEdit {ID = 'ApiKey', Text = '',  EchoMode = 'Password', Weight = 0.8},
                    ui:Button{ ID = 'RegisterButton', Text = '注册', Weight = 0.2, },
                },
                ui.HGroup{
                    Weight = 0.05,
                    ui:Label{ID = "RegisterLabel", Text = " ", Weight = 0.2, Alignment = {AlignHCenter = true, AlignVCenter = true},}
                },
                ui:HGroup {
                    ui:TextEdit{ID='infoTxt', Text = '', ReadOnly = true,},
                    Weight = 0.85,
                },
                ui:Button {
                    ID = 'OpenLinkButton',
                    Text = '😃请作者喝杯咖啡😃，© 2024, 版权所有 HB。',
                    Alignment = { AlignHCenter = true, AlignVCenter = true },
                    Font = ui:Font {
                        PixelSize = 12,
                        StyleName = 'Bold'
                    },
                    Flat = true,
                    TextColor = {0.1, 0.3, 0.9, 1},
                    BackgroundColor = {1, 1, 1, 0},
                    Weight = 0.1,
                },
            },
        },
    },
})

itm = win:GetItems()
itm.MyStack.CurrentIndex = 0
itm.MyTabs:AddTab("文生图")
itm.MyTabs:AddTab("配置")

-- Populate the Model ComboBox
local ModeL = {'FLUX 1.1 [pro]', 'FLUX 1 [pro]', 'FLUX 1 [dev]', 'FLUX 1.1 [pro] Ultra'}
for _, modeL in ipairs(ModeL) do
    itm.ModelCombo:AddItem(modeL)
end

-- Populate Output Format ComboBox
itm.OutputFormatCombo:AddItem("jpeg")
itm.OutputFormatCombo:AddItem("png")

-- Populate Aspect Ratio ComboBox
local aspectRatios = {'1:1', '16:9', '21:9', '2:3', '3:2', '4:5', '5:4', '9:16', '9:21'}
for _, ar in ipairs(aspectRatios) do
    itm.AspectRatioCombo:AddItem(ar)
end

-- Update UI elements based on selected model
function win.On.ModelCombo.CurrentIndexChanged(ev)
    itm.Interval.Visible = false
    itm.IntervalLabel.Visible = false
    itm.Guidance.Visible = false
    itm.GuidanceLabel.Visible = false
    itm.Steps.Visible = false
    itm.StepsLabel.Visible = false
    itm.AspectRatioCombo.Visible = false
    itm.AspectRatioLabel.Visible = false
    itm.Width.Visible = true
    itm.WidthLabel.Visible = true
    itm.Height.Visible = true
    itm.HeightLabel.Visible = true
    itm.PromptUpsampling.Visible = true
    itm.PromptUpsampling.Text = "提示超采样"

    local model_index = itm.ModelCombo.CurrentIndex
    if model_index == 0 then
        -- flux-pro-1.1
    elseif model_index == 1 then
        -- flux-pro
        itm.Guidance.Visible = true
        itm.GuidanceLabel.Visible = true
        itm.Interval.Visible = true
        itm.IntervalLabel.Visible = true
        itm.Steps.Visible = true
        itm.StepsLabel.Visible = true
    elseif model_index == 2 then
        -- flux-dev
        itm.Guidance.Visible = true
        itm.GuidanceLabel.Visible = true
        itm.Steps.Visible = true
        itm.StepsLabel.Visible = true
    elseif model_index == 3 then
        -- flux-pro-1.1-ultra
        itm.AspectRatioCombo.Visible = true
        itm.AspectRatioLabel.Visible = true
        itm.Width.Visible = false
        itm.WidthLabel.Visible = false
        itm.Height.Visible = false
        itm.HeightLabel.Visible = false
        itm.PromptUpsampling.Text = "RAW模式"
    else
        print('Unexpected ModelCombo index: ' .. model_index)
    end
end

-- Load saved settings into UI
if saved_settings then
    itm.DRCheckBox.Checked = saved_settings.USE_DR == nil and default_settings.USE_DR or saved_settings.USE_DR
    itm.FUCheckBox.Checked = saved_settings.USE_FU == nil and default_settings.USE_FU or saved_settings.USE_FU
    itm.ApiKey.Text = saved_settings.API_KEY or default_settings.API_KEY
    itm.Path.Text = saved_settings.OUTPUT_DIRECTORY or default_settings.OUTPUT_DIRECTORY
    itm.ModelCombo.CurrentIndex = saved_settings.MODEL or default_settings.MODEL
    itm.PromptTxt.PlainText = saved_settings.PROMPT or default_settings.PROMPT
    itm.Width.Value = saved_settings.WIDTH or default_settings.WIDTH
    itm.Height.Value = saved_settings.HEIGHT or default_settings.HEIGHT
    itm.PromptUpsampling.Checked = saved_settings.PROMPT_UPSAMPLING or default_settings.PROMPT_UPSAMPLING
    itm.SafetyTolerance.Value = saved_settings.SAFETY_TOLERANCE or default_settings.SAFETY_TOLERANCE
    itm.RandomSeed.Checked = saved_settings.USE_RANDOM_SEED or default_settings.USE_RANDOM_SEED
    itm.Seed.Value = saved_settings.SEED or default_settings.SEED
    itm.Steps.Value = saved_settings.STEPS or default_settings.STEPS
    itm.Guidance.Value = saved_settings.GUIDANCE or default_settings.GUIDANCE
    itm.Interval.Value = saved_settings.INTERVAL or default_settings.INTERVAL
    itm.OutputFormatCombo.CurrentText = saved_settings.OUTPUT_FORMAT or default_settings.OUTPUT_FORMAT
    itm.AspectRatioCombo.CurrentText = saved_settings.ASPECT_RATIO or default_settings.ASPECT_RATIO
end

-- Event handlers for UI elements
function win.On.DRCheckBox.Clicked(ev)
    itm.FUCheckBox.Checked = not itm.DRCheckBox.Checked
end

function win.On.FUCheckBox.Clicked(ev)
    itm.DRCheckBox.Checked = not itm.FUCheckBox.Checked
end

function win.On.GenerateButton.Clicked(ev)
    update_Status("正在生成图像...")
    if itm.Path.Text == '' then
        showWarningMessage('请在配置中选择图像保存路径。')
        return
    end
    if itm.ApiKey.Text == '' then
        showWarningMessage('请在配置中输入API密钥。')
        return
    end

    local newseed
    if itm.RandomSeed.Checked then
        newseed = math.random(0, 705032703)
    else
        newseed = itm.Seed.Value or 0
    end
    itm.Seed.Value = newseed -- Update the seed value in the UI

    local settings = {
        API_KEY = itm.ApiKey.Text,
        PROMPT = itm.PromptTxt.PlainText,
        WIDTH = itm.Width.Value,
        HEIGHT = itm.Height.Value,
        PROMPT_UPSAMPLING = itm.PromptUpsampling.Checked,
        SEED = newseed,
        SAFETY_TOLERANCE = itm.SafetyTolerance.Value,
        OUTPUT_DIRECTORY = itm.Path.Text,
        STEPS = itm.Steps.Value,
        GUIDANCE = itm.Guidance.Value,
        INTERVAL = itm.Interval.Value,
        MODEL = itm.ModelCombo.CurrentIndex,
        OUTPUT_FORMAT = itm.OutputFormatCombo.CurrentText,
        ASPECT_RATIO = itm.AspectRatioCombo.CurrentText,
    }

    -- Validate inputs
    local status, err = pcall(function() validate_inputs(settings) end)
    if not status then
        showWarningMessage(err)
        return
    end

    -- Generate the image
    local status, result = pcall(function()
        local image_id = generate_image(settings)
        print("Image ID: " .. image_id)
        update_Status("生成任务已提交，任务ID：" .. image_id)

        -- Poll for the image result
        local result_url = get_image_result(image_id)
        if result_url then
            update_Status("Downloading.....")
            local output_file_name = generate_output_file_name(settings)
            local log_output_path = output_file_name:gsub("%.%w+$", ".json")
            local file = io.open(log_output_path, "w")
            if file then
                local json_output = encode_json({ id = image_id, image_url = result_url })
                file:write(json_output)
                file:close()
                print("Response saved to: " .. log_output_path)
            else
                error("Failed to save response to: " .. log_output_path)
            end

            if download_image(result_url, output_file_name) then
                print("Image generated successfully: " .. output_file_name)
                update_Status("图像生成成功")
                if itm.DRCheckBox.Checked then
                    AddToMediaPool(output_file_name)
                else
                    loadImageInFusion(output_file_name)
                end
            else
                print("Failed to generate image.")
                update_Status("图像生成失败")
            end
        else
            print("Failed to generate image.")
            update_Status("图像生成失败")
        end
    end)

    if not status then
        local error_message = extract_error_message(tostring(result))
        showWarningMessage(error_message)
        update_Status("图像生成失败")
    end
end

function win.On.OpenLinkButton.Clicked(ev)
    bmd.openurl("https://mp.weixin.qq.com/s?__biz=MzUzMTk2MDU5Nw==&mid=2247484658&idx=1&sn=f71c7f16e4a6bdb7e982fcac56b2bcda&chksm=fabbc288cdcc4b9e9292f4ba74807446bb80833e90c4d61398a2ea6ea582bcbdc201950d2f25#rd")
end

function win.On.RegisterButton.Clicked(ev)
    bmd.openurl("https://api.bfl.ml/auth/login")
end

function win.On.MyTabs.CurrentChanged(ev)
    itm.MyStack.CurrentIndex = ev.Index
end

function win.On.Browse.Clicked(ev)
    local currentPath = itm.Path.Text
    local selectedPath = fu:RequestDir(currentPath)
    if selectedPath then
        itm.Path.Text = tostring(selectedPath)
    else
        print("No directory selected or the request failed.")
    end
    itm.Path.ReadOnly = true
end

function win.On.ResetButton.Clicked(ev)
    -- Reset to default settings
    itm.DRCheckBox.Checked = default_settings.USE_DR
    itm.FUCheckBox.Checked = default_settings.USE_FU
    itm.ModelCombo.CurrentIndex = default_settings.MODEL
    itm.PromptTxt.PlainText = default_settings.PROMPT
    itm.Width.Value = default_settings.WIDTH
    itm.Height.Value = default_settings.HEIGHT
    itm.PromptUpsampling.Checked = default_settings.PROMPT_UPSAMPLING
    itm.SafetyTolerance.Value = default_settings.SAFETY_TOLERANCE
    itm.RandomSeed.Checked = default_settings.USE_RANDOM_SEED
    itm.Seed.Value = default_settings.SEED
    itm.Steps.Value = default_settings.STEPS
    itm.Guidance.Value = default_settings.GUIDANCE
    itm.Interval.Value = default_settings.INTERVAL
    itm.OutputFormatCombo.CurrentText = default_settings.OUTPUT_FORMAT
    itm.AspectRatioCombo.CurrentText = default_settings.ASPECT_RATIO
    itm.StatusLabel.Text = default_settings.STATUS
end

function CloseAndSave()
    local settings = {
        USE_DR = itm.DRCheckBox.Checked,
        USE_FU = itm.FUCheckBox.Checked,
        API_KEY = itm.ApiKey.Text,
        PROMPT_UPSAMPLING = itm.PromptUpsampling.Checked,
        OUTPUT_DIRECTORY = itm.Path.Text,
        PROMPT = itm.PromptTxt.PlainText,
        SEED = itm.Seed.Value,
        HEIGHT = itm.Height.Value,
        WIDTH = itm.Width.Value,
        SAFETY_TOLERANCE = itm.SafetyTolerance.Value,
        USE_RANDOM_SEED = itm.RandomSeed.Checked,
        STEPS = itm.Steps.Value,
        GUIDANCE = itm.Guidance.Value,
        INTERVAL = itm.Interval.Value,
        MODEL = itm.ModelCombo.CurrentIndex,
        OUTPUT_FORMAT = itm.OutputFormatCombo.CurrentText,
        ASPECT_RATIO = itm.AspectRatioCombo.CurrentText,
    }

    save_settings(settings_file, settings)
end

function win.On.MyWin.Close(ev)
    disp:ExitLoop()
    CloseAndSave()
end

-- Set info text based on language
local infomsg = settings.LANGUAGE == "cn" and infomsg_cn or infomsg_en
itm.infoTxt.Text = infomsg_cn

-- Show the window
win:Show()
disp:RunLoop()
win:Hide()
