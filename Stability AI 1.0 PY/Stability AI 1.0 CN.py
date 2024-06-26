import json
import math
import os
import requests
import sys
import random
import platform
import webbrowser
try:
    import DaVinciResolveScript as dvr_script
    from python_get_resolve import GetResolve
    print("DaVinciResolveScript from Python")
except ImportError:
    
    if platform.system() == "Darwin": 
        resolve_script_path1 = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Examples"
        resolve_script_path2 = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
    elif platform.system() == "Windows": 
        resolve_script_path1 = os.path.join(os.environ['PROGRAMDATA'], "Blackmagic Design", "DaVinci Resolve", "Support", "Developer", "Scripting", "Examples")
        resolve_script_path2 = os.path.join(os.environ['PROGRAMDATA'], "Blackmagic Design", "DaVinci Resolve", "Support", "Developer", "Scripting", "Modules")
    else:
        raise EnvironmentError("Unsupported operating system")

    sys.path.append(resolve_script_path1)
    sys.path.append(resolve_script_path2)

    try:
        import DaVinciResolveScript as dvr_script
        from python_get_resolve import GetResolve
        print("DaVinciResolveScript from DaVinci")
    except ImportError as e:
        raise ImportError("Unable to import DaVinciResolveScript or python_get_resolve after adding paths") from e
    
# 获取Resolve实例
resolve = GetResolve()
ui = fusion.UIManager
dispatcher = bmd.UIDispatcher(ui)

def load_image_in_fusion(image_path):
    comp = fusion.GetCurrentComp()
    comp.Lock()
    loader = comp.AddTool("Loader")
    loader.Clip[comp.CurrentTime] = image_path
    loader.SetAttrs({"TOOLS_RegenerateCache": True})
    comp.Unlock()

def add_to_media_pool(filename):
    # 获取Resolve实例
    resolve = dvr_script.scriptapp("Resolve")
    project_manager = resolve.GetProjectManager()
    project = project_manager.GetCurrentProject()
    media_pool = project.GetMediaPool()
    root_folder = media_pool.GetRootFolder()
    ai_image_folder = None

    # 检查 AiImage 文件夹是否已存在
    folders = root_folder.GetSubFolderList()
    for folder in folders:
        if folder.GetName() == "AiImage":
            ai_image_folder = folder
            break

    if not ai_image_folder:
        ai_image_folder = media_pool.AddSubFolder(root_folder, "AiImage")

    if ai_image_folder:
        print(f"AiImage folder is available: {ai_image_folder.GetName()}")
    else:
        print("Failed to create or find AiImage folder.")
        return False

    media_storage = resolve.GetMediaStorage()
    mapped_path = filename
    media_pool.SetCurrentFolder(ai_image_folder)
    return media_pool.ImportMedia([mapped_path], ai_image_folder)

def check_or_create_file(file_path):
    if os.path.exists(file_path):
        pass
    else:
        try:
            with open(file_path, 'w') as file:
                json.dump({}, file)  # 写入一个空的JSON对象，以初始化文件
        except IOError:
            raise Exception(f"Cannot create file: {file_path}")

def get_script_path():
    # 使用 sys.argv 获取脚本路径
    if len(sys.argv) > 0:
        return os.path.dirname(os.path.abspath(sys.argv[0]))
    else:
        return os.getcwd()

script_path = get_script_path()

settings_file = os.path.join(script_path, 'Stability_settings.json')

check_or_create_file(settings_file)

def load_settings(settings_file):
    if os.path.exists(settings_file):
        with open(settings_file, 'r') as file:
            content = file.read()
            if content:
                try:
                    settings = json.loads(content)
                    return settings
                except json.JSONDecodeError as err:
                    print('Error decoding settings:', err)
                    return None
    return None

def save_settings(settings, settings_file):
    with open(settings_file, 'w') as file:
        content = json.dumps(settings, indent=4)
        file.write(content)

saved_settings = load_settings(settings_file) 

default_settings = {
    "USE_DR": True,
    "USE_FU": False,
    "API_KEY": '',
    "OUTPUT_DIRECTORY": '',
    "PROMPT_V1": '',
    "PROMPT_V2": '',
    "NEGATIVE_PROMPT": '',
    "STYLE_PRESET": 0,
    "STYLE_PRESET_V1": 0,
    "ASPECT_RATIO": 0,
    "MODEL_V1": 0,
    "MODEL_V2": 0,
    "SEED_V1": '0',
    "SEED_V2": '0',
    "OUTPUT_FORMAT": 0,
    "USE_RANDOM_SEED_V1": True,
    "USE_RANDOM_SEED_V2": True,
    "CFG_SCALE": '7',
    "HEIGHT": '512',
    "WIDTH": '512',
    "SAMPLER": 0,
    "SAMPLES": '1',
    "STEPS": '30'
}


infomsg = """
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
            margin-bottom: 0px; /* 调整此处以减少间隔 */
            border-bottom: 2px solid #f0f0f0;
            padding-bottom: 5px;
            color: #c7a364; /* 黄金色 */
        }
        p {
            font-size: 1.2em;
            margin-top: 5px;
            margin-bottom: 0px; /* 调整此处以减少间隔 */
            color: #a3a3a3; /* 灰白色 */
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
    <h3>介绍</h3>
    <p>此脚本使用<a href="https://stability.ai">Stability.AI</a> API生成高质量图片，可以导入到 DaVinci Resolve 或通过 Fusion Studio 中的 Loader 节点。</p>

    <h3>保存路径</h3>
    <p>指定生成文件的保存路径。</p>

    <h3>API密钥</h3>
    <p>从<a href="https://stability.ai">Stability.AI</a>获取您的 API 密钥。</p>

    <h3>生成图像 V1</h3>
    <p>在此，您可以使用 'SDXL 1.0' 和 'SD 1.6' 来生成图片。</p>

    <h3>生成图像 V2</h3>
    <p>在此，您可以使用 'Stable Image Core'、'SD3' 和 'SD3 Turbo' 来生成图片。</p>
</body>
</html> 
"""

# 定义窗口
win = dispatcher.AddWindow(
    {
        "ID": 'MyWin',
        "WindowTitle": 'Stability AI Version 1.0',
        "Geometry": [700, 300, 400, 480],
        "Spacing": 10,
    },
    [
        ui.VGroup(
            [
                ui.TabBar({"Weight": 0.0, "ID": "MyTabs"}),
                ui.VGroup([]),
                ui.Stack(
                    {"Weight": 1.0, "ID": "MyStack"},
                    [
                        ui.VGroup(
                            {"Weight": 1},
                            [
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'ModelLabel', "Text": '模型', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.ComboBox({"ID": 'ModelCombo', "Text": 'Model', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 1},
                                    [
                                        ui.Label({"ID": 'PromptLabel', "Text": '提示词', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.TextEdit({"ID": 'PromptTxt', "Text": '', "PlaceholderText": 'Please Enter a Prompt.', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'ResolutionLabel', "Text": '分辨率', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.LineEdit({"ID": 'Width', "Text": '512', "Weight": 0.4}),
                                        ui.LineEdit({"ID": 'Height', "Text": '512', "Weight": 0.4}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'StyleLabel', "Text": '风格', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.ComboBox({"ID": 'StyleComboV1', "Text": 'Style_Preset', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'CfgScaleLabel', "Text": 'CFG', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.LineEdit({"ID": 'CfgScale', "Text": '7', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'SamplerLabel', "Text": '采样器', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.ComboBox({"ID": 'SamplerCombo', "Text": 'Sampler', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'SamplesLabel', "Text": '数量', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.LineEdit({"ID": 'Samples', "Text": '1', "Weight": 0.8, "ReadOnly": True}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'StepsLabel', "Text": '步数', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.LineEdit({"ID": 'Steps', "Text": '30', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'SeedLabel', "Text": '种子', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.LineEdit({"ID": 'Seed', "Text": '0', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Button({"ID": 'HelpButton', "Text": '帮助'}),
                                        ui.CheckBox({"ID": 'RandomSeed', "Text": '使用随机种子', "Checked": True}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Button({"ID": 'GenerateButton', "Text": '生成'}),
                                        ui.Button({"ID": 'ResetButton', "Text": '重置'}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'StatusLabel1', "Text": ' ', "Alignment": {"AlignHCenter": True, "AlignVCenter": True}}),
                                    ]
                                ),
                                ui.Button(
                                    {
                                        "ID": 'OpenLinkButton',
                                        "Text": '😃Buy Me a Coffee😃，© 2024, Copyright by HB.',
                                        "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                                        "Font": ui.Font({"PixelSize": 12, "StyleName": 'Bold'}),
                                        "Flat": True,
                                        "TextColor": [0.1, 0.3, 0.9, 1],
                                        "BackgroundColor": [1, 1, 1, 0],
                                        "Weight": 0.1,
                                    }
                                ),
                            ]
                        ),
                        ui.VGroup(
                            {"Weight": 1},
                            [
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'ModelLabel', "Text": '模型', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.ComboBox({"ID": 'ModelComboV2', "Text": 'Model', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 1},
                                    [
                                        ui.Label({"ID": 'PromptLabel', "Text": '提示词', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.TextEdit({"ID": 'PromptTxtV2', "Text": '', "PlaceholderText": 'Please Enter a Prompt.', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 1},
                                    [
                                        ui.Label({"ID": 'NegativePromptLabel', "Text": '反向提示词', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.TextEdit({"ID": 'NegativePromptTxt', "Text": '', "PlaceholderText": 'Please Enter a Negative Prompt.', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'StyleLabel', "Text": '风格', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.ComboBox({"ID": 'StyleCombo', "Text": 'Style_Preset', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'AspectRatioLabel', "Text": '长宽比', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.ComboBox({"ID": 'AspectRatioCombo', "Text": 'aspect_ratio', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'OutputFormatLabel', "Text": '格式', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.ComboBox({"ID": 'OutputFormatCombo', "Text": 'Output_Format', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'SeedLabel', "Text": '种子', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.LineEdit({"ID": 'SeedV2', "Text": '0', "Weight": 0.8}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Button({"ID": 'HelpButton', "Text": '帮助'}),
                                        ui.CheckBox({"ID": 'RandomSeedV2', "Text": '使用随机种子', "Checked": True}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Button({"ID": 'GenerateButton', "Text": '生成'}),
                                        ui.Button({"ID": 'ResetButton', "Text": '重置'}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.1},
                                    [
                                        ui.Label({"ID": 'StatusLabel2', "Text": ' ', "Alignment": {"AlignHCenter": True, "AlignVCenter": True}}),
                                    ]
                                ),
                                ui.Button(
                                    {
                                        "ID": 'OpenLinkButton',
                                        "Text": '😃Buy Me a Coffee😃，© 2024, Copyright by HB.',
                                        "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                                        "Font": ui.Font({"PixelSize": 12, "StyleName": 'Bold'}),
                                        "Flat": True,
                                        "TextColor": [0.1, 0.3, 0.9, 1],
                                        "BackgroundColor": [1, 1, 1, 0],
                                        "Weight": 0.1,
                                    }
                                ),
                            ]
                        ),
                        ui.VGroup(
                            [
                                ui.HGroup(
                                    {"Weight": 0.05},
                                    [
                                        ui.CheckBox({"ID": 'DRCheckBox', "Text": '在 DaVinci Resolve 中使用', "Checked": True, "Weight": 0.5}),
                                        ui.CheckBox({"ID": 'FUCheckBox', "Text": '在 Fusion Studio 中使用', "Checked": False, "Weight": 0.5}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.05},
                                    [
                                        ui.Label({"ID": 'PathLabel', "Text": '保存路径', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.LineEdit({"ID": 'Path', "Text": '', "PlaceholderText": '', "ReadOnly": False, "Weight": 0.6}),
                                        ui.Button({"ID": 'Browse', "Text": '浏览', "Weight": 0.2}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.05},
                                    [
                                        ui.Label({"ID": 'ApiKeyLabel', "Text": 'API 密钥', "Alignment": {"AlignRight": False}, "Weight": 0.2}),
                                        ui.LineEdit({"ID": 'ApiKey', "Text": '', "EchoMode": 'Password', "Weight": 0.6}),
                                        ui.Button({"ID": 'Balance', "Text": '余额', "Weight": 0.2}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.05},
                                    [
                                          ui.Label({"ID": 'BalanceLabel', "Text": '',  "Alignment" : {"AlignHCenter" : True, "AlignVCenter" : True},"Weight": 0.2}),
                                    ]
                                ),
                                ui.HGroup(
                                    {"Weight": 0.85},
                                    [
                                        ui.TextEdit({"ID": 'infoTxt', "Text": infomsg, "ReadOnly": True}),
                                    ]
                                ),
                                ui.Button(
                                    {
                                        "ID": 'OpenLinkButton',
                                        "Text": '😃Buy Me a Coffee😃，© 2024, Copyright by HB.',
                                        "Alignment": {"AlignHCenter": True, "AlignVCenter": True},
                                        "Font": ui.Font({"PixelSize": 12, "StyleName": 'Bold'}),
                                        "Flat": True,
                                        "TextColor": [0.1, 0.3, 0.9, 1],
                                        "BackgroundColor": [1, 1, 1, 0],
                                        "Weight": 0.1,
                                    }
                                ),
                            ]
                        ),
                    ]
                ),
            ]
        ),
    ]
)

itm = win.GetItems()
itm["MyStack"].CurrentIndex = 0
itm["MyTabs"].AddTab("文生图 V1")
itm["MyTabs"].AddTab("文生图 V2")
itm["MyTabs"].AddTab("配置")
def on_my_tabs_current_changed(ev):
    itm["MyStack"].CurrentIndex = ev["Index"]
win.On.MyTabs.CurrentChanged = on_my_tabs_current_changed


itm["ModelCombo"].AddItem('SD 1.6')
itm["ModelCombo"].AddItem('SDXL 1.0')
engine_id = None

def on_model_combo_current_index_changed(ev):
    global engine_id
    if itm["ModelCombo"].CurrentIndex == 0:
        engine_id = "stable-diffusion-v1-6"
    elif itm["ModelCombo"].CurrentIndex == 1:
        engine_id = "stable-diffusion-xl-1024-v1-0"
    print(f'Using Model: {itm["ModelCombo"].CurrentText}')
win.On.ModelCombo.CurrentIndexChanged = on_model_combo_current_index_changed

samplers = ['DDIM', 'DDPM', 'K_DPMPP_2M', 'K_DPMPP_2S_ANCESTRAL', 'K_DPM_2', 'K_DPM_2_ANCESTRAL', 'K_EULER', 'K_EULER_ANCESTRAL', 'K_HEUN', 'K_LMS']
for sampler in samplers:
    itm["SamplerCombo"].AddItem(sampler)

def on_sampler_combo_current_index_changed(ev):
    print(f'Using Sampler: {itm["SamplerCombo"].CurrentText}')
win.On.SamplerCombo.CurrentIndexChanged = on_sampler_combo_current_index_changed

models = ['Stable Image Ultra','Stable Image Core', 'Stable Diffusion 3 Large', 'Stable Diffusion 3 Large Turbo','Stable Diffusion 3 Medium']
for model in models:
    itm["ModelComboV2"].AddItem(model)

style_presets_mapping = {
    'Default': '默认',
    '3d-model': '3D模型',
    'analog-film': '胶片',
    'anime': '动漫',
    'cinematic': '电影',
    'comic-book': '漫画',
    'digital-art': '数字艺术',
    'enhance': '增强',
    'fantasy-art': '奇幻艺术',
    'isometric': '等距',
    'line-art': '线条艺术',
    'low-poly': '低多边形',
    'modeling-compound': '模型复合',
    'neon-punk': '霓虹朋克',
    'origami': '折纸',
    'photographic': '摄影',
    'pixel-art': '像素艺术',
    'tile-texture': '瓷砖纹理',
}

# 生成反向映射字典
style_presets_mapping_reverse = {v: k for k, v in style_presets_mapping.items()}

# 获取样式名称的函数
def get_style_preset_cn(style):
    return style_presets_mapping.get(style, style)

def get_style_preset_en(chinese_style):
    return style_presets_mapping_reverse.get(chinese_style, chinese_style)
for style in style_presets_mapping:
    itm["StyleCombo"].AddItem(get_style_preset_cn(style))
    itm["StyleComboV1"].AddItem(get_style_preset_cn(style))

aspect_ratios = ['1:1', '16:9', '21:9', '2:3', '3:2', '4:5', '5:4', '9:16', '9:21']
for ratio in aspect_ratios:
    itm["AspectRatioCombo"].AddItem(ratio)

output_formats = ['png', 'jpeg','webp']
for format in output_formats:
    itm["OutputFormatCombo"].AddItem(format)

def on_dr_checkbox_clicked(ev):
    itm["FUCheckBox"].Checked = not itm["DRCheckBox"].Checked
    if itm["FUCheckBox"].Checked:
        print("Using in Fusion Studio")
    else:
        print("Using in DaVinci Resolve")
win.On.DRCheckBox.Clicked = on_dr_checkbox_clicked
def on_fu_checkbox_clicked(ev):
    itm["DRCheckBox"].Checked = not itm["FUCheckBox"].Checked
    if itm["FUCheckBox"].Checked:
        print("Using in Fusion Studio")
    else:
        print("Using in DaVinci Resolve")
win.On.FUCheckBox.Clicked = on_fu_checkbox_clicked

model_id = None
style_preset = ['', '3d-model', 'analog-film', 'anime', 'cinematic', 'comic-book', 'digital-art', 'enhance', 'fantasy-art', 'isometric', 'line-art', 'low-poly', 'modeling-compound', 'neon-punk', 'origami', 'photographic', 'pixel-art', 'tile-texture']

def update_output_formats():
    if itm["ModelComboV2"].CurrentIndex in [2, 3 , 4]:
        if "webp" in output_formats:
            output_formats.remove("webp")
    else:
        if "webp" not in output_formats:
            output_formats.append("webp")

    current_selection = itm["OutputFormatCombo"].CurrentText
    itm["OutputFormatCombo"].Clear()
    for format in output_formats:
        itm["OutputFormatCombo"].AddItem(format)
    
    # 重新设置当前选项
    if current_selection in output_formats:
        itm["OutputFormatCombo"].CurrentText = current_selection



def on_model_combo_v2_current_index_changed(ev):

    itm["NegativePromptTxt"].ReadOnly = False
    itm["StyleCombo"].CurrentIndex = 0
    global model_id
    model_index = itm["ModelComboV2"].CurrentIndex
    if model_index == 0:
        itm["StyleCombo"].Enabled = False
        model_id = 'ultra'
        itm["OutputFormatCombo"].AddItem(format)
    elif model_index == 1:
        model_id = 'core'
        itm["StyleCombo"].Enabled = True
    elif model_index == 2:
        itm["StyleCombo"].Enabled = False
        model_id = 'sd3-large'
    elif model_index == 3:
        itm["StyleCombo"].Enabled = False
        itm["NegativePromptTxt"].ReadOnly = True
        itm["NegativePromptTxt"].Text = ''
        model_id = 'sd3-large-turbo'
    elif model_index == 4:
        itm["StyleCombo"].Enabled = False
        model_id = 'sd3-medium'  

    print(f'Using Model: {itm["ModelComboV2"].CurrentText}')

    update_output_formats()
win.On.ModelComboV2.CurrentIndexChanged = on_model_combo_v2_current_index_changed


def on_aspect_ratio_combo_current_index_changed(ev):
    print(f'Using Aspect_Ratio: {itm["AspectRatioCombo"].CurrentText}')
win.On.AspectRatioCombo.CurrentIndexChanged = on_aspect_ratio_combo_current_index_changed


def on_output_format_combo_current_index_changed(ev):
    # print(f'Using Output_Format: {itm["OutputFormatCombo"].CurrentText}')
    pass
win.On.OutputFormatCombo.CurrentIndexChanged = on_output_format_combo_current_index_changed


def on_open_link_button_clicked(ev):
    webbrowser.open("https://www.paypal.me/heiba2wk")
win.On.OpenLinkButton.Clicked = on_open_link_button_clicked


# 更新状态
def update_status(message):
    itm["StatusLabel1"].Text = message
    itm["StatusLabel2"].Text = message

if saved_settings:
    itm["DRCheckBox"].Checked = saved_settings.get("USE_DR", default_settings["USE_DR"])
    itm["FUCheckBox"].Checked = saved_settings.get("USE_FU", default_settings["USE_FU"])
    itm["ApiKey"].Text = saved_settings.get("API_KEY", default_settings["API_KEY"])
    itm["PromptTxtV2"].PlainText = saved_settings.get("PROMPT_V2", default_settings["PROMPT_V2"])
    itm["NegativePromptTxt"].PlainText = saved_settings.get("NEGATIVE_PROMPT", default_settings["NEGATIVE_PROMPT"])
    itm["StyleCombo"].CurrentIndex = saved_settings.get("STYLE_PRESET", default_settings["STYLE_PRESET"])
    itm["StyleComboV1"].CurrentIndex = saved_settings.get("STYLE_PRESET_V1", default_settings["STYLE_PRESET_V1"])
    itm["SeedV2"].Text = str(saved_settings.get("SEED_V2", default_settings["SEED_V2"]))
    itm["RandomSeedV2"].Checked = saved_settings.get("USE_RANDOM_SEED_V2", default_settings["USE_RANDOM_SEED_V2"])
    itm["ModelComboV2"].CurrentIndex = saved_settings.get("MODEL_V2", default_settings["MODEL_V2"])
    itm["AspectRatioCombo"].CurrentIndex = saved_settings.get("ASPECT_RATIO", default_settings["ASPECT_RATIO"])
    itm["OutputFormatCombo"].CurrentIndex = saved_settings.get("OUTPUT_FORMAT", default_settings["OUTPUT_FORMAT"])
    itm["Path"].Text = saved_settings.get("OUTPUT_DIRECTORY", default_settings["OUTPUT_DIRECTORY"])
    itm["PromptTxt"].PlainText = saved_settings.get("PROMPT_V1", default_settings["PROMPT_V1"])
    itm["Seed"].Text = str(saved_settings.get("SEED_V1", default_settings["SEED_V1"]))
    itm["CfgScale"].Text = str(saved_settings.get("CFG_SCALE", default_settings["CFG_SCALE"]))
    itm["Height"].Text = str(saved_settings.get("HEIGHT", default_settings["HEIGHT"]))
    itm["Width"].Text = str(saved_settings.get("WIDTH", default_settings["WIDTH"]))
    itm["Samples"].Text = str(saved_settings.get("SAMPLES", default_settings["SAMPLES"]))
    itm["Steps"].Text = str(saved_settings.get("STEPS", default_settings["STEPS"]))
    itm["RandomSeed"].Checked = saved_settings.get("USE_RANDOM_SEED_V1", default_settings["USE_RANDOM_SEED_V1"])
    itm["ModelCombo"].CurrentIndex = saved_settings.get("MODEL_V1", default_settings["MODEL_V1"])
    itm["SamplerCombo"].CurrentIndex = saved_settings.get("SAMPLER", default_settings["SAMPLER"])


def show_warning_message(text):
    # 创建警告消息框窗口
    msgbox = dispatcher.AddWindow(
        {
            "ID": 'msg',
            "WindowTitle": 'Warning',
            "Geometry": [750, 400, 350, 100],
            "Spacing": 10,
        },
        [
            ui.VGroup(
                [
                    ui.Label({"ID": 'WarningLabel', "Text": text}),
                    ui.HGroup(
                        {
                            "Weight": 0,
                        },
                        [
                            ui.Button({"ID": 'OkButton', "Text": 'OK'}),
                        ]
                    ),
                ]
            ),
        ]
    )
    
    def on_ok_button_clicked(ev):
        dispatcher.ExitLoop()
    msgbox.On.OkButton.Clicked = on_ok_button_clicked

    # 显示消息框
    msgbox.Show()
    dispatcher.RunLoop()
    msgbox.Hide()

def get_remaining_credits(api_key: str) -> float:
    api_host = 'https://api.stability.ai'
    url = f"{api_host}/v1/user/balance"

    response = requests.get(url, headers={
        "Authorization": f"Bearer {api_key}"
    })

    if response.status_code != 200:
        raise Exception("Non-200 response: " + str(response.text))

    payload = response.json()
    credits = payload.get("credits", 0.0)
    return round(credits, 1)

def generate_image_v1(settings, engine_id):
    update_status("图像生成中...")

    url = f"https://api.stability.ai/v1/generation/{engine_id}/text-to-image"
    count = 0
    file_exists = False
    output_file = None

    while True:
        count += 1
        output_directory = settings["OUTPUT_DIRECTORY"]
        output_file = os.path.join(output_directory, f"image{settings['SEED_V1']}{count}a.png")
        if os.path.exists(output_file):
            file_exists = True
        else:
            file_exists = False

        if not file_exists:
            break

    data = {
        "text_prompts": [{"text": settings["PROMPT_V1"]}],
        "cfg_scale": settings["CFG_SCALE"],
        "height": settings["HEIGHT"],
        "width": settings["WIDTH"],
        "samples": settings["SAMPLES"],
        "steps": settings["STEPS"],
        "seed": settings["SEED_V1"],
        "sampler": settings["SAMPLER"]
    }
    if get_style_preset_en(settings.get("STYLE_PRESET_V1"))!="Default":
        data["style_preset"] = get_style_preset_en(settings["STYLE_PRESET_V1"])

    headers = {
        "Content-Type": "application/json",
        "Accept": "image/png",
        "Authorization": f"Bearer {settings['API_KEY']}"
    }

    print("Sending request to URL:", url)
    print("Request data:", json.dumps(data, indent=2))
    
    response = requests.post(url, headers=headers, json=data)

    if response.status_code == 200:
        with open(output_file, 'wb') as file:
            file.write(response.content)
        update_status("图像生成成功.")
        print(f"Success: Image saved to {output_file}")
        return output_file
    else:
        error_message = response.json()
        update_status(f"图像生成失败: {response.status_code}")
        print(f"Error: {error_message}")
        return None

def generate_image_v2(settings):
    update_status("图像生成中...")
    count = 0
    file_exists = False
    output_file = None

    while True:
        count += 1
        output_directory = settings["OUTPUT_DIRECTORY"]
        output_file = os.path.join(output_directory, f"image{settings['SEED_V2']}{count}a.{settings['OUTPUT_FORMAT']}")
        if os.path.exists(output_file):
            file_exists = True
        else:
            file_exists = False

        if not file_exists:
            break
    #print(output_file)
    url = ""
    data = {
        "prompt": settings["PROMPT_V2"],
        "negative_prompt": settings["NEGATIVE_PROMPT"],
        "seed": settings["SEED_V2"],
        "aspect_ratio": settings["ASPECT_RATIO"],
        "output_format": settings["OUTPUT_FORMAT"],
    }

    if settings["MODEL_V2"] == "ultra":
        url = "https://api.stability.ai/v2beta/stable-image/generate/ultra"

    elif settings["MODEL_V2"] == "core":
        url = "https://api.stability.ai/v2beta/stable-image/generate/core"
        if get_style_preset_en(settings["STYLE_PRESET"])!="Default":
            data["style_preset"] = get_style_preset_en(settings["STYLE_PRESET"])

    elif settings["MODEL_V2"] in ["sd3-large", "sd3-large-turbo","sd3-medium"]:
        url = "https://api.stability.ai/v2beta/stable-image/generate/sd3"
        data["mode"] = "text-to-image"
        data["model"] = settings["MODEL_V2"]
    else:
        update_status("Invalid model specified.")
        return None

    headers = {
        "Authorization": f"Bearer {settings['API_KEY']}",
        "Accept": "image/*"
    }

    print("Sending request to URL:", url)
    print("Request data:", data)

    response = requests.post(url, headers=headers, files={"none": ""}, data=data)
    if response.status_code == 200:
        credits = get_remaining_credits(settings['API_KEY'])
        with open(output_file, 'wb') as file:
            file.write(response.content)
        update_status("图像生成成功.")
        print(f"Success: Image saved to {output_file}")
        return output_file
    else:
        error_message = response.json()
        update_status(f"图像生成失败: {response.status_code}")
        print(f"Error: {error_message}")
        return None


def on_generate_button_clicked(ev):
    if itm["Path"].Text == '':
        show_warning_message('Please go to Configuration to select the image save path.')
        return
    if itm["ApiKey"].Text == '':
        show_warning_message('Please go to Configuration to enter the API Key.')
        return

    if itm["MyTabs"].CurrentIndex == 1:
        if itm["RandomSeedV2"].Checked:
            newseed = random.randint(0, 4294967295)
        else:
            newseed = int(itm["SeedV2"].Text) if itm["SeedV2"].Text.isdigit() else 0  # 如果输入无效，默认为0

        itm["SeedV2"].Text = str(newseed)  # 更新界面上的显示

        settings = {
            "API_KEY": itm["ApiKey"].Text,
            "PROMPT_V2": itm["PromptTxtV2"].PlainText,
            "NEGATIVE_PROMPT": itm["NegativePromptTxt"].PlainText,
            "STYLE_PRESET": itm["StyleCombo"].CurrentText,
            "ASPECT_RATIO": itm["AspectRatioCombo"].CurrentText,
            "OUTPUT_FORMAT": itm["OutputFormatCombo"].CurrentText,
            "MODEL_V2": model_id,
            "SEED_V2": newseed,
            "OUTPUT_DIRECTORY": itm["Path"].Text,
        }

        # 执行图片生成和加载操作
        image_path = generate_image_v2(settings)
        if image_path:
            if itm["DRCheckBox"].Checked:
                add_to_media_pool(image_path)
            else:
                load_image_in_fusion(image_path)
    elif itm["MyTabs"].CurrentIndex == 0:
        if itm["RandomSeed"].Checked:
            newseed = random.randint(0, 4294967295)
        else:
            newseed = int(itm["Seed"].Text) if itm["Seed"].Text.isdigit() else 0

        itm["Seed"].Text = str(newseed)  # 更新界面上的显示

        settings = {
            "API_KEY": itm["ApiKey"].Text,
            "PROMPT_V1": itm["PromptTxt"].PlainText,
            "SAMPLER": itm["SamplerCombo"].CurrentText,
            "CFG_SCALE": float(itm["CfgScale"].Text),
            "HEIGHT": int(itm["Height"].Text),
            "WIDTH": int(itm["Width"].Text),
            "STYLE_PRESET_V1": itm["StyleComboV1"].CurrentText,
            "SAMPLES": int(itm["Samples"].Text),
            "STEPS": int(itm["Steps"].Text),
            "SEED_V1": newseed,
            "OUTPUT_DIRECTORY": itm["Path"].Text,
        }

        # 执行图片生成和加载操作
        image_path = generate_image_v1(settings, engine_id)
        if image_path:
            if itm["DRCheckBox"].Checked:
                add_to_media_pool(image_path)
            else:
                load_image_in_fusion(image_path)
win.On.GenerateButton.Clicked = on_generate_button_clicked

def close_and_save(settings_file):
    settings = {
        "USE_DR": itm["DRCheckBox"].Checked,
        "USE_FU": itm["FUCheckBox"].Checked,
        "API_KEY": itm["ApiKey"].Text,
        "PROMPT_V2": itm["PromptTxtV2"].PlainText,
        "NEGATIVE_PROMPT": itm["NegativePromptTxt"].PlainText,
        "STYLE_PRESET": itm["StyleCombo"].CurrentIndex,
        "STYLE_PRESET_V1": itm["StyleComboV1"].CurrentIndex,
        "SEED_V2": int(itm["SeedV2"].Text),
        "ASPECT_RATIO": itm["AspectRatioCombo"].CurrentIndex,
        "OUTPUT_FORMAT": itm["OutputFormatCombo"].CurrentIndex,
        "MODEL_V2": itm["ModelComboV2"].CurrentIndex,
        "USE_RANDOM_SEED_V2": itm["RandomSeedV2"].Checked,
        "OUTPUT_DIRECTORY": itm["Path"].Text,
        "PROMPT_V1": itm["PromptTxt"].PlainText,
        "SEED_V1": int(itm["Seed"].Text),
        "CFG_SCALE": float(itm["CfgScale"].Text),
        "HEIGHT": int(itm["Height"].Text),
        "WIDTH": int(itm["Width"].Text),
        "SAMPLER": itm["SamplerCombo"].CurrentIndex,
        "MODEL_V1": itm["ModelCombo"].CurrentIndex,
        "SAMPLES": int(itm["Samples"].Text),
        "STEPS": int(itm["Steps"].Text),
        "USE_RANDOM_SEED_V1": itm["RandomSeed"].Checked
    }

    save_settings(settings, settings_file)

def on_help_button_clicked(ev):
    helpmsg1 = ''' 
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
    </ul>
    '''
    helpmsg2 = ''' 
    <h2>Negative_Prompt</h2>
    <p>This parameter does not work with SD3-Turbo model.</p>
    <h2>Style_Preset</h2>
    <p>This parameter is applicable exclusively to the Core model.</p>
    '''
    
    if itm["MyTabs"].CurrentIndex == 1:
        helpmsg = helpmsg2
    elif itm["MyTabs"].CurrentIndex == 0:
        helpmsg = helpmsg1

    msgbox = dispatcher.AddWindow(
        {
            "ID": 'msg',
            "WindowTitle": 'Help',
            "Geometry": [400, 300, 300, 300],
            "Spacing": 10,
        },
        [
            ui.VGroup(
                [
                    ui.TextEdit({"ID": 'HelpTxt', "Text": helpmsg, "ReadOnly": True}),
                ]
            ),
        ]
    )

    def on_msg_close(ev):
        dispatcher.ExitLoop()

    msgbox.On.msg.Close = on_msg_close
    msgbox.Show()
    dispatcher.RunLoop()
    msgbox.Hide()
win.On.HelpButton.Clicked = on_help_button_clicked

def on_reset_button_clicked(ev):
    itm["DRCheckBox"].Checked = default_settings["USE_DR"]
    itm["FUCheckBox"].Checked = default_settings["USE_FU"]
    # itm["ApiKey"].Text = default_settings["API_KEY"]
    itm["Path"].ReadOnly = False
    itm["Path"].PlaceholderText = ''
    # itm["Path"].Text = default_settings["OUTPUT_DIRECTORY"]

    if itm["MyTabs"].CurrentIndex == 1:
        itm["PromptTxtV2"].PlainText = default_settings["PROMPT_V2"]
        itm["NegativePromptTxt"].PlainText = default_settings["NEGATIVE_PROMPT"]
        itm["StyleCombo"].CurrentIndex = default_settings["STYLE_PRESET"]
        itm["SeedV2"].Text = str(default_settings["SEED_V2"])
        itm["ModelComboV2"].CurrentIndex = default_settings["MODEL_V2"]
        itm["OutputFormatCombo"].CurrentIndex = default_settings["OUTPUT_FORMAT"]
        itm["AspectRatioCombo"].CurrentIndex = default_settings["ASPECT_RATIO"]
        itm["RandomSeedV2"].Checked = default_settings["USE_RANDOM_SEED_V2"]

    elif itm["MyTabs"].CurrentIndex == 0:
        itm["PromptTxt"].PlainText = default_settings["PROMPT_V1"]
        itm["ModelCombo"].CurrentIndex = default_settings["MODEL_V1"]
        itm["SamplerCombo"].CurrentIndex = default_settings["SAMPLER"]
        itm["Seed"].Text = str(default_settings["SEED_V1"])
        itm["CfgScale"].Text = str(default_settings["CFG_SCALE"])
        itm["Height"].Text = str(default_settings["HEIGHT"])
        itm["StyleComboV1"].CurrentIndex = default_settings["STYLE_PRESET_V1"]
        itm["Width"].Text = str(default_settings["WIDTH"])
        itm["Samples"].Text = str(default_settings["SAMPLES"])
        itm["Steps"].Text = str(default_settings["STEPS"])
        itm["RandomSeed"].Checked = default_settings["USE_RANDOM_SEED_V1"]

    update_status(" ")
win.On.ResetButton.Clicked = on_reset_button_clicked


def on_browse_button_clicked(ev):
    current_path = itm["Path"].Text
    selected_path = fusion.RequestDir(current_path)
    if selected_path:
        itm["Path"].Text = str(selected_path)
    else:
        print("No directory selected or the request failed.")
win.On.Browse.Clicked = on_browse_button_clicked


def on_balance_button_clicked(ev):
    try:
        credits = get_remaining_credits(itm["ApiKey"].Text)
        itm["BalanceLabel"].Text = f"剩余积分: {credits}"
        print(f"Credits: {credits}")
    except Exception as e:
        itm["BalanceLabel"].Text = f"Invalid API key"
        print(f"发生错误: {e}")
win.On.Balance.Clicked = on_balance_button_clicked

def on_close(ev):
    close_and_save(settings_file)
    dispatcher.ExitLoop()
win.On.MyWin.Close = on_close

# 显示窗口
win.Show()
dispatcher.RunLoop()
win.Hide()
