/*

---
### ![views]() Views

My attempt to replicate FancyZones from PowerToys. My main issue was the fact that you need to press ALT to select multiple zones, and to switch layouts you need some shortcuts which you will never remember.

I've fixed that by allowing the user to select multiple zones by holding Right Click and switching layout by spinning the wheel so you don't need to move your other hand.

*/
const String markdownHomeLeft = '''
## ![tabame](logo) Welcome to Tabame
  
The primary purpose of this app is to provide users with a quick and easy way to navigate and access the information they need.

---
### ![quickMenu]() QuickMenu

This is a window management tool that helps you organize and keep track of all your open windows in one place. It's great for keeping your desktop tidy and making sure you don't lose any important information.

You can pin files and apps for quick access, show System Information and quick-run PowerShell Scripts all in one place. Also you can manage your Tray Icons.

Main reason of QuickMenu is to hide taskbar so you can focus on your work: less badges, flashes and notifications.

The primary purpose of QuickMenu is to minimize distractions by hiding the taskbar, reducing badges, flashes, and notifications.

**You can navigate QuickMenu** with Tab and arrows.


##### QuickActions
Quick Actions is a set of predefined tools that give you access to useful functions, such as switching audio output, changing volume or music track, switch Desktop, pin Window and many other.

---
### ![runWindow]() QuickRun

QuickRun has a suite of tools that can be accessed with a prefix. You can start Shortcuts, use Currency Converto, Set Countdown, calculate/convert units and timezones and many other.

You can also access your projects and create new Tasks.

---
### ![wizardly]() Wizardly

A Folder utility that helps you to manage your folders and files. 

- This program allows you to scan folders and sort them by size. You can also delete any folders you want.
- The user may rename folders and files. Regex and list access are granted in order to change, for example, from a number month to the name of the month.
- The user can search for text within files, specifying options such as the filename and which files or folders to ignore.
- You can change the size of images or the file format.
- You can count lines of code in a folder. You can set which files to include or exclude and also exclude lines that contain specific regex or non alphabet characters.


''';
const String markdownHomeRight = '''
## ![tips]() Quick Tips

### **Audio Button**
  - Left Click to open Audio box where you can manage your audio devices and Audio Mixer.
  - Right Click the audio button to switch between audio output.
  - Middle Click to mute.
  - Scroll Wheel to change volume.
### **Media Button**
  - Left Click to Play/Pause audio.
  - Right Click to Skip to Next Track.
  - Middle Click to Skip to Previous Track.
  - Scroll Wheel to change volume.
### **Task Bar Windows**
  - **If you press play/skip on a window and have Spotify open, it will try to block Spotify from Playing.** It works most of the times...
  - Right click opens a window with Actions.
  - Dragging to left or right moves window to specified Virtual Desktop.
  - You can add media controls for a specific app from QuickMenu Settings.
  - Long Press X will try to force close the window.
### **Pinned Apps**
  - If you order them as in your taskbar and press Right Click, it will open the quickjump Menu in Taskbar.  
  - The Windows Shortcut is **Win+Alt+{Number}**

---
### ![remap]() Hotkeys
  You can set custom actions to be performed based on the executable you are hovering, the region on the screen, or in the app, and mouse movement.

  Actions can be other hotkeys, send key sequences or run executable.

---
### ![projects]() Projects
  You can save folders and files to your projects and access them from QuickRun. This comes in handy when you want to open an older project or specific file but don't know the path.

---
### ![trktivty]() Trktivty
  If you are enabling this, it will track your keystroke and mouse movement and make a hourly and daily graph of your activity.
  - Keyboard strokes per minute [Writing]
  - Keyboard writes each 10 seconds per minute [Debugging]
  - Mouse movement each 3 seconds per minute [Testing/Research]

---
### ![tasks]() Tasks

This is a utility that allows you to create tasks such as reminders and Page Watchers.

- Reminders can be customised by day and time.
- With Page Watchers you can watch if a whole web page changes or only a specific text. It's good when you make a forum post on some random site, if a blog has new posts or other uses you might find.

''';
