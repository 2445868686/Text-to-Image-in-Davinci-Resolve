local infomsg = [[ 
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
                margin-bottom: 0px; /* 调整此处以减少间隔 */
                border-bottom: 2px solid #f0f0f0;
                padding-bottom: 5px;
                color: #c7a364; /* 黄色 */
            }
            p {
                font-size: 1.2em;
                margin-top: 5px;
                margin-bottom: 0px; /* 调整此处以减少间隔 */
                color: #a3a3a3; /* 白色 */
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
        <h3>Introduction</h3>
        <p>This script uses the <a href="https://stability.ai">Stability.AI</a> API to generate high-quality images, importable into DaVinci Resolve or via the Loader node in Fusion Studio.</p>
    
        <h3>Save Path</h3>
        <p>Specifies the save path for the generated files.</p>

        <h3>API_Key</h3>
        <p>Obtain your API key from <a href="https://stability.ai">Stability.AI</a></p>

        <h3>Image Generate V1</h3>
        <p>Here, you can use ' SDXL 1.0 ' and ' SD 1.6 ' to generate images.</p>

        <h3>Image Generate V2</h3>
        <p>Here, you can use ' Stable Image Core ', ' SD3 ', and ' SD3 ' Turbo to generate images.</p>
    </body>
    </html>    
    ]]
local ui = fu.UIManager
local disp = bmd.UIDispatcher(ui)
local comp = fusion:GetCurrentComp()
local math = require("math")
local json = require('dkjson')
local os_name = package.config:sub(1,1)  
math.randomseed(os.time())

function AddToMediaPool(filename)
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

function loadImageInFusion(image_path)

    comp:Lock()
    local loader = comp:AddTool("Loader")
    loader.Clip[comp.CurrentTime] = image_path
    loader:SetAttrs({TOOLS_RegenerateCache = true})
    comp:Unlock()

end

function get_remaining_credits(api_key)
    if not api_key then
        error("API key is not provided")
    end

    local api_host = os.getenv("API_HOST") or "https://api.stability.ai"
    local url = api_host .. "/v1/user/balance"

    local command = 'curl -f -sS "' .. url .. '" -H "Content-Type: application/json" -H "Authorization: Bearer ' .. api_key .. '"'
    local handle = io.popen(command)
    local result = handle:read("*a")
    handle:close()

    local json = require("dkjson")
    local payload, pos, err = json.decode(result, 1, nil)

    if err then
        error("Error parsing JSON: " .. err)
    end
    local credits = payload.credits or 0.0
    return tonumber(string.format("%.1f", credits))
end

function Generate_Image_V2(settings)
    updateStatus("Generating image...")
    local count = 0
    local output_file 
    local file_exists = false

    repeat
        count = count + 1
        local output_directory = settings.OUTPUT_DIRECTORY
        if os_name == '\\' then
            if output_directory:sub(-1) ~= "\\" then
                output_directory = output_directory .. "\\"
            end
            output_file = output_directory .. "image" .. tostring(settings.SEED) .. tostring(count) .. "a" ..".".. settings.OUTPUT_FORMAT
            output_file = output_file:gsub("\\", "\\\\")
        else
            if output_directory:sub(-1) ~= "/" then
                output_directory = output_directory .. "/"
            end
            output_file = output_directory .. "image" .. tostring(settings.SEED) .. tostring(count) .. "a" ..".".. settings.OUTPUT_FORMAT
        end
        local file = io.open(output_file, "r")
        file_exists = file ~= nil
        if file then file:close() end
    until not file_exists

    local function generate_curl_command(model, url, settings, output_file)
        local escaped_prompt = settings.PROMPT_V2:gsub('"', '\\"'):gsub("'", '\\"')
        local escaped_negative_prompt = settings.NEGATIVE_PROMPT:gsub('"', '\\"'):gsub("'", '\\"')
        
        local base_command = string.format(
            'curl -f -sS -X POST "%s" ' ..
            '-H "Authorization: Bearer %s" ' ..
            '-H "Accept: image/*" ' ..
            '-F prompt="%s" ' ..
            '-F negative_prompt="%s" ' ..
            '-F seed=%d ' ..
            '-F aspect_ratio="%s" ' ..
            '-F output_format="%s" ',
            url,
            settings.API_KEY,
            escaped_prompt,
            escaped_negative_prompt,
            settings.SEED,
            settings.ASPECT_RATIO,
            settings.OUTPUT_FORMAT
        )
    
        if model == "core" and settings.STYLE_PRESET ~= 'Default' then
            base_command = base_command .. string.format('-F style_preset="%s" ', settings.STYLE_PRESET)
        end
    
        if model == "sd3-large" or model == "sd3-large-turbo" or model == "sd3-medium" then
            base_command = base_command ..'-F mode="text-to-image" ' .. string.format('-F model="%s" ', model)
        end
    
        base_command = base_command .. string.format('-o "%s"', output_file)
    
        return base_command
    end
    
    local url
    local curl_command
    
    if settings.MODEL_V2 == "ultra" then
        url = "https://api.stability.ai/v2beta/stable-image/generate/ultra"
        curl_command = generate_curl_command("ultra", url, settings, output_file)
    
    elseif settings.MODEL_V2 == "core" then
        url = "https://api.stability.ai/v2beta/stable-image/generate/core"
        curl_command = generate_curl_command("core", url, settings, output_file)
    
    elseif settings.MODEL_V2 == "sd3-large" or settings.MODEL_V2 == "sd3-large-turbo" or settings.MODEL_V2 == "sd3-medium" then
        url = "https://api.stability.ai/v2beta/stable-image/generate/sd3"
        curl_command = generate_curl_command(settings.MODEL_V2, url, settings, output_file)
    
    else
        updateStatus("Invalid model specified.")
        return nil
    end
    print("Executing command: " .. curl_command)
    print("\nPrompt:",settings.PROMPT_V2,"\nNegative_Prompt:",settings.NEGATIVE_PROMPT,"\nStyle_Preset:",settings.STYLE_PRESET,"\nSeed:",settings.SEED,"\nAspect_Ratio:",settings.ASPECT_RATIO,"\nOutput_Format:",settings.OUTPUT_FORMAT,"\nFile_Name:",output_file)
    print("Generating image...")

    local success, _, exit_status = os.execute(curl_command)
    if success and exit_status == 0 then
        updateStatus("Image generated successfully.")
        print("["..exit_status.."]".."Success".."\noutput_file:"..output_file)
        return output_file
    else
        updateStatus("Failed to generate image["..exit_status.."]")
        print("[error]"..exit_status)
    end
end

function Generate_Image_V1(settings,engine_id)
    updateStatus("Generating image...")

    local url = "https://api.stability.ai/v1/generation/"..engine_id.."/text-to-image"
    local count = 0
    local output_file
    local file_exists
    repeat
        count = count + 1

        local output_directory = settings.OUTPUT_DIRECTORY
        if os_name == '\\' then
            if output_directory:sub(-1) ~= "\\" then
                output_directory = output_directory .. "\\"
            end
            output_file = output_directory .. "image" .. tostring(settings.SEED) .. tostring(count) .. "a" .. ".png"
            output_file = output_file:gsub("\\", "\\\\")
        else
            if output_directory:sub(-1) ~= "/" then
                output_directory = output_directory .. "/"
            end
            output_file = output_directory .. "image" .. tostring(settings.SEED) .. tostring(count) .. "a" .. ".png"
        end
        local file = io.open(output_file, "r")
        file_exists = file ~= nil
        if file then file:close() end
    until not file_exists
    local data = {
        text_prompts = {{
            text = settings.PROMPT_V1:gsub('"', "\'"):gsub("'", "\'")
        }},
        cfg_scale = settings.CFG_SCALE,
        height = settings.HEIGHT,
        width = settings.WIDTH,
        samples = settings.SAMPLES,
        steps = settings.STEPS,
        seed = settings.SEED,
        sampler = settings.SAMPLER
    }
    if settings.STYLE_PRESET_V1 ~= 'Default' then
        data.style_preset = settings.STYLE_PRESET_V1
    end

    local data_str = json.encode(data)

    -- 根据操作系统构建适当的 curl 命令
    local curl_command
    if os_name == '\\' then
        data_str = data_str:gsub('"', '\\"')
        curl_command = string.format(
        'curl -v -f -X POST "%s" ' ..
        '-H "Content-Type: application/json" ' ..
        '-H "Accept: image/png" ' ..
        '-H "Authorization: Bearer %s" ' ..
        '--data-raw "%s" -o "%s"',
        url, settings.API_KEY, data_str, output_file
     )
    else
        curl_command = string.format(
            'curl -v -f -X POST "%s" ' ..
            '-H "Content-Type: application/json" ' ..
            '-H "Accept: image/png" ' ..
            '-H "Authorization: Bearer %s" ' ..
            '--data-raw \'%s\' -o "%s"',
            url,settings.API_KEY,data_str,output_file
        )
    end

    print("Executing command: " .. curl_command)
    print("\nPrompt:",settings.PROMPT_V1,"\nSeed:",settings.SEED,"\ncfg:",settings.CFG_SCALE,"\nsampler:",settings.SAMPLER,"\nwidth:",settings.WIDTH,"\nheight:",settings.HEIGHT,"\nsamples:",settings.SAMPLES,"\nsteps:",settings.STEPS,"\nFile_Name:",output_file)
    print("Generating image...")
    
    -- 执行 curl 命令，并获取返回状态
    local success, _, exit_status = os.execute(curl_command)

    if success and exit_status == 0 then
    
        updateStatus("Image generated successfully.")
        print("["..exit_status.."]".."Image generated successfully.".."\noutput_file:"..output_file)
        return output_file
    else
        updateStatus("Failed to generate image:"..exit_status)
        print("[error]"..exit_status)
    end
end

function getScriptPath()

    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*[\\/])")  -- 匹配最后一个斜杠或反斜杠之前的所有字符

end

function checkOrCreateFile(filePath)

    local file = io.open(filePath, "r")
    if file then
        file:close() 
    else
        file = io.open(filePath, "w") 
        if file then
            file:write('{}') -- 写入一个空的JSON对象，以初始化文件
            file:close()
        else
            error("Cannot create file: " .. filePath)
        end
    end
end

local script_path = getScriptPath()
local settings_file ='' 
if os_name == '\\' then
    settings_file = script_path .. '\\Stability_settings.json' 
else
    settings_file = script_path .. '/Stability_settings.json' 
end
checkOrCreateFile(settings_file)

-- 从文件加载设置
function loadSettings()

    local file = io.open(settings_file, 'r')

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

-- 保存设置到文件
function saveSettings(settings)

    local file = io.open(settings_file, 'w+')

    if file then
        local content = json.encode(settings, {indent = true})
        file:write(content)
        file:close()
    end

end

local savedSettings = loadSettings() -- 尝试加载已保存的设置

local defaultSettings = {

    USE_DR = true,
    USE_FU = false,
    API_KEY = '',
    OUTPUT_DIRECTORY = '',
    PROMPT_V1 = '',
    PROMPT_V2 = '',
    NEGATIVE_PROMPT= '',
    STYLE_PRESET_V1 = 0,
    STYLE_PRESET = 0,
    ASPECT_RATIO= 0 ,
    MODEL_V1 = 0,
    MODEL_V2 = 0,
    SEED = '0',
    OUTPUT_FORMAT = 0,
    USE_RANDOM_SEED_V1 = true,
    USE_RANDOM_SEED_V2 = true,
    CFG_SCALE = '7',
    HEIGHT = '512',
    WIDTH = '512',
    SAMPLER = 0,
    SAMPLES = '1',
    STEPS = '30',


}

win = disp:AddWindow(
{
    ID = 'MyWin',
    WindowTitle = 'Stability AI Version 1.0',
    Geometry = {700, 300, 400, 480},
    Spacing = 10,
    ui:VGroup{
        ui:TabBar { Weight = 0.0, ID = "MyTabs", },
        
        ui:VGroup{



        },
       
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
        
                    Weight = 1,
                    ui:Label {ID = 'PromptLabel', Text = 'Prompt',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:TextEdit{ID='PromptTxt', Text = '', PlaceholderText = 'Please Enter a Prompt.',Weight = 0.8}
        
                },
                
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'ResolutionLabel', Text = 'Resolution',Alignment = { AlignRight = false },Weight = 0.2,},
                    ui:LineEdit {ID = 'Width', Text = '1024',Weight = 0.4,},
                    ui:LineEdit {ID = 'Height', Text = '1024',Weight = 0.4,},
                
                },
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'StyleLabel', Text = 'Style Preset',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:ComboBox{ID = 'StyleComboV1', Text = 'Style_Preset',Weight = 0.8},
        
                },
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'CfgScaleLabel', Text = 'CFG Scale',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:LineEdit {ID = 'CfgScale', Text = '7',Weight = 0.8},
        
                },
        
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'SamplerLabel', Text = 'Sampler',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:ComboBox{ID = 'SamplerCombo', Text = 'Sampler',Weight = 0.8},
        
                },
                
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'SamplesLabel', Text = 'Samples',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:LineEdit {ID = 'Samples', Text = '1',Weight = 0.8,ReadOnly = true},
        
                },
        
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'StepsLabel', Text = 'Steps',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:LineEdit {ID = 'Steps', Text = '30',Weight = 0.8},
        
                },
        
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'SeedLabel', Text = 'Seed',  Alignment = { AlignRight = false },Weight = 0.2},
                    ui:LineEdit {ID = 'Seed', Text = '0',Weight = 0.8},
        
                },
        
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Button {ID = 'HelpButton', Text = 'Help'},
                    ui:CheckBox {ID = 'RandomSeed',Text = 'Use Random Seed',Checked = true, 
                
                    },
        
                },
        
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Button {ID = 'GenerateButton', Text = 'Generate'},
                    ui:Button {ID = 'ResetButton', Text = 'Reset'},
        
                },
        
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'StatusLabel1', Text = ' ',Alignment = { AlignHCenter = true, AlignVCenter = true }},
                   
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
            ui:VGroup {
                Weight = 1,
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'ModelLabel', Text = 'Model',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:ComboBox{ID = 'ModelComboV2', Text = 'Model',Weight = 0.8},
        
                },
                ui:HGroup {
        
                    Weight = 1,
                    ui:Label {ID = 'PromptLabel', Text = 'Prompt',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:TextEdit{ID='PromptTxtV2', Text = '', PlaceholderText = 'Please Enter a Prompt.',Weight = 0.8}
        
                },
                
                ui:HGroup {
        
                    Weight = 1,
                    ui:Label {ID = 'NegativePromptLabel', Text = 'Negative',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:TextEdit{ID='NegativePromptTxt', Text = ' ', PlaceholderText = 'Please Enter a Negative Prompt.',Weight = 0.8}
        
                },
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'StyleLabel', Text = 'Style Preset',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:ComboBox{ID = 'StyleCombo', Text = 'Style_Preset',Weight = 0.8},
        
                },
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'AspectRatioLabel', Text = 'Aspect Ratio',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:ComboBox{ID = 'AspectRatioCombo', Text = 'aspect_ratio',Weight = 0.8},
        
                },
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'OutputFormatLabel', Text = 'Format',Alignment = { AlignRight = false },Weight = 0.2},
                    ui:ComboBox{ID = 'OutputFormatCombo', Text = 'Output_Format',Weight = 0.8},
        
                },
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'SeedLabel', Text = 'Seed',  Alignment = { AlignRight = false },Weight = 0.2},
                    ui:LineEdit {ID = 'SeedV2', Text = '0',Weight = 0.8},
        
                },
        
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Button {ID = 'HelpButton', Text = 'Help'},
                    ui:CheckBox {
        
                        ID = 'RandomSeedV2',
                        Text = 'Use Random Seed',
                        Checked = true, 
                
                    },
        
                },
        
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Button {ID = 'GenerateButton', Text = 'Generate'},
                    ui:Button {ID = 'ResetButton', Text = 'Reset'},
        
                },
        
                ui:HGroup {
        
                    Weight = 0.1,
                    ui:Label {ID = 'StatusLabel2', Text = ' ',Alignment = { AlignHCenter = true, AlignVCenter = true }},
        
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
                    ui:Button{ ID = 'Balance', Text = 'Balance', Weight = 0.2, },
                },
                ui.HGroup{
                    Weight = 0.05,
                    ui:Label{ID = "BalanceLabel",Text = "",Weight = 0.2,Alignment = {AlignHCenter = true, AlignVCenter = true},}
               
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
itm.MyTabs:AddTab("Image Generate V1")
itm.MyTabs:AddTab("Image Generate V2")
itm.MyTabs:AddTab("Configuration")


itm.ModelCombo:AddItem('SD 1.6')
itm.ModelCombo:AddItem('SDXL 1.0')
local engine_id
function win.On.ModelCombo.CurrentIndexChanged(ev)
    if itm.ModelCombo.CurrentIndex == 0 then
        engine_id = "stable-diffusion-v1-6"
        print('Using SD 1.6 ,Model:' .. engine_id )
    elseif itm.ModelCombo.CurrentIndex == 1 then
        engine_id = "stable-diffusion-xl-1024-v1-0"
        print('Using SDXL 1.0 ,Model:' .. engine_id )
    end
end

local samplers ={'DDIM','DDPM','K_DPMPP_2M','K_DPMPP_2S_ANCESTRAL','K_DPM_2','K_DPM_2_ANCESTRAL','K_EULER','K_EULER_ANCESTRAL','K_HEUN','K_LMS'}
for _, style in ipairs(samplers) do
    itm.SamplerCombo:AddItem(style)
end
function win.On.SamplerCombo.CurrentIndexChanged(ev)
    print('Using Sampler:' .. itm.SamplerCombo.CurrentText )
end

local MOdel = {'Stable Image Ultra','Stable Image Core', 'Stable Diffusion 3 Large', 'Stable Diffusion 3 Large Turbo','Stable Diffusion 3 Medium'}
for _, modeL in ipairs(MOdel) do
    itm.ModelComboV2:AddItem(modeL)
end


local stylePreset ={'Default','3d-model','analog-film','anime','cinematic','comic-book','digital-art','enhance','fantasy-art','isometric','line-art','low-poly','modeling-compound','neon-punk','origami','photographic','pixel-art','tile-texture',}
for _, style in ipairs(stylePreset) do
    itm.StyleCombo:AddItem(style)
    itm.StyleComboV1:AddItem(style)
end

local aspectRatios = {'1:1', '16:9', '21:9', '2:3', '3:2', '4:5', '5:4', '9:16', '9:21'}
for _, ratio in ipairs(aspectRatios) do
    itm.AspectRatioCombo:AddItem(ratio)
end

local outputFormat = {'png', 'jpeg','webp'}
for _, format in ipairs(outputFormat) do
    itm.OutputFormatCombo:AddItem(format)
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

function update_output_formats()

end


local model_id
function update_output_formats()
    if itm.ModelComboV2.CurrentIndex == 2 or itm.ModelComboV2.CurrentIndex == 3 or  itm.ModelComboV2.CurrentIndex == 4 then
        for i, format in ipairs(outputFormat) do
            if format == "webp" then
                table.remove(outputFormat, i)
                break
            end
        end
    else
        local webp_exists = false
        for _, format in ipairs(outputFormat) do
            if format == "webp" then
                webp_exists = true
                break
            end
        end
        if not webp_exists then
            table.insert(outputFormat, "webp")
        end
    end

    -- 获取当前选择的格式
    local current_selection = itm.OutputFormatCombo.CurrentText
    -- 清空现有的项目
    local count = itm.OutputFormatCombo:Count()
    for i = count - 1, 0, -1 do
        itm.OutputFormatCombo:RemoveItem(i)
    end

    -- 重新添加格式
    for _, format in ipairs(outputFormat) do
        itm.OutputFormatCombo:AddItem(format)
    end

    -- 重新设置当前选项
    for _, format in ipairs(outputFormat) do
        if format == current_selection then
            itm.OutputFormatCombo.CurrentIndex = _-1
            break
        else
            itm.OutputFormatCombo.CurrentIndex = 0
        end
    end

end

function win.On.ModelComboV2.CurrentIndexChanged(ev)
    itm.NegativePromptTxt.ReadOnly = false
    itm.StyleCombo.CurrentIndex = 0
    if itm.ModelComboV2.CurrentIndex == 0 then
        itm.StyleCombo.Enabled = false
        model_id = 'ultra'
    elseif itm.ModelComboV2.CurrentIndex == 1 then
        model_id = 'core'
        itm.StyleCombo.Enabled = true
    elseif itm.ModelComboV2.CurrentIndex == 2 then
        itm.StyleCombo.Enabled = false
        model_id = 'sd3-large'
    elseif itm.ModelComboV2.CurrentIndex == 3 then
        itm.NegativePromptTxt.ReadOnly = true
        itm.StyleCombo.Enabled = false
        itm.NegativePromptTxt.Text = ''
        model_id = 'sd3-large-turbo'
    elseif itm.ModelComboV2.CurrentIndex == 4 then
        itm.StyleCombo.Enabled = false
        model_id = 'sd3-medium'
    end
    print('Using Model:' .. itm.ModelComboV2.CurrentText )
    update_output_formats()
end

function win.On.AspectRatioCombo.CurrentIndexChanged(ev)
    print('Using Aspect_Ratio:' .. itm.AspectRatioCombo.CurrentText )
end

function win.On.OutputFormatCombo.CurrentIndexChanged(ev)
    -- print('Using Output_Format:' .. itm.OutputFormatCombo.CurrentText )
end

function win.On.OpenLinkButton.Clicked(ev)
    bmd.openurl("https://www.paypal.me/heiba2wk")
end

function updateStatus(message)
    itm.StatusLabel1.Text = message
    itm.StatusLabel2.Text = message
end

if savedSettings then
    itm.DRCheckBox.Checked = savedSettings.USE_DR == nil and defaultSettings.USE_DR or savedSettings.USE_DR
    itm.FUCheckBox.Checked = savedSettings.USE_FU == nil and defaultSettings.USE_FU or savedSettings.USE_FU
    itm.ApiKey.Text = savedSettings.API_KEY or defaultSettings.API_KEY
    itm.PromptTxtV2.PlainText = savedSettings.PROMPT_V2 or defaultSettings.PROMPT_V2
    itm.NegativePromptTxt.PlainText = savedSettings.NEGATIVE_PROMPT or defaultSettings.NEGATIVE_PROMPT
    itm.StyleCombo.CurrentIndex = savedSettings.STYLE_PRESET or defaultSettings.STYLE_PRESET
    itm.StyleComboV1.CurrentIndex = savedSettings.STYLE_PRESET_V1 or defaultSettings.STYLE_PRESET_V1
    itm.SeedV2.Text = tostring(savedSettings.SEED or defaultSettings.SEED)
    itm.RandomSeedV2.Checked = savedSettings.USE_RANDOM_SEED_V2 
    itm.ModelComboV2.CurrentIndex = savedSettings.MODEL_V2 or defaultSettings.MODEL_V2
    itm.AspectRatioCombo.CurrentIndex = savedSettings.ASPECT_RATIO or defaultSettings.ASPECT_RATIO
    itm.OutputFormatCombo.CurrentIndex = savedSettings.OUTPUT_FORMAT or defaultSettings.OUTPUT_FORMAT
    itm.Path.Text = savedSettings.OUTPUT_DIRECTORY or  defaultSettings.OUTPUT_DIRECTORY
    itm.PromptTxt.PlainText = savedSettings.PROMPT_V1 or defaultSettings.PROMPT_V1
    itm.Seed.Text = tostring(savedSettings.SEED or defaultSettings.SEED)
    itm.CfgScale.Text = tostring(savedSettings.CFG_SCALE or defaultSettings.CFG_SCALE)
    itm.Height.Text = tostring(savedSettings.HEIGHT or defaultSettings.HEIGHT)
    itm.Width.Text = tostring(savedSettings.WIDTH or defaultSettings.WIDTH)
    itm.Samples.Text = tostring(savedSettings.SAMPLES or defaultSettings.SAMPLES)
    itm.Steps.Text = tostring(savedSettings.STEPS or defaultSettings.STEPS)
    itm.RandomSeed.Checked = savedSettings.USE_RANDOM_SEED_V1 
    itm.ModelCombo.CurrentIndex = savedSettings.MODEL_V1 or defaultSettings.MODEL_V1
    itm.SamplerCombo.CurrentIndex = savedSettings.SAMPLER or defaultSettings.SAMPLER
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


function win.On.GenerateButton.Clicked(ev)
    if itm.Path.Text == '' then
        showWarningMessage('Please go to Configuration to select the image save path.')
        return
    end
    if itm.ApiKey.Text == '' then
        showWarningMessage('Please go to Configuration to enter the API Key.')
        return
    end

    if itm.MyTabs.CurrentIndex == 1 then 
        local newseed
        if itm.RandomSeedV2.Checked then
            newseed = math.random(0, 4294967295)
        else
            newseed = tonumber(itm.SeedV2.Text) or 0 -- 如果输入无效，默认为0
        end

        itm.SeedV2.Text = tostring(newseed) -- 更新界面上的显示

        local settings = {
            
            API_KEY = itm.ApiKey.Text,
            PROMPT_V2 = itm.PromptTxtV2.PlainText,
            NEGATIVE_PROMPT = itm.NegativePromptTxt.PlainText,
            STYLE_PRESET = itm.StyleCombo.CurrentText,
            ASPECT_RATIO = itm.AspectRatioCombo.CurrentText,
            OUTPUT_FORMAT = itm.OutputFormatCombo.CurrentText,
            MODEL_V2 = model_id ,
            SEED = newseed,
            OUTPUT_DIRECTORY = itm.Path.Text,

        }
        -- 执行图片生成和加载操作
        local image_path  = ''
        image_path =  Generate_Image_V2(settings)
        if image_path then
            if itm.DRCheckBox.Checked then
                AddToMediaPool(image_path)  
            else
                loadImageInFusion(image_path)
            end
        end
    elseif itm.MyTabs.CurrentIndex == 0 then 
        local newseed
        if itm.RandomSeed.Checked then
            newseed = math.random(0, 4294967295)
        else
            newseed = tonumber(itm.Seed.Text) or 0 
        end
        itm.Seed.Text = tostring(newseed) -- 更新界面上的显示
        local settings = {
        --    USE_DR = itm.DRCheckBox.Checked,
            API_KEY = itm.ApiKey.Text,
            PROMPT_V1 = itm.PromptTxt.PlainText,
            SAMPLER = itm.SamplerCombo.CurrentText,
            CFG_SCALE = tonumber(itm.CfgScale.Text),
            HEIGHT = tonumber(itm.Height.Text),
            WIDTH = tonumber(itm.Width.Text),
            STYLE_PRESET_V1 = itm.StyleComboV1.CurrentText,
            SAMPLES = tonumber(itm.Samples.Text),
            STEPS = tonumber(itm.Steps.Text),
            SEED = newseed,
            OUTPUT_DIRECTORY =  itm.Path.Text 
    
        }
    
        -- 执行图片生成和加载操作
        local image_path  = ''
        image_path =  Generate_Image_V1(settings,engine_id)
        if image_path then
            if itm.DRCheckBox.Checked then
                AddToMediaPool(image_path)  
            else
                loadImageInFusion(image_path)
            end
        end
    end


end


function CloseAndSave()

    local settings = {
        USE_DR = itm.DRCheckBox.Checked,
        USE_FU = itm.FUCheckBox.Checked,
        API_KEY = itm.ApiKey.Text,
        PROMPT_V2 = itm.PromptTxtV2.PlainText,
        NEGATIVE_PROMPT = itm.NegativePromptTxt.PlainText,
        STYLE_PRESET = itm.StyleCombo.CurrentIndex,
        STYLE_PRESET_V1 = itm.StyleComboV1.CurrentIndex,
        SEED_V2 = tonumber(itm.SeedV2.Text),
        ASPECT_RATIO = itm.AspectRatioCombo.CurrentIndex,
        OUTPUT_FORMAT = itm.OutputFormatCombo.CurrentIndex,
        MODEL_V2 = itm.ModelComboV2.CurrentIndex ,
        USE_RANDOM_SEED_V2 = itm.RandomSeedV2.Checked,
        OUTPUT_DIRECTORY = itm.Path.Text,
        PROMPT_V1 = itm.PromptTxt.PlainText,
        SEED = tonumber(itm.Seed.Text),
        CFG_SCALE = tonumber(itm.CfgScale.Text),
        HEIGHT = tonumber(itm.Height.Text),
        WIDTH = tonumber(itm.Width.Text),
        SAMPLER = itm.SamplerCombo.CurrentIndex,
        MODEL_V1 = itm.ModelCombo.CurrentIndex ,
        SAMPLES = tonumber(itm.Samples.Text),
        STEPS = tonumber(itm.Steps.Text),
        USE_RANDOM_SEED_V1 = itm.RandomSeed.Checked

    }

    saveSettings(settings)

end

function win.On.HelpButton.Clicked(ev)
    local helpmsg
    local helpmsg2 = [[ 
      
        <h2>Negative_Prompt</h2>
        <p>This parameter does not work with SD3-Turbo model.</p>

        <h2>Style_Preset</h2>
        <p>This parameter is applicable exclusively to the Core model.</p>


        ]]
    local helpmsg1 =  [[ 
      
        <h2>Using SDXL 1.0</h2>
        <p>When using SDXL 1.0, ensure the height and width you input match one of the following combinations:</p>
        <ul>
            <li>1024x1024</li>
            <li>1152x896</li>
            <li>896x1152</li>
            <li>1216x832</li>
            <li>1344x768</li>
            <li>768x1344</li>
            <li>1536x640</li>
            <li>640x1536</li>
        </ul>
        
        <h2>Using SD 1.6</h2>
        <p>When using SD 1.6, ensure the height and width you pass in adhere to the following restrictions:</p>
        <ul>
            <li>No dimension can be less than 320 pixels</li>
            <li>No dimension can be greater than 1536 pixels</li>
        </ul>]]
    if itm.MyTabs.CurrentIndex == 1 then
        helpmsg = helpmsg2
    elseif itm.MyTabs.CurrentIndex == 0 then 
        helpmsg = helpmsg1
    end


    local msgbox = disp:AddWindow({

        ID = 'msg',
        WindowTitle = 'Help',
        Geometry = {400, 300, 300, 300},
        Spacing = 10,

        ui:VGroup {

            ui:TextEdit{ID='HelpTxt', Text = helpmsg,ReadOnly = true,            

            },

        },

     })

    function msgbox.On.msg.Close(ev)
        disp:ExitLoop() 
    end
    msgbox:Show()
    disp:RunLoop() 
    msgbox:Hide()
    return
end


function win.On.ResetButton.Clicked(ev)
    itm.DRCheckBox.Checked = defaultSettings.USE_DR
    itm.FUCheckBox.Checked = defaultSettings.USE_FU
    --itm.ApiKey.Text = defaultSettings.API_KEY
    itm.Path.ReadOnly = false
    itm.Path.PlaceholderText = ''
    --itm.Path.Text = defaultSettings.OUTPUT_DIRECTORY
       
    if itm.MyTabs.CurrentIndex == 1 then
       
        itm.PromptTxtV2.PlainText = defaultSettings.PROMPT_V2
        itm.NegativePromptTxt.PlainText = defaultSettings.NEGATIVE_PROMPT
        itm.StyleCombo.CurrentIndex = defaultSettings.STYLE_PRESET
        itm.SeedV2.Text = defaultSettings.SEED
        itm.ModelComboV2.CurrentIndex = defaultSettings.MODEL_V2
        itm.OutputFormatCombo.CurrentIndex = defaultSettings.OUTPUT_FORMAT
        itm.AspectRatioCombo.CurrentIndex = defaultSettings.ASPECT_RATIO
        itm.RandomSeedV2.Checked = defaultSettings.USE_RANDOM_SEED_V2

    elseif itm.MyTabs.CurrentIndex == 0 then 
        itm.PromptTxt.PlainText = defaultSettings.PROMPT_V1
        itm.ModelCombo.CurrentIndex = defaultSettings.MODEL_V1
        itm.SamplerCombo.CurrentIndex = defaultSettings.SAMPLER
        itm.StyleComboV1.CurrentIndex = defaultSettings.STYLE_PRESET_V1
        itm.Seed.Text = defaultSettings.SEED
        itm.CfgScale.Text = defaultSettings.CFG_SCALE
        itm.Height.Text = defaultSettings.HEIGHT
        itm.Width.Text = defaultSettings.WIDTH
        itm.Samples.Text = defaultSettings.SAMPLES
        itm.Steps.Text = defaultSettings.STEPS
        itm.RandomSeed.Checked = defaultSettings.USE_RANDOM_SEED_V1
    end
    updateStatus(" ")
end

function win.On.MyWin.Close(ev)

    disp:ExitLoop()
    CloseAndSave()

end
function win.On.MyTabs.CurrentChanged(ev)
    itm.MyStack.CurrentIndex = ev.Index
end
function win.On.Balance.Clicked(ev)
    local api_key = itm.ApiKey.Text
    local credits
    local status, err = pcall(function()
        credits = get_remaining_credits(api_key)
    end)

    if status then
        itm["BalanceLabel"].Text = "Credits: " .. credits
        print("Credits: " .. credits)
    else
        itm["BalanceLabel"].Text = "Invalid API key"
        print("发生错误: " .. err)
    end
end

function win.On.Browse.Clicked(ev)
    local currentPath = itm.Path.Text
    local selectedPath = fu:RequestDir(currentPath)
    if selectedPath then
        itm.Path.Text = tostring(selectedPath)
    else
        print("No directory selected or the request failed.")
    end
end

-- 显示窗口
win:Show()
disp:RunLoop()
win:Hide()
 
