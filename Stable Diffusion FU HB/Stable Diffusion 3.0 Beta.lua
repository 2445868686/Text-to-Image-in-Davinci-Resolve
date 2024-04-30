local ui = fu.UIManager
local disp = bmd.UIDispatcher(ui)
local comp = fusion:GetCurrentComp()
local math = require("math")
local json = require('dkjson')

math.randomseed(os.time())

local os_name = package.config:sub(1,1)  

-- 使用 curl 调用 Stability AI API 的函数
function generateImageFromStabilityAI(settings)
    updateStatus("Generating image...")

    local url = "https://api.stability.ai/v2beta/stable-image/generate/sd3"
    local count = 0
    local output_file
    local file_exists

    repeat
        count = count + 1
        if os_name == '\\' then
            output_file = settings.output_directory:sub(1, -2) .. "\\image" .. tostring(settings.seed) ..tostring(count).. "a" .. "."..settings.output_format
            output_file = output_file:gsub("\\", "\\\\")
        else
            output_file = settings.output_directory:sub(1, -2) .. "/image" .. tostring(settings.seed) ..  tostring(count) .. "a" .."."..settings.output_format
        end

        local file = io.open(output_file, "r")
        file_exists = file ~= nil
        if file then file:close() end
    until not file_exists

    print( settings.model)

    local curl_command = string.format(
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
    

    print("Executing command: " .. curl_command)
   -- print("api:",settings.api_key,"\nPrompt:",settings.prompt,"\nSeed:",settings.seed,"\ncfg:",settings.cfg_scale,"\nsampler:",settings.sampler,"\nwidth:",settings.width,"\nheight:",settings.height,"\nsamples:",settings.samples,"\nsteps:",settings.steps)
    print("Generating image...")
    
    -- 执行 curl 命令，并获取返回状态
    local success, _, exit_status = os.execute(curl_command)

    if success and exit_status == 0 then
        updateStatus("Image generated successfully.")
        print("["..exit_status.."]".."Success".."output_file:"..output_file)
        loadImageInFusion(output_file)
    else
        updateStatus("Failed to generate image"..exit_status)
        print("[error]"..exit_status)
    end
end

function loadImageInFusion(image_path)

    comp:Lock()
    local loader = comp:AddTool("Loader")
    loader.Clip[comp.CurrentTime] = image_path
    loader:SetAttrs({TOOLS_RegenerateCache = true})
    comp:Unlock()

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
    settings_file = script_path .. '\\SD3_settings.json' 
else
    settings_file = script_path .. '/SD3_settings.json' 
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

    api_key = '',
    prompt = '',
    negative_prompt= '',
    aspect_ratio= 0 ,
    model = 0,
    seed = '0',
    output_format = 0,
    use_random_seed = true,

}

-- 创建窗口
local win = disp:AddWindow({

    ID = 'MyWin',
    WindowTitle = 'Text to Image SD3',
    Geometry = {100, 100, 400, 400},
    Spacing = 10,

    ui:VGroup {

        ID = 'root',

        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'ApiKeyLabel', Text = 'API Key',Alignment = { AlignRight = false },Weight = 0.2},
            ui:LineEdit {ID = 'ApiKey', Text = '',  EchoMode = 'Password',Weight = 0.8},    

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
            ui:Label {ID = 'AspectRatioLabel', Text = 'Aspect Ratio',Alignment = { AlignRight = false },Weight = 0.2},
            ui:ComboBox{ID = 'AspectRatioCombo', Text = 'aspect_ratio',Weight = 0.8},

        },
        ui:HGroup {

            Weight = 1,
            ui:Label {ID = 'ModelLabel', Text = 'Model',Alignment = { AlignRight = false },Weight = 0.2},
            ui:ComboBox{ID = 'ModelCombo', Text = 'Model',Weight = 0.8},

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
            --ui:Label {ID = 'CopyrightLabel', Text = '© 2024, Copyright by HB.'},

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

itm.ModelCombo:AddItem('SD3')
itm.ModelCombo:AddItem('SD3-Turbo')

itm.AspectRatioCombo:AddItem('1:1')
itm.AspectRatioCombo:AddItem('16:9')
itm.AspectRatioCombo:AddItem('21:9')
itm.AspectRatioCombo:AddItem('2:3')
itm.AspectRatioCombo:AddItem('3:2')
itm.AspectRatioCombo:AddItem('4:5')
itm.AspectRatioCombo:AddItem('5:4')
itm.AspectRatioCombo:AddItem('9:16')
itm.AspectRatioCombo:AddItem('9:21')

itm.OutputFormatCombo:AddItem('png')
itm.OutputFormatCombo:AddItem('jpeg')

local model_id
function win.On.ModelCombo.CurrentIndexChanged(ev)
    if itm.ModelCombo.CurrentIndex == 0 then
        model_id = 'sd3'
        print('Using Model:' .. model_id)
    else
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

    itm.ApiKey.Text = savedSettings.api_key or defaultSettings.api_key
    itm.PromptTxt.PlainText = savedSettings.prompt or defaultSettings.prompt
    itm.NegativePromptTxt.PlainText = savedSettings.negative_prompt or defaultSettings.negative_prompt
    itm.Seed.Text = tostring(savedSettings.seed or defaultSettings.seed)
    itm.RandomSeed.Checked = savedSettings.use_random_seed 
    itm.ModelCombo.CurrentIndex = savedSettings.model or defaultSettings.model
    itm.AspectRatioCombo.CurrentIndex = savedSettings.aspect_ratio or defaultSettings.aspect_ratio
    itm.OutputFormatCombo.CurrentIndex = savedSettings.output_format or defaultSettings.output_format
end


function win.On.GenerateButton.Clicked(ev)

    -- 检查当前合成文件是否已保存
    local current_file_path = comp:GetAttrs().COMPS_FileName
    
    if not current_file_path or current_file_path == '' then

        -- 文件未保存，显示警告对话框
        local msgbox = disp:AddWindow({

            ID = 'msg',
            WindowTitle = 'Warning',
            Geometry = {400, 300, 300, 100},
            Spacing = 10,

            ui:VGroup {

                ui:Label {ID = 'WarningLabel', Text = 'Please save your composition file first.',  },
                ui:HGroup {

                    Weight = 0,
                    ui:Button {ID = 'OkButton', Text = 'OK'},

                },

             },

        })

        -- 处理确定按钮点击事件
        function msgbox.On.OkButton.Clicked(ev)

            disp:ExitLoop()
        end

        msgbox:Show()
        disp:RunLoop() 
        msgbox:Hide()

    -- 由于文件未保存，终止后续操作
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

        api_key = itm.ApiKey.Text,
        prompt = itm.PromptTxt.PlainText,
        negative_prompt = itm.NegativePromptTxt.PlainText,
        aspect_ratio = itm.AspectRatioCombo.CurrentText,
        output_format = itm.OutputFormatCombo.CurrentText,
        model = model_id ,
        seed = newseed,
        output_directory = comp:GetAttrs().COMPS_FileName:match("(.+[\\/])") -- 获取当前合成文件的目录

    }
    print( settings.model)
    -- 执行图片生成和加载操作
    generateImageFromStabilityAI(settings)
    -- loadImageInFusion(image_path)
end


function CloseAndSave()

    local settings = {

        api_key = itm.ApiKey.Text,
        prompt = itm.PromptTxt.PlainText,
        negative_prompt = itm.NegativePromptTxt.PlainText,
        seed = tonumber(itm.Seed.Text),
        aspect_ratio = itm.AspectRatioCombo.CurrentIndex,
        output_format = itm.OutputFormatCombo.CurrentIndex,
        model = itm.ModelCombo.CurrentIndex ,
        use_random_seed = itm.RandomSeed.Checked

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
            <p>This parameter does not work with sd3-turbo.</p>
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

    itm.ApiKey.Text = defaultSettings.api_key
    itm.PromptTxt.PlainText = defaultSettings.prompt
    itm.NegativePromptTxt.PlainText = defaultSettings.negative_prompt
    itm.Seed.Text = defaultSettings.seed
    itm.ModelCombo.CurrentIndex = defaultSettings.model
    itm.OutputFormatCombo.CurrentIndex = defaultSettings.output_format
    itm.AspectRatioCombo.CurrentIndex = defaultSettings.aspect_ratio
    itm.RandomSeed.Checked = defaultSettings.use_random_seed
    updateStatus(" ")

end

function win.On.MyWin.Close(ev)

    disp:ExitLoop()
    CloseAndSave()

end

-- 显示窗口
win:Show()
disp:RunLoop()
win:Hide()