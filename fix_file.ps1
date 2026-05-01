$filePath = "c:\Users\ratna\Desktop\notsoalone-final2\lib\screens\chat_room_screen.dart"
$content = [System.IO.File]::ReadAllText($filePath)
$content = $content.Replace("\r`r`n", "`r`n")
[System.IO.File]::WriteAllText($filePath, $content)
Write-Host "Fixed line endings"
