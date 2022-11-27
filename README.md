<div align="center">
     <img src="resources/logo_light.png" width="80px">
    <h1>Tabame</h1>
</div>

![promote](https://user-images.githubusercontent.com/20853986/204137435-68a6697c-274a-4c81-807e-5ae4c6a2710f.png#gh-light-mode-only)

![promote_dark](https://user-images.githubusercontent.com/20853986/204138108-e57e9b1b-4d2b-445e-b8cb-4480d188ebb9.png#gh-dark-mode-only)

## 🤔 What is this app about?

Main purpose of this app is to be a replacement for the Taskbar, but in meanwhile I've added more features that can come in handy sometimes. It's not about the 30px you add on your screen, but to limit distraction that comes from flashes, badges, notifications and other apps Microsoft forcefully tries to push to their users.
### **Best way to use:**
- **You can bind the QuickMenu on:**
- Mouse Side buttons, most mouses have them.
- Any extra mouse button. Open your mouse software, bind it to something like `CTRL+ALT+SHIFT+F9` then focus Tabame and press the button on field above.
- If you do not have any extra buttons on your mouse, you can bind it to something simple like `Shift+Win+A`, it's easy for the fingers.

### You can watch a small demo here:

| <video src="https://user-images.githubusercontent.com/20853986/185470373-dce706ae-5132-4ecb-97e8-77fbe5377edb.mp4" width="300px"></video> | <video src="https://user-images.githubusercontent.com/20853986/185466421-7347e01a-de1e-4dcd-adfe-81f206107325.mp4" width="300"></video> 	|
|------	|------	|

# 📥 How to Install

Go to [Release page](https://github.com/Far-Se/tabame/releases/latest). It is in right sidebar. Download either installer.ps1 or tabame.zip

## Easiest way to install:
1. Download **installer.ps1**
2. Open your **Downloads folder**
3. Right click and press **"Run with PowerShell"**
4. Complete main setup and it's done 😄 


| ![image](https://user-images.githubusercontent.com/20853986/184855270-4bf0f8d9-ec81-4b22-aee6-1b1df97fc459.png) | ![image](https://user-images.githubusercontent.com/20853986/184855277-f484dc64-b0e9-4468-afb0-44c0ed8f0c0a.png) |
|------|------|

## Manual Install:
1. Download zip archive.
2. Extract it in a folder you want.
3. Open tabame.exe

### 📤 How to uninstall:
If you installed it with installer.ps1 Open file explorer, in address bar write `%localappdata%` then delete folder `Tabame`.
If you manually installed it, delete the folder where you placed it.

## 🐛 If you encounter any errors or bugs:
Please submit a [issue here](https://github.com/Far-Se/tabame/issues), it will be very helpful. On my Computer it works, but each PC can be different.

**Please also provide errors.log file**. You can find it here: `%localappdata%/Tabame`. Open File Explorer and paste that in Address Bar.

Thanks to @elvinvandalen for helping me fix a bug where the app crashed on start because AudioPropertyStore was bugged for some users.

**Known Issue**: for a small amount of users Audio Module makes the app crash, if you experience crash on startup and still want to use Tabame, open folder
`%localappdata%/Tabame` and create a file called `disable_audio.txt` then start Tabame again.

## Make your own:
This project is open source, which means you can compile your own version.
1. Install Flutter for Windows
2. Open Visual Studio Installer, on Individual Components select ATL Dependencies and install.
3. Open a console in Tabame folder and type `flutter build windows`
4. The exe is in `build\windows\runner\Release`
5. You can open vsCode and debug the app.

# Written in Flutter
Which means it consumes very little resources and disk space. 

On idle cpu is 0.0% and when in use is below 3%.

Ram usage is below 50 MB, usually around 40 MB.

It takes only 26.5 MB of space.

**Works very fast, no interruptions**


# Main Features
[🎛️ QuickMenu](#%EF%B8%8F-quickmenu)  

[🎚️ QuickRun](#%EF%B8%8F-quickrun) 

[🎨 Theme](#-theme) 

[🎶 Audio](#-audio) 

[⌨️ Hotkeys](#%EF%B8%8F-hotkeys) 

[📕 Bookmarks](#-bookmarks)

[📝 Trktivity](#-trktivity)

[📅 Tasks](#-tasks)

[✨ Wizardly](#-wizardly)

[🧩 Views](#-views) (v1.1)

[🧰 QuickActionsMenu](#-quickactionsmenu) (v1.2)

[📷 Fancyshot](#-fancyshot) (v1.2)

[🙃 Outro](#-outro)

# **🎛️ QuickMenu**

This is the menu that will popup when you are pressing the main hotkey. It is divided in 3 sections:

## **Top bar**
Contains audio control, volume control, quick actions, pinned apps, Desktop Button and settings button.

### **Audio Control**
- Left click to open Audio Box, where you can modify audio devices.
- Right click to switch default audio output.
- Middle button to mute or un-mute.
- Scroll up or down to change volume level.
  
### **Volume Control**
- Left click sends Play or Pause signal.
- Right click sends Next Track.
- Middle button sends Previous Track.
- Scroll up or down to change volume level.

### **Quick Actions**
- Spotify Button  - Sends media control only to Spotify, same buttons as Volume Control.
- Task Manager Button - Opens Task Manager
- Virtual Desktop Button - Left Click to move to Right(Next) Desktop, right click for Left(Previous) Desktop
- Toggle Taskbar Button - Hides or shows taskbar
- Pin Window Button - Sets last focused window always on top
- Mic Mute Button - Mutes microphone, right click to switch Device Input.
- Always Awake Button - Keeps screen on
- Change Theme Button - Changes between Dark to White. It does not change the settings too!
- Hide Desktop Files Button - Hides/Shows files on desktop, good if you do not always use them.
- Toggle Hidden Files Button - Hides/Shows hidden files.
- **v1.2**
- Fancyshot - Screen Capture with editor.
- Bookmarks - See your saved Bookmarks.
- Countdown - A countdown for quick access.
- Timers - Create Quick Timers. (v1.3:Timers save after restart)
- Quick Actions Menu - A dedicated menu with Quick Actions.
- Close on Focus Loss - If you want to keep QuickMenu on screen, toggle this.
- **v1.3**
- Custom Chars - You can save custom chars or browse different language accents or currency symbols.
- Schedule Shutdown - Schendule a Computer shutdown at a specific hour or after a specific period.
- Case Change - Convert text to camelCase, PascalCase, snake_case, kebab-case, UPPERCASE or lowercase
- Memos - Save your memos.


## **Taskbar**
Contains your opened windows, it shows the icon, if it makes sound, if it is pinned, Monitor Number, Title, Media Control and Close button.

**You can right click a listed window to move it to right or left Desktop, pin or force close**

**You can drag to left or right to switch the app to a different Desktop**

You can show QuickMenu at Taskbar Level or TopBar Level. You can order windows by monitor, activity, or only current monitor.

You can rewrite app titles using regex, example:

![example](https://user-images.githubusercontent.com/20853986/185778878-14ef5a6f-0981-4e7d-aa68-a5afc5b7feb4.png)

## **Bottom Bar**
Main elements of bottom bar are the time and the weather.
It also shows:

### **Tray icons**
It shows a list of existing tray icons. You can hide/pin icons from settings. You can simulate click on the icon, or open icon's executable. Some apps do not listen to native clicks so you can set the second option!

### **PowerShell Scripts**
You can pin PowerShell scripts for easy access, either write the code directly or make a `.ps1` file and then set as command `Invoke-Item path\to\script.ps1`

### **System Information**
Your CPU and RAM usage.

### **You can move pinned apps and tray icons on the same level at the bottom** if the UI becomes too crowded.

### **You can change the icon and add a splash image above the menu** if you brand it as your own or to add your company logo.


# **🎚️ QuickRun**
QuickRun can be launched directly from QuickMenu, just start typing. You can also set a hotkey to open it specifically.

**BE AWARE**: shortcuts always have a space after letters. You can add regex as last parameter. Look at calculator or currency converter.

Consists of:

## Converters
- Calculator: default shortcut is `c `. You can divide multiple math equations with | and use x,y,z,a,b,c as variables. It supports complex equations. Example: `66*20/12` ... `c 75 | x * 20% | x - y | z * 30% | z-a` ... `c 2+3*sqrt(4)`
- Unit converter: Default is `u `. Supports length, mass, temperature, volume, speed, digital, area, energy, force, fuel, power, pressure, shoe, time, torque
Example: `u 1 in to cm` ... `u 1 mass`
- Currency converter: default is `cur `. It uses [fawazahmed0/currency-api](https://github.com/fawazahmed0/currency-api/tree/1/latest/currencies) repository to get latest rates. Example: `cur 100 eur to usd` ... `100 usd to eur` ... `100$ to eur`
- Color converter: default is `col `. Converts from and to: hex `#` or `0x`, rgba, hsla, hsv, cmyk. Example: `col #ff00ff` ... `rgba(123,255,54,12)`
- Time zones: default is `tz `. Shows current time in specific timezone, contains DTS as well.

## Processors
- **Shortcuts: default is `s `. It is good to bookmark links or search**
- **Memo: default is `m `. Good to save commands, text, info that you might need later**
- Regex: default is `rgx `. You can test regex if you ever need to.
- Lorem: default is `lorem `. It generates lorem ipsum text, Example: `lorem 3 long headers`
- Encoders: default is `enc `. Use ! to encode and @ to decode. supports url, base, rot13, ascii.

## Utility
- Bookmarks: default is `b `. You open your saved bookmarks from Interface.
- Timer: default is `t `. Use this to set quick timers, for example for `t 5 tea` to remind you in 5 minutes to drink your tea and not forget it for 4 hours.
- Variable: default is `v `. Use this in combination with Hotkeys if you need to reset a variable.
- Send keys: default is `k `. You can save specific keys and trigger them from quick menu. For example: `k m` to trigger `MEDIA_NEXT_TRACK` if you don't want to stretch your fingers to the random media next track keyboard button.

# **🎨 Theme**
You can change the background color, text color and accent color. Also QuickMenu has a slight gradient in the middle, you can change the opacity as well.

You can pick between predefined colors or your own colors.

# **🎶 Audio**
A main reason I've made this app is to easily manage Audio. You can easily switch between output devices, change volume from hotkeys by moving your mouse and modify specific app volume.

Another reason is to fix Spotify, that listen to all media trigger and acts upon them, I think this is a marketing strategy of "did you wanted music? we are your music". So I made this functions (that you need to enable from settings):
- When you play an app, Tabame will try to mute Spotify.
- When sound comes from other sources, Spotify will pause.
- A dedicated Button on Quick Actions for Spotify, so if you want to play/pause only Spotify, you can use that.

Each app that makes sound has dedicated media control and you can set default `exe`s that will show them by default.

Also you can modify Volume OSD to hide media, make it thinner or hide it completely.


# **⌨️ Hotkeys**
I've tried to make a complex system for hotkeys, with one button you can achieve more.

- Each hotkey has a list of triggers and each trigger is capable of multiple actions.
- You can activate window under cursor so data is sent where you want to.
- You can set a trigger to a specific window by title, exe or class.
- You can set a trigger to a specific region of the window, in pixels or percentage. The region can be anchored in all 4 points of the window.
- The trigger can be:
  - Press
  - Double Press
  - Mouse Movement
    - the trigger can be at the end or while moving.
  - Hold Duration
- You can set a variable check if you need more complexity.

Actions can be:
- Send Keys
- Hotkey
- Tabame Function
- Set Var
- Send Click

Tabame Functions are:
- Toggle Taskbar 
- Toggle Quick Menu
- Show Quick Menu In Center
- Toggle Quick Run
- Show Last Active Window
- Open Audio Settings
- Play Pause Spotify
- Toggle Hidden Files
- Toggle Desktop Files
- Switch Audio Output
- Switch Microphone Input
- Toggle Microphone 
- Switch Desktop To Right
- Switch Desktop To Left

You can set multiple Actions.

Example: With main hotkey, you can open tabame, show previous window, toggle taskbar, open start menu, open `ALT+Z` menu, open new chrome tab, show desktop, change volume level or switch desktops. You do not need to learn new hotkeys for each thing you need.


# **📕 Bookmarks**
Here you can create bookmarks for your projects, docs and other items you need to quick access.

You can bookmark folders, links or commands.

You can create groups and that contains your bookmarks. You can set an emoji for each so you can differentiate between them later when you forgot which is which.

You can access Bookmarks from QuickMenu/Quickrun by typing `b ` then name of the bookmark, like `b tabame`.

For example I've made a group Tabame where I saved command for vscode, release folder, install folder and github page. When I need to open one, rather the navigate manually, I open QuickRun and type `b tabame` and nagivate with arrows.


<img src="https://user-images.githubusercontent.com/20853986/200884861-d761c8bc-6885-43d2-86fe-119c1d6b60e3.png" align="right" width="250" height="auto"
     alt="Trktivity.">
     
# **📝 Trktivity**
Trktivity tracks your activity 🧐. It records keystrokes, mouse pings each 3 seconds and active window exe and title (if you set filters for it). 

You can view stats per day or a set of days. It generates a graph from 00:00 to 24:00.

It generates a timeline for executable you were focused and for Titles you've created filters for.

By default is disabled, you can enable it, all recorded information is stored locally on your Computer and it is not sent anywhere.

# **📅 Tasks**
Tasks consists of Reminders and Page Watchers. 

Reminders can be repetitive or one time per day. You can set which days of the week to be active and for repetitive reminders you can set interval when the reminder is active. You can set to receive Toast Notification or Audio Notification. You can use `xNR` to repeat the message, ex `Workout x3`. 

v1.3: 
- You can create Pesistent Reminders. You will see a warning sign in QuickActions QuickMenu when you receive a new Reminder notification and you need to manually click on it to remove. It's good for meds reminder.
- You can create Interval Reminders at each other $X$ days. For example if you set each other 5 days since Monday, it will trigger on Saturday (+5 days) Thursday (+5 days) Tuesday, etc.

Page watchers will check a link each to see if specific text exists or not. For example if you made a post on a obscure forum and want to know when you receive a reply, you can set the link, 60 second interval and `\d+ Replies` and when that string changes, you will be notified.

# **✨ Wizardly**
Wizardly is a set of tools that works with folders. You can add it in Context Menu for easier access.

## **Find Text In Folder**
You can search text in a folder, recursively. You can use regex, case sensitive or match the whole text only.

Important feature (and why I've made it): You can exclude files/folders, so if you do not want to see results from, for example `node_modules` you can set that in filters. For example Notepad++ and vsCode does not have this feature and it's annoying.


## **Project Overview**

It counts lines of code and makes a summary. **You can ignore folders or only show specific file types**.

It shows code lines, non-code lines (lines with 1-2 chars line `[]{}()`), comment lines and empty lines.

It also calculates how many books you could have written with same characters. It was surprising that this project is equivalent of 7 and a half books.

For example, at this time of writing this README.md, Tabame has `27,191 lines` with `761,698 characters` which is impressive in my opinion because I've written it by myself.

## **Rename Files**
You can rename files in bulk, you can use regex but also Lists. This can be useful when you want to change from **IMG_20220725_121728.jpg** to **25 July 2022.jpg** 

## **Folder Size Scan**
You can scan folders recursively and see each folder size, you can delete folders.

## **Hosts Editor (v1.3)**
You can edit hosts files directly from Tabame! You need Admin Privileges to use this.

# **🧩 Views**
Views is an alternative to PowerToys FancyZones. If presets are not what you need and you need more flexibility, you should try this feature.

It consists of a grid where you can change it's size using scroll wheel. Drag a window, press right click, move the window where you want, hold right click, select a region the release right and left click. When you move again the window, it will regain it's previous size.

**This is not DPI aware. Use PowerToys if you changed your monitor DPI**

## **Workspaces**
With Workspaces you can save current position and size of specific windows, so you can load them easily from QuickMenu QuickActions. 

## **Hooks**
With Hooks you can hook multiple windows together, when you focus one, other will surface as well. You can access this feature by right clicking a window in QuickMenu.

## **Predefined Sizes (v1.2)**
You can register predefined sizes and access then by right clicking a window in QuickMenu. This comes handy when you need specific window sizes such as mobile view or half screen.

Views in actions:

https://user-images.githubusercontent.com/20853986/200880366-2eaca57c-c4f3-4fe0-8b9c-e5729c3ca80b.mp4

# **🧰 QuickActionsMenu**

| You can bind Quick Actions Menu to a hotkey and access functions such as setting specific volume, spotify control, tabame functions, change audio output, and run commands. QuickActionsMenu now includes almost all QuickActions Buttons from QuickMenu. |  <video src="https://user-images.githubusercontent.com/20853986/200881569-5951da57-752f-43a6-9ec4-88463daa2ef8.mp4" width="400px"></video> |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------|

# **📷 Fancyshot**
With Fancyshot you can capture custom screenshots. You can set a background stock image, custom image, capture itself or transparency. Also you can change image padding or background padding and add a watermark.

You can create custom profiles.

You can bind Fancyshot on a hotkey or add it in QuickMenuActions. 

Interface needs to open in order for the image to drawn.

![1666548921040895](https://user-images.githubusercontent.com/20853986/197408844-5a706e3f-685d-49ff-b41f-d45f03ef5da4.png)


# 🙃 Outro
I've started this project to learn Dart and Flutter, in my mind I had only `QuickMenu` features/app, but while writing for it I got new ideas for it, and it ended up `Tabame`, random name I came up with.

## If you find this app useful, you can [buy me a coffee](https://www.buymeacoffee.com/far.se). It would be appreciated 😊.