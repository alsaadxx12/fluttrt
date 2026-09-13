$desktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
$shortcutPath = Join-Path $desktop "YouTube Pro.lnk"
$target = "C:\Users\Medinat AlElm\Desktop\youtube\build\windows\x64\runner\Release\youtube_downloader.exe"
$workDir = "C:\Users\Medinat AlElm\Desktop\youtube\build\windows\x64\runner\Release"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $target
$shortcut.WorkingDirectory = $workDir
$shortcut.Description = "YouTube & Cinemana Pro"
$shortcut.Save()
Write-Output "Shortcut created successfully on Desktop: $shortcutPath"
