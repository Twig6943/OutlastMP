# Build

### Launcher
Since the launcher is written in batch you'll need some batch compiler which you can find [here](https://www.majorgeeks.com/files/details/bat_to_exe_converter.html)

The reason it's compiled is to replace `OutlastLauncher.exe` .

Open bat to exe converter, select `OutlastLauncher.bat` go to Converter > Convert and the output should be `OutlastLauncher.bat` in the same directory.

# UDK

### Prerequisites
- UDK
- make

Make can be installed via [chocolatey](https://chocolatey.org/install) .

UDK can be found [here](https://drive.google.com/file/d/1IZed_3QAivpnU2uPlSClFVs-YOZrIpcd/view).

`"%UDK%" make`

This compiles the UnrealScript source into the `Multiplayer.u` .
