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
    return mediaPool:ImportMedia(mappedPath, aiImageFolder:GetName())
end

function loadImageInFusion(image_path)

    comp:Lock()
    local loader = comp:AddTool("Loader")
    loader.Clip[comp.CurrentTime] = image_path
    loader:SetAttrs({TOOLS_RegenerateCache = true})
    comp:Unlock()

end

function Generate_Stable_Image(settings)
    updateStatus("Generating image...")
    local count = 0
    local output_file
    local file_exists
    repeat
        count = count + 1
        local output_directory = settings.output_directory
        if os_name == '\\' then
            if output_directory:sub(-1) ~= "\\" then
                output_directory = output_directory .. "\\"
            end
            output_file = output_directory .. "image" .. tostring(settings.seed) .. tostring(count) .. "a" ..".".. settings.output_format
            output_file = output_file:gsub("\\", "\\\\")
        else
            if output_directory:sub(-1) ~= "/" then
                output_directory = output_directory .. "/"
            end
            output_file = output_directory .. "image" .. tostring(settings.seed) .. tostring(count) .. "a" ..".".. settings.output_format
        end
        local file = io.open(output_file, "r")
        file_exists = file ~= nil
        if file then file:close() end
    until not file_exists

    local url
    local curl_command

    if settings.model == "core" then
        url = "https://api.stability.ai/v2beta/stable-image/generate/core"
        curl_command = string.format(
            'curl -f -sS -X POST "%s" ' ..
            '-H "Authorization: Bearer %s" ' ..
            '-H "Accept: image/*" ' ..
            '-F mode="text-to-image" ' ..
            '-F prompt="%s" ' ..
            '-F negative_prompt="%s" ' ..
            '-F seed=%d ' ..
            '-F aspect_ratio="%s" ' ..
            '-F output_format="%s" ',
            url,
            settings.api_key,
            settings.prompt:gsub('"', '\\"'):gsub("'", '\\"'),  -- Escape double quotes in the prompt
            settings.negative_prompt:gsub('"', '\\"'):gsub("'", '\\"'),  -- Escape double quotes in the negative prompt
            settings.seed,
            settings.aspect_ratio,
            settings.output_format
        )
        if settings.style_preset ~= '' then
            curl_command = curl_command .. string.format('-F style_preset="%s" ', settings.style_preset)
        end
        
        curl_command = curl_command .. string.format('-o "%s"', output_file)

    elseif settings.model == "sd3" or settings.model == "sd3-turbo" then
        url = "https://api.stability.ai/v2beta/stable-image/generate/sd3"
        curl_command = string.format(
            'curl -f -sS -X POST "%s" ' ..
            '-H "Authorization: Bearer %s" ' ..
            '-H "Accept: image/*" ' ..
            '-F mode="text-to-image" ' ..
            '-F prompt="%s" ' ..
            '-F negative_prompt="%s" ' ..
            '-F seed=%d ' ..
            '-F aspect_ratio="%s" ' ..
            '-F output_format="%s" ' ..
            '-F model="%s" ' ..
            '-o "%s"',
            url,
            settings.api_key,
            settings.prompt:gsub('"', '\\"'):gsub("'", '\\"'),  -- Escape double quotes in the prompt
            settings.negative_prompt:gsub('"', '\\"'):gsub("'", '\\"'),  -- Escape double quotes in the negative prompt
            settings.seed,
            settings.aspect_ratio,
            settings.output_format,
            settings.model,
            output_file
        )

    else
        updateStatus("Invalid model specified.")
        return nil
    end
    print("Executing command: " .. curl_command)
    print("\nPrompt:",settings.prompt,"\nNegative_Prompt:",settings.negative_prompt,"\nStyle_Preset:",settings.style_preset,"\nSeed:",settings.seed,"\nAspect_Ratio:",settings.aspect_ratio,"\nOutput_Format:",settings.output_format,"\nFile_Name:",output_file)
    print("Generating image...")

    local success, _, exit_status = os.execute(curl_command)
    if success and exit_status == 0 then
        updateStatus("Image generated successfully.")
        print("["..exit_status.."]".."Success".."\noutput_file:"..output_file)
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
    settings_file = script_path .. '\\Stable_Image_Generate_settings.json' 
else
    settings_file = script_path .. '/Stable_Image_Generate_settings.json' 
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

    use_dr = true,
    use_fu = false,
    api_key = '',
    prompt = '',
    negative_prompt= '',
    style_preset = 0,
    aspect_ratio= 0 ,
    model = 0,
    seed = '0',
    output_format = 0,
    use_random_seed = true,
    output_directory = '',

}

local win = disp:AddWindow({

    ID = 'MyWin',
    WindowTitle = 'Stable Image Generate Version 1.0',
    Geometry = {700, 300, 400, 470},
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
            ui:LineEdit {ID = 'ApiKey', Text = '',  EchoMode = 'Password',Weight = 0.8},    

        },
        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'PathLabel', Text = 'Save Path',Alignment = { AlignRight = false },Weight = 0.2},
            ui:Button{ ID = 'Browse', Text = 'Browse', Weight = 0.2, },
            ui:LineEdit {ID = 'Path', Text = '', PlaceholderText = '',ReadOnly = false ,Weight = 0.6},
            
        },
        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'ModelLabel', Text = 'Model',Alignment = { AlignRight = false },Weight = 0.2},
            ui:ComboBox{ID = 'ModelCombo', Text = 'Model',Weight = 0.8},

        },
        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'PromptLabel', Text = 'Prompt',Alignment = { AlignRight = false },Weight = 0.2},
            ui:TextEdit{ID='PromptTxt', Text = '', PlaceholderText = 'Please Enter a Prompt.',Weight = 0.8}

        },
        
        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'NegativePromptLabel', Text = 'Negative',Alignment = { AlignRight = false },Weight = 0.2},
            ui:TextEdit{ID='NegativePromptTxt', Text = ' ', PlaceholderText = 'Please Enter a Negative Prompt.',Weight = 0.8}

        },
        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'StyleLabel', Text = 'Style_Preset',Alignment = { AlignRight = false },Weight = 0.2},
            ui:ComboBox{ID = 'StyleCombo', Text = 'Style_Preset',Weight = 0.8},

        },
        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'AspectRatioLabel', Text = 'Aspect Ratio',Alignment = { AlignRight = false },Weight = 0.2},
            ui:ComboBox{ID = 'AspectRatioCombo', Text = 'aspect_ratio',Weight = 0.8},

        },
        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'OutputFormatLabel', Text = 'Format',Alignment = { AlignRight = false },Weight = 0.2},
            ui:ComboBox{ID = 'OutputFormatCombo', Text = 'Output_Format',Weight = 0.8},

        },
        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'SeedLabel', Text = 'Seed',  Alignment = { AlignRight = false },Weight = 0.2},
            ui:LineEdit {ID = 'Seed', Text = '0',Weight = 0.8},

        },

        ui:HGroup {

            Weight = 1,
            ui:Button {ID = 'HelpButton', Text = 'Help'},
            ui:CheckBox {

                ID = 'RandomSeed',
                Text = 'Use Random Seed',
                Checked = true, 
        
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

local MOdel = {'Core','SD3','SD3 Turbo'}
for _, modeL in ipairs(MOdel) do
    itm.ModelCombo:AddItem(modeL)
end

local stylePreset ={'','3d-model','analog-film','anime','cinematic','comic-book','digital-art','enhance','fantasy-art','isometric','line-art','low-poly','modeling-compound','neon-punk','origami','photographic','pixel-art','tile-texture',}
for _, style in ipairs(stylePreset) do
    itm.StyleCombo:AddItem(style)
end

local aspectRatios = {'1:1', '16:9', '21:9', '2:3', '3:2', '4:5', '5:4', '9:16', '9:21'}
for _, ratio in ipairs(aspectRatios) do
    itm.AspectRatioCombo:AddItem(ratio)
end

local outputFormat = {'png','jpeg',}
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

local model_id
function win.On.ModelCombo.CurrentIndexChanged(ev)
    itm.NegativePromptTxt.ReadOnly = false
    for _, style in ipairs(stylePreset) do
        itm.StyleCombo:RemoveItem(0)
    end
    if itm.ModelCombo.CurrentIndex == 0 then
        model_id = 'core'
        print('Using Model:' .. model_id)
        for _, style in ipairs(stylePreset) do
            itm.StyleCombo:AddItem(style)
        end
    elseif itm.ModelCombo.CurrentIndex == 1 then
        model_id = 'sd3'
        print('Using Model:' .. model_id)
    elseif itm.ModelCombo.CurrentIndex == 2 then
        itm.NegativePromptTxt.ReadOnly = true
        itm.NegativePromptTxt.Text = ''
        model_id = 'sd3-turbo'
        print('Using Model:' .. model_id )
    end
end

function win.On.AspectRatioCombo.CurrentIndexChanged(ev)
    print('Using Aspect_Ratio:' .. itm.AspectRatioCombo.CurrentText )
end

function win.On.OutputFormatCombo.CurrentIndexChanged(ev)
    print('Using Output_Format:' .. itm.OutputFormatCombo.CurrentText )
end

function win.On.OpenLinkButton.Clicked(ev)
    bmd.openurl("https://www.paypal.me/HEIBAWK")
end

function updateStatus(message)
    itm.StatusLabel.Text = message
end

if savedSettings then
    itm.DRCheckBox.Checked = savedSettings.use_dr == nil and defaultSettings.use_dr or savedSettings.use_dr
    itm.FUCheckBox.Checked = savedSettings.use_fu == nil and defaultSettings.use_fu or savedSettings.use_fu
    itm.ApiKey.Text = savedSettings.api_key or defaultSettings.api_key
    itm.PromptTxt.PlainText = savedSettings.prompt or defaultSettings.prompt
    itm.NegativePromptTxt.PlainText = savedSettings.negative_prompt or defaultSettings.negative_prompt
    itm.StyleCombo.CurrentIndex = savedSettings.style_preset or defaultSettings.style_preset
    itm.Seed.Text = tostring(savedSettings.seed or defaultSettings.seed)
    itm.RandomSeed.Checked = savedSettings.use_random_seed 
    itm.ModelCombo.CurrentIndex = savedSettings.model or defaultSettings.model
    itm.AspectRatioCombo.CurrentIndex = savedSettings.aspect_ratio or defaultSettings.aspect_ratio
    itm.OutputFormatCombo.CurrentIndex = savedSettings.output_format or defaultSettings.output_format
    itm.Path.Text = savedSettings.output_directory or  defaultSettings.output_directory

end


function win.On.GenerateButton.Clicked(ev)
    if itm.Path.Text == '' then
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

    local newseed
    if itm.RandomSeed.Checked then
        newseed = math.random(0, 4294967295)
    else
        newseed = tonumber(itm.Seed.Text) or 0 -- 如果输入无效，默认为0
    end

    itm.Seed.Text = tostring(newseed) -- 更新界面上的显示

    local settings = {
        
        use_dr = itm.DRCheckBox.Checked,
        api_key = itm.ApiKey.Text,
        prompt = itm.PromptTxt.PlainText,
        negative_prompt = itm.NegativePromptTxt.PlainText,
        style_preset = itm.StyleCombo.CurrentText,
        aspect_ratio = itm.AspectRatioCombo.CurrentText,
        output_format = itm.OutputFormatCombo.CurrentText,
        model = model_id ,
        seed = newseed,
        output_directory = itm.Path.Text,

    }
    -- 执行图片生成和加载操作
    local image_path  = ''
    image_path =  Generate_Stable_Image(settings)
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
        negative_prompt = itm.NegativePromptTxt.PlainText,
        style_preset = itm.StyleCombo.CurrentIndex,
        seed = tonumber(itm.Seed.Text),
        aspect_ratio = itm.AspectRatioCombo.CurrentIndex,
        output_format = itm.OutputFormatCombo.CurrentIndex,
        model = itm.ModelCombo.CurrentIndex ,
        use_random_seed = itm.RandomSeed.Checked,
        output_directory = itm.Path.Text,

    }

    saveSettings(settings)

end

function win.On.HelpButton.Clicked(ev)
    local msgbox = disp:AddWindow({

        ID = 'msg',
        WindowTitle = 'Help',
        Geometry = {400, 300, 300, 300},
        Spacing = 10,

        ui:VGroup {

            ui:TextEdit{ID='HelpTxt', Text = [[ 
            <h2>API_Key</h2>
            <p>Obtain your API key from <a href="https://stability.ai">stability.ai</a></p>
            
            <h2>Negative_Prompt</h2>
            <p>This parameter does not work with SD3-Turbo model.</p>

            <h2>Style_Preset</h2>
            <p>This parameter is applicable exclusively to the Core model.</p>


            ]],ReadOnly = true,            

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
    itm.DRCheckBox.Checked = defaultSettings.use_dr
    itm.FUCheckBox.Checked = defaultSettings.use_fu
    itm.ApiKey.Text = defaultSettings.api_key
    itm.PromptTxt.PlainText = defaultSettings.prompt
    itm.Path.ReadOnly = false
    itm.Path.PlaceholderText = ''
    itm.NegativePromptTxt.PlainText = defaultSettings.negative_prompt
    itm.StyleCombo.CurrentIndex = defaultSettings.style_preset
    itm.Seed.Text = defaultSettings.seed
    itm.ModelCombo.CurrentIndex = defaultSettings.model
    itm.OutputFormatCombo.CurrentIndex = defaultSettings.output_format
    itm.AspectRatioCombo.CurrentIndex = defaultSettings.aspect_ratio
    itm.RandomSeed.Checked = defaultSettings.use_random_seed
    itm.Path.Text = defaultSettings.output_directory
    updateStatus(" ")
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

-- 显示窗口
win:Show()
disp:RunLoop()
win:Hide()
