# Text to Image Generator for DaVinci Resolve

## 介绍
这是一个专门为视频编辑和后期制作软件DaVinci Resolve设计的Lua脚本。借助于最新的SD3.0、SD3-Turbo、SDXL等模型，这个脚本能够调用 [Stability AI](https://stability.ai/) API生成高质量的图片，并将这些图片导入到DaVinci Resolve的媒体池中。特别适用于视频制作人和视觉艺术家，他们需要快速生成并应用大量图像素材，从而提升创作效率并丰富视觉效果。
![output](https://github.com/2445868686/Davinci-Resolve-SD-Text-to-Image/assets/50979290/0c7dd17a-032e-4681-82a3-352a8a6732c2)
<div align="center">
   DaVinci Resolve界面
</div>


## 安装
### DaVinci Resolve 版本安装：

将`Stable Diffusion DR HB`文件夹移动到以下位置：

  `Mac：/Users/用户名/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Edit`
  
  `Win：C:\ProgramData\Blackmagic Design\DaVinci Resolve\Fusion\Scripts\Edit`

###  Fusion Studio 版本安装：
将`Stable Diffusion Fu HB`文件夹移动到以下位置：

  `Mac：/Users/用户名/Library/Application Support/Blackmagic Design/Fusion/Scripts/Comp`
  
  `Win：C:\ProgramData\Blackmagic Design\Fusion\Scripts\Comp`
## 使用
### Stable Diffusion 3.0 
<div align="center">
    <img src="https://github.com/2445868686/Davinci-Resolve-SD-Text-to-Image/assets/50979290/4b0472d8-f2f9-4340-996b-1bbf34edb831" width="430" alt="截屏2024-04-29 08 34 35">
</div>
<div align="center">
   Stable Diffusion 3.0界面
</div>

**API_Key：** <br>
请从  [Stability AI](https://stability.ai/)  获取您的 API 密钥，目前注册赠送25积分,使用SD Version 1.0可以免费生成125～200张图片。 <br>

**Save Path：** <br>
图片保存路径，手动复制至此。 <br>

**Negative_Prompt：** <br>
此参数不适用于 sd3-turbo。 <br>

### SD Version 1.0
<div align="center">
  <img width="446" alt="截屏2024-04-29 08 36 49" src="https://github.com/2445868686/Davinci-Resolve-SD-Text-to-Image/assets/50979290/d8813c31-b8ab-42f8-858c-160497bd14b6">
</div>
<div align="center">
   SD Version 1.0界面
</div>

***使用 SD 1.6***<br>
在使用 SD 1.6 时，请确保您设置的高度和宽度满足以下条件：

- 任一维度不得低于 320 像素
- 任一维度不得超过 1536 像素

***使用 SDXL 1.0***<br>
在使用 SDXL 1.0 时，请确保您输入的高度和宽度符合以下几种组合之一：
- 1024x1024
- 1152x896
- 896x1152
- 1216x832
- 1344x768
- 768x1344
- 1536x640
- 640x1536



## 支持
拥抱开源和AI人工智能，致力于AI人工智能的实际应用。所有软件均为开源且免费。如果您支持我的工作，欢迎成为赞助者。

PayPal：https://www.paypal.me/HEIBAWK

<img width="430" alt="A031269C-141F-4338-95F1-6018D40E0A3F" src="https://github.com/2445868686/Davinci-Resolve-SD-Text-to-Image/assets/50979290/a17d3ade-7486-4b3f-9b19-1d2d0c4b6945">
