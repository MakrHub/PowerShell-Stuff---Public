# Function to check for unquoted service paths and fix them
function Fix-UnquotedServicePaths {
    #get serverices
    $services = Get-WmiObject -Query "SELECT * FROM Win32_Service"
    foreach ($service in $services) {
        $servicePath = $service.PathName
        $serviceName = $service.Name
        $regLoc = "HKLM:\SYSTEM\CurrentControlSet\Services\" # services location
        $regServ = $regLoc + $serviceName
        #check if (servicepath contains white spaces between the start and the executable and that it doesnt contain "C:\Windows" or double quotes) or (servicepath contains whitespaces, is in the .net dir and not includes double quotes
        if (($servicePath -match 'C:\\.*\s.*\.exe' -and -not ($servicePath -match '("|C:\\Windows\\)')) -or ($servicePath -match 'C:\\.*\s.*\.exe' -and $servicePath -match 'C:\\Windows\\Microsoft.NET' -and -not ($servicePath -match '"'))) {
            Write-Output "Service $($service.Name) meets the condition: $servicePath"
            #check for switches in the path that run during execution
            if ($servicePath -match '.*\.exe\s.*') {
                #put quotes only around the path and not the switches
                $startPath = ($servicePath -split ".exe ")[0]
                $switches = ($servicePath -split ".exe ")[1]
                $newPath = "`"$startPath.exe`" $switches"
                #write new quote path to registry
                Set-ItemProperty -Path $regServ -Name "ImagePath" -Value "$newPath"
                Write-Output "Fixed service path for $serviceName to: $newPath"
            }
            else {
                #add quotes around the service path with no switches
                $newPath = "`"$servicePath`""
                Set-ItemProperty -Path $regServ -Name "ImagePath" -Value $newPath
                Write-Output "Fixed service path for $serviceName to: $newPath"
            }
        }
    }
}
Fix-UnquotedServicePaths