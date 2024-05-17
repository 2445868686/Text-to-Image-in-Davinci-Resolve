local ui = fu.UIManager
local disp = bmd.UIDispatcher(ui)
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
    return mediaPool:ImportMedia(mappedPath, aiImageFolder:GetName())
end

function loadImageInFusion(image_path)

    comp:Lock()
    local loader = comp:AddTool("Loader")
    loader.Clip[comp.CurrentTime] = image_path
    loader:SetAttrs({TOOLS_RegenerateCache = true})
    comp:Unlock()

end

-- 使用 curl 调用 Stability AI API 的函数
function generateImageFromStabilityAI(settings,engine_id)
    updateStatus("Generating image...")

    local url = "https://api.stability.ai/v1/generation/"..engine_id.."/text-to-image"
    local count = 0
    local output_file
    local file_exists
   -- print("api:",settings.api_key,"\nPrompt:",settings.prompt,"\nSeed:",settings.seed,"\ncfg:",settings.cfg_scale,"\nsampler:",settings.sampler,"\nwidth:",settings.width,"\nheight:",settings.height,"\nsamples:",settings.samples,"\nsteps:",settings.steps)
    
    repeat
        count = count + 1

        local output_directory = settings.output_directory
        if os_name == '\\' then
            if output_directory:sub(-1) ~= "\\" then
                output_directory = output_directory .. "\\"
            end
            output_file = output_directory .. "image" .. tostring(settings.seed) .. tostring(count) .. "a" .. ".png"
            output_file = output_file:gsub("\\", "\\\\")
        else
            if output_directory:sub(-1) ~= "/" then
                output_directory = output_directory .. "/"
            end
            output_file = output_directory .. "image" .. tostring(settings.seed) .. tostring(count) .. "a" .. ".png"
        end
        local file = io.open(output_file, "r")
        file_exists = file ~= nil
        if file then file:close() end
    until not file_exists

    
    local data = {
        text_prompts = {{
            text = settings.prompt:gsub('"', '\\"'):gsub("'", '\\"')
        }},
        cfg_scale = settings.cfg_scale,
        height = settings.height,
        width = settings.width,
        samples = settings.samples,
        steps = settings.steps,
        seed = settings.seed,
        sampler = settings.sampler
    }
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
        url, settings.api_key, data_str, output_file
     )
    else
        curl_command = string.format(
            'curl -v -f -X POST "%s" ' ..
            '-H "Content-Type: application/json" ' ..
            '-H "Accept: image/png" ' ..
            '-H "Authorization: Bearer %s" ' ..
            '--data-raw \'%s\' -o "%s"',
            url,settings.api_key,data_str,output_file
        )
    end

    print("Executing command: " .. curl_command)
    print("\nPrompt:",settings.prompt,"\nSeed:",settings.seed,"\ncfg:",settings.cfg_scale,"\nsampler:",settings.sampler,"\nwidth:",settings.width,"\nheight:",settings.height,"\nsamples:",settings.samples,"\nsteps:",settings.steps,"\nFile_Name:",output_file)
    print("Generating image...")
    
    -- 执行 curl 命令，并获取返回状态
    local success, _, exit_status = os.execute(curl_command)

    if success and exit_status == 0 then
        updateStatus("Image generated successfully.")
        print("["..exit_status.."]".."Image generated successfully.".."\noutput_file:"..output_file)
        return output_file
    else
        updateStatus("Failed to generate image"..exit_status)
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
    settings_file = script_path .. '\\SD1_settings.json' 
else
    settings_file = script_path .. '/SD1_settings.json' 
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



local defaultSettings = {

    use_dr = true,
    use_fu = false,
    output_directory= '',
    api_key = '',
    prompt = '',
    seed = '0',
    cfg_scale = '7',
    height = '512',
    width = '512',
    sampler = 0,
    samples = '1',
    steps = '30',
    use_random_seed = true,
    model = 0,

}
local savedSettings = loadSettings() -- 尝试加载已保存的设置

local win = disp:AddWindow({

    ID = 'MyWin',
    WindowTitle = 'Text to Image SD Version 1.0',
    Geometry = {700, 300, 400, 450},
    Spacing = 10,
    
    ui:VGroup {

        ID = 'root',
        ui:HGroup {

            Weight = 1,
            ui:CheckBox {ID = 'DRCheckBox',Text = 'Use In DavVnci Resolve',Checked = true,Weight = 0.5},
            ui:CheckBox {ID = 'FUCheckBox',Text = 'Use In Fusion Studio',Checked = false,Weight = 0.5},

        },
        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'ApiKeyLabel', Text = 'API Key',Alignment = { AlignRight = false },Weight = 0.2},
            ui:LineEdit {ID = 'ApiKey', Text = '', EchoMode = 'Password',Weight = 0.8},
        
        },
        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'PathLabel', Text = 'Save Path',Alignment = { AlignRight = false },Weight = 0.2},
            ui:Button{ ID = 'Browse', Text = 'Browse', Weight = 0.2, },
            ui:LineEdit {ID = 'Path', Text = '', PlaceholderText = '',ReadOnly = false ,Weight = 0.6},
 
        },

        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'PromptLabel', Text = 'Prompt',Alignment = { AlignRight = false },Weight = 0.2},
            ui:TextEdit{ID='PromptTxt', Text = '', PlaceholderText = 'Please Enter a Prompt',Weight = 0.8}

        },
        
        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'ModelLabel', Text = 'Model',Alignment = { AlignRight = false },Weight = 0.2},
            ui:ComboBox{ID = 'ModelCombo', Text = 'Model',Weight = 0.8},

        },

        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'ResolutionLabel', Text = 'Resolution',Alignment = { AlignRight = false },Weight = 0.2,},
            ui:LineEdit {ID = 'Width', Text = '1024',Weight = 0.4,},
            ui:LineEdit {ID = 'Height', Text = '1024',Weight = 0.4,},
        
        },

        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'CfgScaleLabel', Text = 'Cfg Scale',Alignment = { AlignRight = false },Weight = 0.2},
            ui:LineEdit {ID = 'CfgScale', Text = '7',Weight = 0.8},

        },

        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'SamplerLabel', Text = 'Sampler',Alignment = { AlignRight = false },Weight = 0.2},
            ui:ComboBox{ID = 'SamplerCombo', Text = 'Sampler',Weight = 0.8},

        },
        
        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'SamplesLabel', Text = 'Samples',Alignment = { AlignRight = false },Weight = 0.2},
            ui:LineEdit {ID = 'Samples', Text = '1',Weight = 0.8},

        },

        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'StepsLabel', Text = 'Steps',Alignment = { AlignRight = false },Weight = 0.2},
            ui:LineEdit {ID = 'Steps', Text = '30',Weight = 0.8},

        },

        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'SeedLabel', Text = 'Seed',  Alignment = { AlignRight = false },Weight = 0.2},
            ui:LineEdit {ID = 'Seed', Text = '0',Weight = 0.8},

        },

        ui:HGroup {

            Weight = 1,
            ui:Button {ID = 'HelpButton', Text = 'Help'},
            ui:CheckBox {ID = 'RandomSeed',Text = 'Use Random Seed',Checked = true, 
        
            },

        },

        ui:HGroup {

            Weight = 0,
            ui:Button {ID = 'GenerateButton', Text = 'Generate'},
            ui:Button {ID = 'ResetButton', Text = 'Reset'},

        },

        ui:HGroup {

            Weight = 0,
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
            Weight = 0.3
        },

    },

})

itm = win:GetItems()

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

function win.On.OpenLinkButton.Clicked(ev)
    bmd.openurl("https://www.paypal.me/heiba2wk")
end

function updateStatus(message)
    itm.StatusLabel.Text = message
end

if savedSettings then
    itm.DRCheckBox.Checked = savedSettings.use_dr == nil and defaultSettings.use_dr or savedSettings.use_dr
    itm.FUCheckBox.Checked = savedSettings.use_fu == nil and defaultSettings.use_fu or savedSettings.use_fu
    itm.ApiKey.Text = savedSettings.api_key or defaultSettings.api_key
    itm.PromptTxt.PlainText = savedSettings.prompt or defaultSettings.prompt
    itm.Seed.Text = tostring(savedSettings.seed or defaultSettings.seed)
    itm.CfgScale.Text = tostring(savedSettings.cfg_scale or defaultSettings.cfg_scale)
    itm.Height.Text = tostring(savedSettings.height or defaultSettings.height)
    itm.Width.Text = tostring(savedSettings.width or defaultSettings.width)
    itm.Path.Text = savedSettings.output_directory or defaultSettings.output_directory
    itm.Samples.Text = tostring(savedSettings.samples or defaultSettings.samples)
    itm.Steps.Text = tostring(savedSettings.steps or defaultSettings.steps)
    itm.RandomSeed.Checked = savedSettings.use_random_seed 
    itm.ModelCombo.CurrentIndex = savedSettings.model or defaultSettings.model
    itm.SamplerCombo.CurrentIndex = savedSettings.sampler or defaultSettings.sampler
end


function win.On.GenerateButton.Clicked(ev)
    if itm.Path.Text == '' then
        local current_file_path = comp:GetAttrs().COMPS_FileName
        if not current_file_path or current_file_path == '' then
            local msgbox = disp:AddWindow({
                ID = 'msg',
                WindowTitle = 'Warning',
                Geometry = {750, 400, 300, 100},
                Spacing = 10,
                ui:VGroup {
                    ui:Label {ID = 'WarningLabel', Text = 'Please select the image save path.',  },
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
            return
        end
    end

    local newseed
    if itm.RandomSeed.Checked then
        newseed = math.random(0, 4294967295)
    else
        newseed = tonumber(itm.Seed.Text) or 0 
    end
    itm.Seed.Text = tostring(newseed) -- 更新界面上的显示
    local settings = {
    --    use_dr = itm.DRCheckBox.Checked,
        api_key = itm.ApiKey.Text,
        prompt = itm.PromptTxt.PlainText,
        sampler = itm.SamplerCombo.CurrentText,
        cfg_scale = tonumber(itm.CfgScale.Text),
        height = tonumber(itm.Height.Text),
        width = tonumber(itm.Width.Text),
        samples = tonumber(itm.Samples.Text),
        steps = tonumber(itm.Steps.Text),
        seed = newseed,
        output_directory =  itm.Path.Text 

    }

    -- 执行图片生成和加载操作
    local image_path  = ''
    image_path =  generateImageFromStabilityAI(settings,engine_id)
    if image_path then
        if itm.DRCheckBox.Checked then
            AddToMediaPool(image_path)  
        else
            loadImageInFusion(image_path)
        end
    end
end

function CloseAndSave()
    local settings = {
        use_dr = itm.DRCheckBox.Checked,
        use_fu = itm.FUCheckBox.Checked,
        api_key = itm.ApiKey.Text,
        prompt = itm.PromptTxt.PlainText,
        seed = tonumber(itm.Seed.Text),
        cfg_scale = tonumber(itm.CfgScale.Text),
        height = tonumber(itm.Height.Text),
        width = tonumber(itm.Width.Text),
        output_directory = itm.Path.Text,
        sampler = itm.SamplerCombo.CurrentIndex,
        model = itm.ModelCombo.CurrentIndex ,
        samples = tonumber(itm.Samples.Text),
        steps = tonumber(itm.Steps.Text),
        use_random_seed = itm.RandomSeed.Checked

    }
    saveSettings(settings)
end


function win.On.ResetButton.Clicked(ev)
    itm.DRCheckBox.Checked = defaultSettings.use_dr
    itm.FUCheckBox.Checked = defaultSettings.use_fu
    itm.ApiKey.Text = defaultSettings.api_key
    itm.PromptTxt.PlainText = defaultSettings.prompt
    itm.Path.ReadOnly = false
    itm.Path.PlaceholderText = ''
    itm.ModelCombo.CurrentIndex = defaultSettings.model
    itm.SamplerCombo.CurrentIndex = defaultSettings.sampler
    itm.Seed.Text = defaultSettings.seed
    itm.Path.Text = defaultSettings.output_directory
    itm.CfgScale.Text = defaultSettings.cfg_scale
    itm.Height.Text = defaultSettings.height
    itm.Width.Text = defaultSettings.width
    itm.Samples.Text = defaultSettings.samples
    itm.Steps.Text = defaultSettings.steps
    itm.RandomSeed.Checked = defaultSettings.use_random_seed
    updateStatus(" ")

end

function win.On.HelpButton.Clicked(ev)
    local msgbox = disp:AddWindow({

        ID = 'msg',
        WindowTitle = 'Help',
        Geometry = {400, 300, 300, 300},
        Spacing = 10,

        ui:VGroup {

            -- 显示警告信息
            ui:TextEdit{ID='HelpTxt', Text = [[ 
            <h2>API_Key</h2>
            <p>Obtain your API key from <a href="https://stability.ai">stability.ai</a></p>
            
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
            </ul>]],ReadOnly = true,            

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

function win.On.MyWin.Close(ev)

    disp:ExitLoop()
    CloseAndSave()

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

win:Show()

disp:RunLoop()

win:Hide()
