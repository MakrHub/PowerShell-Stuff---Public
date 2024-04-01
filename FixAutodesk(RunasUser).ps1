#Get and Set Autodesk Env Vars
$autoCAD_version = Read-Host -prompt "Enter the year version of AutoCad (4 numbers)"
$civil3D_version = Read-Host -prompt "Enter the year version of Civil3D (4 numbers)"
$autoCAD_Loc = "Env:LOCALAPPDATA\Autodesk\AutoCAD " + $autoCAD_version + "\R23.0\enu\"
$civil3d_Loc = "Env:LOCALAPPDATA\Autodesk\C3D " + $civil3D_version + "\enu\"
$bCache = "BrowserCache"
$gCache = "GraphicsCache"

#remove AutoDesk Caches
Remove-item -LiteralPath $autoCAD_Loc+$bCache -Force -Recursive
Write-Host "AutoCAD Browser Cache Removed" -ForegroundColor Green
Remove-item -LiteralPath $autoCAD_Loc+$gCache -Force -Recursive
Write-Host "AutoCAD Graphics Cache Removed" -ForegroundColor Green
Remove-item -LiteralPath $civil3d_Loc+$bCache -Force -Recursive
Write-Host "Civil3D Browser Cache Removed" -ForegroundColor Green
Remove-item -LiteralPath $civil3d_Loc+$gCache -Force -Recursive
Write-Host "Civil3D Graphics Cache Removed" -ForegroundColor Green