#Find ADSync server and run AD Sync on it | Credit: https://www.easy365manager.com/how-to-identify-your-azure-ad-connect-server/
$syncServers = Get-ADUser -LDAPFilter "(description=*configured to synchronize to tenant*)" -Properties description | % { $_.description.SubString(142, $_.description.IndexOf(" ", 142) - 142)}
#incase there are multiple results I.E. from a deecommed sync server
foreach ($server in $syncServers)
{
    try {
        Invoke-Command -ComputerName $server -ScriptBlock {Start-ADSyncSyncCycle -PolicyType Delta} -ErrorAction stop
    }
    catch {
        Write-Host("Failed to sync on $server") -ForegroundColor Red
    }
}
