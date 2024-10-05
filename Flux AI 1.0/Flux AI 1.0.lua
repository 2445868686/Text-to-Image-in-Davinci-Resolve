local infomsg =[[
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
    <h3>FLUX1.1 [pro]</h3>
    <p>Top-of-the-line image generation with blazing speed and quality.</p>

    <h3>FLUX.1 [pro]</h3>
    <p>High-speed image generation with excellent quality and diversity. </p>

    <h3>FLUX.1 [dev]</h3>
    <p>An open-weight model for non-commercial use, distilled from FLUX.1 [pro] for efficiency.</p>
</body>
</html>
]]
local ui = fu.UIManager
local disp = bmd.UIDispatcher(ui)
local json = require('dkjson')
math.randomseed(os.time())
local function AddToMediaPool(filename)
    local resolve = Resolve()
    local projectManager = resolve:GetProjectManager()
    local project = projectManager:GetCurrentProject()
    local mediaPool = project:GetMediaPool()
    local rootFolder = mediaPool:GetRootFolder()
    local aiImageFolder = nil

    -- 检查 AiImage 文件夹是否已存在
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
local function loadImageInFusion(image_path)

    comp:Lock()
    local loader = comp:AddTool("Loader")
    loader.Clip[comp.CurrentTime] = image_path
    loader:SetAttrs({TOOLS_RegenerateCache = true})
    comp:Unlock()

end

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
    USE_RANDOM_SEED = true
}

-- Use saved settings if they exist, otherwise use default settings
local settings = saved_settings or default_settings

-- Save settings to the file
save_settings(settings_file, settings)

-- Function to encode a table into a JSON-like string without using any third-party libraries
local function encode_json(tbl)
    local json_str = "{"
    for k, v in pairs(tbl) do
        -- Add key-value pairs to the JSON string, ensuring correct formatting and escaping quotes
        if type(v) == "string" then
            v = v:gsub("\"", "\\\"")  -- Escape double quotes in strings
            json_str = json_str .. string.format("\"%s\":\"%s\",", k, v)
        else
            json_str = json_str .. string.format("\"%s\":%s,", k, tostring(v))
        end
    end
    -- Remove the trailing comma and close the JSON string
    json_str = json_str:sub(1, -2) .. "}"
    return json_str
end

-- Function to send an HTTP POST request without using third-party libraries
local function http_post(url, headers, body)
    -- Use single quotes around body to ensure it is treated correctly in the shell
    local command
    if package.config:sub(1, 1) == '\\' then  -- Windows
        body = body:gsub('"', '\\"')
        command = string.format(
            'curl -s -X POST -H "Content-Type: %s" -H "X-Key: %s" -H "Accept: application/json" --data-raw "%s" %s',
            headers["Content-Type"], headers["X-Key"], body, url
        )
    else  -- Unix-like systems
        command = string.format(
            'curl -s -X POST -H "Content-Type: %s" -H "X-Key: %s" -H "Accept: application/json" --data-raw '%s' %s',
            headers["Content-Type"], headers["X-Key"], body, url
        )
    end
    print(command)
    local handle = io.popen(command)
    local result = handle:read("*a")
    handle:close()
    return result
end

-- Function to send an HTTP GET request without using any third-party libraries
local function http_get(url)
    local command = string.format("curl -s -X GET %s", url)
    local handle = io.popen(command)
    local result = handle:read("*a")
    handle:close()
    return result
end

-- Function to generate an image by making a POST request to the API
local function generate_image(settings)
    -- Ensure required parameters are provided in the settings
    assert(settings.API_KEY, "API key (Key) is required.")
    assert(settings.PROMPT, "Prompt is required.")
    assert(settings.WIDTH, "Image width is required.")
    assert(settings.HEIGHT, "Image height is required.")
    assert(settings.PROMPT_UPSAMPLING ~= nil, "Prompt upsampling (true/false) is required.")
    assert(settings.SEED, "Seed is required.")
    assert(settings.SAFETY_TOLERANCE, "Safety tolerance is required.")
    assert(settings.MODEL, "Model is required (0 for flux-pro-1.1, 1 for flux-pro, 2 for flux-dev).")

    -- Additional assertions based on model type
    if settings.MODEL == 1 or settings.MODEL == 2 then
        assert(settings.STEPS, "Steps are required.")
        assert(settings.GUIDANCE, "Guidance is required.")
    end
    if settings.MODEL == 2 then
        assert(settings.INTERVAL, "Interval is required.")
    end

    -- Prepare the payload with all required parameters
    local payload = {
        prompt = settings.PROMPT,
        width = settings.WIDTH,
        height = settings.HEIGHT,
        prompt_upsampling = settings.PROMPT_UPSAMPLING,
        seed = settings.SEED,
        safety_tolerance = settings.SAFETY_TOLERANCE
    }

    -- Add additional parameters based on model type
    if settings.MODEL == 1 or settings.MODEL == 2 then
        payload.steps = settings.STEPS
        payload.guidance = settings.GUIDANCE
    end
    if settings.MODEL == 1 then
        payload.interval = settings.INTERVAL
    end

    -- Convert the payload table into a JSON-like string
    local request_body = encode_json(payload)

    -- Prepare the headers for the request
    local headers = {
        ["Content-Type"] = "application/json",
        ["X-Key"] = settings.API_KEY
    }

    -- Determine the URL based on model type
    local url
    if settings.MODEL == 0 then
        url = "https://api.bfl.ml/v1/flux-pro-1.1"
    elseif settings.MODEL == 2 then
        url = "https://api.bfl.ml/v1/flux-dev"
    elseif settings.MODEL == 1 then
        url = "https://api.bfl.ml/v1/flux-pro"
    else
        error("Invalid model type: " .. settings.MODEL)
    end

    -- Send the POST request to generate the image
    local response = http_post(url, headers, request_body)
    print(response)
    -- Parse the response (assuming it is a simple JSON-like string)
    local id = response:match('"id":"(.-)"')
    if id then
        return id  -- Return the ID to be used for polling the result
    else
        error("Failed to generate image: " .. response)
    end
end


-- Function to get the result of the generated image by polling the API
local function get_image_result(id)
    assert(id, "ID is required to get the result.")

    local url = "https://api.bfl.ml/v1/get_result?id=" .. id
    local max_attempts = 10  -- 最大重试次数
    local attempt = 0
    local wait_time = 5  -- 每次重试之间的等待时间（秒）

    while attempt < max_attempts do
        local response = http_get(url)

        -- Parse the response to extract the status and image URL
        local status = response:match('"status":"(.-)"')
        local image_url = response:match('"sample":"(.-)"')

        if status == "Ready" and image_url then
            return image_url  -- 返回生成的图像 URL
        elseif status == "Pending" then
            print("Attempt " .. (attempt + 1) .. " of " .. max_attempts .. ": Image generation is still pending.")
            update_Status("Attempt " .. (attempt + 1) .. " of " .. max_attempts .. ": Image generation is still pending.")
            attempt = attempt + 1
            if package.config:sub(1, 1) == '\\' then  -- Windows
                os.execute("timeout " .. wait_time)
            else  -- macOS and Unix-like systems
                os.execute("sleep " .. wait_time)
            end            
        elseif status == "Task not found" then
            error("Task not found: The given task ID is invalid or expired.")
        elseif status == "Request Moderated" then
            error("Request Moderated: The request was moderated and cannot be processed.")
        elseif status == "Content Moderated" then
            error("Content Moderated: The generated content was moderated and cannot be processed.")
        elseif status == "Error" then
            error("Error: There was an error while processing the request.")
        else
            error("Unexpected response status: " .. (status or "unknown") .. ". Full response: " .. response)
        end
    end

    -- 如果达到最大重试次数后仍未成功
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
            os.execute(string.format("mkdir \"%s\" 2>nul || exit 0", directory))
        else  -- Unix-like systems
            os.execute(string.format("mkdir -p \"%s\"", directory))
        end
    end

    local command = string.format("curl -s -o \"%s\" %s", output_path, image_url)
    update_Status("Downloading the image")
    print(command)
    local result = os.execute(command)
    print("Image saved as " .. output_path)

    -- Check if the download was successful
    local file = io.open(output_path, "r")
    if file then
        file:close()
        return true
    else
        return false
    end
end


-- Function to generate the output file name based on settings.OUTPUT_DIRECTORY and settings.SEED
local function generate_output_file_name(settings)
    local unique_suffix = tostring(os.time()) .. tostring(math.random(1000, 9999))  -- Use a timestamp and random number for uniqueness
    local output_directory = settings.OUTPUT_DIRECTORY
    local os_name = package.config:sub(1, 1)  -- Get the OS-specific path separator

    if os_name == '\\' then  -- Windows
        if output_directory:sub(-1) ~= "\\" then
            output_directory = output_directory .. "\\"
        end
        return output_directory .. "image" .. tostring(settings.SEED) .. "_" .. unique_suffix .. ".jpg"
    else  -- Unix-like systems
        if output_directory:sub(-1) ~= "/" then
            output_directory = output_directory .. "/"
        end
        return output_directory .. "image" .. tostring(settings.SEED) .. "_" .. unique_suffix .. ".jpg"
    end
end

win = disp:AddWindow(
{
    ID = 'MyWin',
    WindowTitle = 'Flux AI Version 1.0',
    Geometry = {700, 300, 400, 480},
    Spacing = 10,
    ui:VGroup{
        ui:TabBar { Weight = 0.0, ID = "MyTabs", },
       
        ui:Stack{
            Weight = 1.0,
            ID = "MyStack",

            ui:VGroup {
                Weight = 1,
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'ModelLabel', Text = 'Model',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:ComboBox{ID = 'ModelCombo', Text = 'Model',Weight = 0.8},
        
                },

                ui:HGroup {
        
                    Weight = 0.5,
                    ui:TextEdit{ID='PromptTxt', Text = '', PlaceholderText = 'Please Enter a Prompt.',Weight = 0.5},
        
                },
                
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'WidthLabel', Text = 'Width',Alignment = { AlignRight = false },Weight = 0.1,},
                    ui:SpinBox{ID = "Width",Value = 768 , Minimum = 256,Maximum = 1440,SingleStep = 32, Weight = 0.4},
                    ui:Label {ID = 'HeightLabel', Text = 'Height',Alignment = { AlignRight = false },Weight = 0.1,},
                    ui:SpinBox{ID = "Height",Value = 1024 ,Minimum = 256,Maximum = 1440,SingleStep = 32, Weight = 0.4}
                
                },
                    
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'SafetyToleranceLabel', Text = 'Safety',Alignment = { AlignRight = false },Weight = 0.1},
                    ui:SpinBox{ID = "SafetyTolerance",Value = 2,Minimum = 0,Maximum = 6,SingleStep = 1, Weight = 0.4},
                    ui:Label {ID = 'SeedLabel', Text = 'Seed',  Alignment = { AlignRight = false },Weight = 0.1},
                    ui:SpinBox{ID = "Seed",Value = 0,Minimum = 0,Maximum = 4999999999,SingleStep = 1, Weight = 0.4}
        
                },

                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'StepsLabel', Text = 'Steps',Alignment = { AlignRight = false },Weight = 0.1,},
                    ui:SpinBox{ID = "Steps",Value = 20 , Minimum = 1,Maximum = 50,SingleStep = 1, Weight = 0.4},
                    ui:Label {ID = 'GuidanceLabel', Text = 'Guidance',Alignment = { AlignRight = false },Weight = 0.1,},
                    ui:DoubleSpinBox{ID = "Guidance",Value = 2.5 ,Minimum = 1.5,Maximum =5.0,SingleStep = 0.1, Weight = 0.4}
          
                },

        
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'IntervalLabel', Text = 'Interval',Alignment = { AlignRight = false },Weight = 0.1,},
                    ui:DoubleSpinBox{ID = "Interval",Value = 2.0 ,Minimum = 1.0,Maximum =4.0,SingleStep = 0.1, Weight = 0.4},
                    
        
                },
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:CheckBox {ID = 'RandomSeed',Text = 'Use Random Seed',Checked = true, Weight = 0.5},
                    ui:CheckBox {ID = 'PromptUpsampling',Text = 'Prompt Upsampling',Checked = true, Weight = 0.5},
        
                
                },
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Button {ID = 'GenerateButton', Text = 'Generate'},
                    ui:Button {ID = 'ResetButton', Text = 'Reset'},
                    ui:Button {ID = 'HelpButton', Text = 'Help'},
                },
        
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'StatusLabel', Text = ' ',Alignment = { AlignHCenter = true, AlignVCenter = true }},
                   
                },
        
                ui:Button {
                    ID = 'OpenLinkButton',
                    Text = '😃Buy Me a Coffee😃，© 2024, Copyright by HB.',
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
            ui:VGroup{
                ui:HGroup {
        
                    Weight = 0.05,
                    ui:CheckBox {ID = 'DRCheckBox',Text = 'Use In DavVnci Resolve',Checked = true,Weight = 0.5},
                    ui:CheckBox {ID = 'FUCheckBox',Text = 'Use In Fusion Studio',Checked = false,Weight = 0.5},
        
                },
                ui:HGroup {
            
                    Weight = 0.05,
                    ui:Label {ID = 'PathLabel', Text = 'Save Path',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:LineEdit {ID = 'Path', Text = '', PlaceholderText = '',ReadOnly = false ,Weight = 0.6},
                    ui:Button{ ID = 'Browse', Text = 'Browse', Weight = 0.2, },
                    
                },
                ui:HGroup {

                    Weight = 0.05,
                    ui:Label {ID = 'ApiKeyLabel', Text = 'API Key',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:LineEdit {ID = 'ApiKey', Text = '',  EchoMode = 'Password',Weight = 0.8},    
                    ui:Button{ ID = 'RegisterButton', Text = 'Register', Weight = 0.2, },
                },
                ui.HGroup{
                    Weight = 0.05,
                    ui:Label{ID = "RegisterLabel",Text = " ",Weight = 0.2,Alignment = {AlignHCenter = true, AlignVCenter = true},}
               
                },
                ui:HGroup {
        
                    ui:TextEdit{ID='infoTxt', Text = infomsg ,ReadOnly = true,},
                    Weight = 0.85,
                },
                ui:Button {
                    ID = 'OpenLinkButton',
                    Text = '😃Buy Me a Coffee😃，© 2024, Copyright by HB.',
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
itm.MyTabs:AddTab("Generate")
itm.MyTabs:AddTab("Configuration")

local ModeL = {'FLUX 1.1 [pro]','FLUX.1 [pro]', 'FLUX.1 [dev]'}
for _, modeL in ipairs(ModeL) do
    itm.ModelCombo:AddItem(modeL)
end

local engine_id
function win.On.ModelCombo.CurrentIndexChanged(ev)
    itm.Interval.Visible = false
    itm.IntervalLabel.Visible = false
    itm.Guidance.Visible = false
    itm.GuidanceLabel.Visible = false
    itm.Steps.Visible = false
    itm.StepsLabel.Visible = false

    if itm.ModelCombo.CurrentIndex == 0 then
        engine_id = "flux-pro-1.1"
        print('Using Model: ' .. engine_id)
    elseif itm.ModelCombo.CurrentIndex == 1 then
        engine_id = "flux-pro"
        itm.Guidance.Visible = true
        itm.GuidanceLabel.Visible = true
        itm.Interval.Visible = true
        itm.IntervalLabel.Visible = true
        itm.Steps.Visible = true
        itm.StepsLabel.Visible = true
        print('Using Model: ' .. engine_id)
    elseif itm.ModelCombo.CurrentIndex == 2 then
        engine_id = "flux-dev"
        itm.Guidance.Visible = true
        itm.GuidanceLabel.Visible = true
        itm.Steps.Visible = true
        itm.StepsLabel.Visible = true
        print('Using Model: ' .. engine_id)
    else
        print('Unexpected ModelCombo index: ' .. itm.ModelCombo.CurrentIndex)
    end
end


if saved_settings then
    itm.DRCheckBox.Checked = saved_settings.USE_DR == nil and default_settings.USE_DR or saved_settings.USE_DR
    itm.FUCheckBox.Checked = saved_settings.USE_FU == nil and default_settings.USE_FU or saved_settings.USE_FU
    itm.ApiKey.Text = saved_settings.API_KEY or default_settings.API_KEY
    itm.Path.Text = saved_settings.OUTPUT_DIRECTORY or  default_settings.OUTPUT_DIRECTORY
    itm.ModelCombo.CurrentIndex = saved_settings.MODEL or  default_settings.MODEL
    itm.PromptTxt.PlainText = saved_settings.PROMPT or  default_settings.PROMPT
    itm.Width.Value = saved_settings.WIDTH or default_settings.WIDTH
    itm.Height.Value = saved_settings.HEIGHT or default_settings.HEIGHT
    itm.PromptUpsampling.Checked = saved_settings.PROMPT_UPSAMPLING or default_settings.PROMPT_UPSAMPLING
    itm.SafetyTolerance.Value = saved_settings.SAFETY_TOLERANCE or default_settings.SAFETY_TOLERANCE
    itm.RandomSeed.Checked = saved_settings.USE_RANDOM_SEED or default_settings.USE_RANDOM_SEED
    itm.Seed.Value = saved_settings.SEED or default_settings.SEED
    itm.Steps.Value = saved_settings.STEPS or default_settings.STEPS
    itm.Guidance.Value = saved_settings.GUIDANCE or default_settings.GUIDANCE
    itm.Interval.Value = saved_settings.INTERVAL or default_settings.INTERVAL 


end

function win.On.DRCheckBox.Clicked(ev)
    itm.FUCheckBox.Checked = not itm.DRCheckBox.Checked
    if itm.FUCheckBox.Checked then
        print("Using in Fusion Studio")
    else
        print("Using in DaVinci Resolve")

    end
end

function win.On.FUCheckBox.Clicked(ev)
    itm.DRCheckBox.Checked = not itm.FUCheckBox.Checked
    if itm.FUCheckBox.Checked then
        print("Using in Fusion Studio")

    else
        print("Using in DaVinci Resolve")

    end
end
function win.On.GenerateButton.Clicked(ev)
    if itm.Path.Text == '' then
        showWarningMessage('Please go to Configuration to select the image save path.')
        return
    end
    if itm.ApiKey.Text == '' then
        showWarningMessage('Please go to Configuration to enter the API Key.')
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
        PROMPT_UPSAMPLING =itm.PromptUpsampling.Checked,
        SEED = newseed,
        SAFETY_TOLERANCE = itm.SafetyTolerance.Value,
        OUTPUT_DIRECTORY = itm.Path.Text,
        STEPS = itm.Steps.Value,
        GUIDANCE = itm.Guidance.Value,
        INTERVAL = itm.Interval.Value,
        MODEL = itm.ModelCombo.CurrentIndex
    }
    if (settings.WIDTH % 32 ~= 0) or (settings.HEIGHT % 32 ~= 0) then
        showWarningMessage("Width and Height must be multiples of 32.")
        return  
    end
    print(settings.MODEL)
    -- Generate the image
    local image_id = generate_image(settings)
    print("Image ID: " .. image_id)
    update_Status("Image ID generated successfully")

    -- Poll for the image result
    local result_url = get_image_result(image_id)
    if result_url then
        local output_file_name = generate_output_file_name(settings)
        local log_output_path = output_file_name:gsub("%.jpg$", ".json")
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
            update_Status("Image generated successfully")
            if itm.DRCheckBox.Checked then
                AddToMediaPool(output_file_name)  
            else
                loadImageInFusion(output_file_name)
            end
        else
            print("Failed to generate image.")
            update_Status("Failed to generate image.")
        end        
    else
        print("Failed to generate image.")
        update_Status("Failed to generate image.")
    end
end

function win.On.OpenLinkButton.Clicked(ev)
    bmd.openurl("https://www.paypal.me/heiba2wk")
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
    itm.DRCheckBox.Checked = default_settings.USE_DR
    itm.FUCheckBox.Checked = default_settings.USE_FU
    --itm.Path.ReadOnly = false
    --itm.Path.Text = default_settings.OUTPUT_DIRECTORY
    --itm.ApiKey.Text = default_settings.API_KEY
    itm.ModelCombo.CurrentIndex = default_settings.MODEL
    itm.PromptTxt.PlainText = default_settings.PROMPT
    itm.Width.Value = default_settings.WIDTH
    itm.Height.Value =default_settings.HEIGHT
    itm.PromptUpsampling.Checked = default_settings.PROMPT_UPSAMPLING
    itm.SafetyTolerance.Value = default_settings.SAFETY_TOLERANCE
    itm.RandomSeed.Checked = default_settings.USE_RANDOM_SEED
    itm.Seed.Value = default_settings.SEED
    itm.Seed.Value = default_settings.SEED
    itm.Steps.Value = default_settings.STEPS
    itm.Guidance.Value = default_settings.GUIDANCE
    itm.Interval.Value = default_settings.INTERVAL 
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
        MODEL = itm.ModelCombo.CurrentIndex
    }

    save_settings(settings_file, settings)

end
function update_Status(message)
    itm.StatusLabel.Text = message
end

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

function win.On.MyWin.Close(ev)
    disp:ExitLoop()
    CloseAndSave()
end
-- 显示窗口
win:Show()
disp:RunLoop()
win:Hide()
 
