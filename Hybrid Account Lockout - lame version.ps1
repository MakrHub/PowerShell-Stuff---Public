#################################
#                               #
#  AD Account Lockout using PS  #
#         Mike Gardner          #
#                               #
#################################

#Nerdy Function things

#Install Microsoft Graph PowerShell module
$module = Get-InstalledModule Microsoft.Graph -errorAction SilentlyContinue
if ($null -eq $module) {
    Write-Output "Microsoft Graph module is not installed. Installing module..."
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

#Log File
function New-LogFile {
    param (
        $ticketID
    )
    $logPath = "$env:USERPROFILE\Documents\AccountLockoutScript"
    if(!(Test-Path -PathType Container $logPath))
    {
        New-Item -ItemType Directory -Path $logPath | Out-Null
    }
    $currentDate = Get-Date -Format "MM-dd-yyyy_HHmmss"
    $logName = "HybridAccountLockout.log"
    $global:logFile = $logPath + '\' + $currentDate + "_ticket_" + $ticketID + "_" + $logName
    New-Item $logfile | Out-Null
}

#write to log file
function Add-ToLog {
    param (
        $someWords
    )
    $someWords | Out-File -FilePath $script:logFile -Append
}

#Prompt user to enter email address and Ticket ID
#get ticket number to write to ticket notes
function Get-TicketNum {
    $ticketID = Read-Host "Enter a valid ticket number (7 digits, Numbers only)"
    $ticketID = $ticketID.trim()

    While (!($ticketID -match '^\d{7}$')) {
        $ticketID = Read-Host "Enter the VALID ticket NUMBER ONLY please" 
    }
    while ((($ticketID -match '^\d{7}$')) -and ((Check-Ticket -ticketID $ticketID) -ne $Null))
    {
        $ticketID = Read-Host "Enter the VALID ticket NUMBER ONLY please"        
    }   
    return $ticketID
}

#Sync with AzureAD
function Invoke-ADSync {
    #Find ADSync server and run AD Sync on it | Credit: https://www.easy365manager.com/how-to-identify-your-azure-ad-connect-server/
    $syncServers = Get-ADUser -LDAPFilter "(description=*configured to synchronize to tenant*)" -Properties description | % { $_.description.SubString(142, $_.description.IndexOf(" ", 142) - 142)}
    #incase there are multiple results I.E. from a deecommed sync server
    foreach ($server in $syncServers)
    {
        try {
            Invoke-Command -ComputerName $server -ScriptBlock {Start-ADSyncSyncCycle -PolicyType Delta} -ErrorAction stop | Out-Null
            Write-Host("Sync Successfull on $server") -foregroundColor green
            Add-ToLog("Sync Successfull on $server")
        }
        catch {
            Write-Host("Failed to sync on $server. This can be ignored if the sync was successful on another server") -ForegroundColor Red
            Add-ToLog("Sync failed on $server. This can be ignored if the sync was successful on another server")
        }
    }
    Start-Sleep -Seconds 2
}

#function to generate a random 20 digit password with special characters
function Get-SeededPW {
    $lowercase = "abcdefghijklmnopqrstuvwxyz"
    $numbers = "0123456789"
    $special = "!@#$%^&*()_+-={}[]|\:;'<>,.?/"
    $random = New-Object System.Random([int]::Parse((Get-Date -Format "fffffff")))
    $chars = $lowercase.ToUpper() + $lowercase + $numbers + $special
    $password = ""
    for ($i = 0; $i -lt 20; $i++) {
        $password += $chars[$random.Next(0, $chars.Length)]
    }
    return $password
}

#get target user info and check if exists
function Get-CompedUser {
    $upn = Read-Host("Enter the compromised user's UPN (user@domain)")
    $upnCheck = Get-ADUser -Filter {userPrincipalName -eq $upn} -Erroraction Continue | Select-Object UserPrincipalName | Out-String
    while ($upnCheck -eq "") {
        Write-Host "User not found or does not exist." -ForegroundColor Red
        Add-ToLog("$upn not found, trying again")
        $upn = Read-Host("Try again")
        $upnCheck = Get-ADUser -Filter {userPrincipalName -eq $upn} -Erroraction Continue | Select-Object UserPrincipalName | Out-String
    }
    Write-Host("UPN Found") -ForegroundColor Green
    Add-ToLog("$upn found")
    return $upn
}

#get user's DistinguishedName for AD Powershell commands
function Get-UserDN {
    param (
        $upn
    )
    $DN = Get-ADUser -Filter {userPrincipalName -eq $upn} -Properties DistinguishedName | Select-Object -ExpandProperty DistinguishedName
    Write-Host("Distiguished Name found $DN") -ForegroundColor Green
    Add-ToLog("Distiquished Name found for $upn : $DN")
    return $DN
}

#clear refresh tokens and revoke sign-ins in Azure
function Revoke-AzureSignIns {
    param (
        $upn
    )

    #!!1!ACTIVATE GRAPH POWERS!!!!
    Disconnect-MgGraph -Erroraction SilentlyContinue | Out-Null 
    Connect-MgGraph -Scopes "Directory.AccessAsUser.All" | Out-Null
    Add-ToLog("Logged into Azure")

    #Revoke SignIns
    $uri = "/beta/users/$upn/revokeSignInSessions"
    try {
        Invoke-MgGraphRequest -Method POST -Uri $uri -ErrorAction Stop | Out-Null
        Write-Host("Sign-in sessions revoked for $upn") -foregroundColor green
        Add-ToLog("Sign-in sessions revoked for $upn")
    }
    catch {
        Write-Host("Unable to revoke sign-in sessions for $upn. Please perform this action in Azure") -foregroundColor red
        Add-ToLog("Unable to revoke sign-in sessions for $upn. Please perform this action in Azure")
    }

    #Revoke all refresh tokens
    $uri = "/beta/users/$upn/invalidateAllRefreshTokens"
    try {
        Invoke-MgGraphRequest -Method POST -Uri $uri -ErrorAction Stop | Out-Null
        Write-Host("Sessions cleared for $upn") -foregroundColor green
        Add-ToLog("Sessions cleared for $upn")
    }
    catch {
        Write-Host("Unable to clear sessions for $upn. Please clear MFA tokens in Azure") -foregroundColor red
        Add-ToLog("Unable to clear sessions for $upn. Please clear MFA tokens in Azure")
    }
}

#clear MFA in Azure
function Revoke-AzureMFA {
    param (
        $upn
    )
    #connect and get User ID
    Connect-MgGraph -Scopes "Directory.AccessAsUser.All" | Out-Null
    $user = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/users/$upn" -Method GET
    $UserId = $user.id

    #change scopes to clear MFA
    Connect-MgGraph -Scopes UserAuthenticationMethod.ReadWrite.All | Out-Null

    # Retrieve strong authentication methods
    $phoneMethods = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/phoneMethods"
    $microsoftAuthenticatorMethods = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/microsoftAuthenticatorMethods"
    $fido2KeyMethods = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/fido2Methods"
    $softwareOauthMethods = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/softwareOathMethods"
    $windowsHelloMethods = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/windowsHelloForBusinessMethods"
    $emailMethods = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/emailMethods"
    # Remove phone methods
    foreach ($method in $phoneMethods.value) {
        Write-Host "Removing phone method $($method.phoneNumber) for user $upn" -ForegroundColor Yellow
        Add-ToLog("Removing phone method $($method.phoneNumber) for user $upn")
        Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/phoneMethods/$($method.id)"
    }
    # Remove Microsoft Authenticator methods
    foreach ($method in $microsoftAuthenticatorMethods.value) {
        Write-Host "Removing Microsoft Authenticator method $($method.displayName) for user $upn" -ForegroundColor Yellow
        Add-ToLog("Removing Microsoft Authenticator method $($method.displayName) for user $upn")
        Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/microsoftAuthenticatorMethods/$($method.id)"
    }
    # Remove FIDO2 key methods
    foreach ($method in $fido2KeyMethods.value) {
        Write-Host "Removing FIDO2 key method $($method.id) for user $upn" -ForegroundColor Yellow
        Add-ToLog("Removing FIDO2 key method $($method.id) for user $upn")
        Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/fido2Methods/$($method.id)"
    }
    # Remove Software Oauth Authentication methods
    foreach ($method in $softwareOauthMethods.value) {
        Write-Host "Removing Software Oauth Authentication method $($method.id) for user $upn" -ForegroundColor Yellow
        Add-ToLog("Removing Software Oauth Authentication method $($method.id) for user $upn")
        Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/softwareOathMethods/$($method.id)"
    }
    # Remove Windows Hello For Business methods
    foreach ($method in $windowsHelloMethods.value) {
        Write-Host "Removing Windows Hello For Business method $($method.id) for user $upn" -ForegroundColor Yellow
        Add-ToLog("Removing Windows Hello For Business method $($method.id) for user $upn")
        Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/windowsHelloForBusinessMethods/$($method.id)"
    }
    # Remove email methods
    foreach ($method in $emailMethods.value) {
        Write-Host "Removing email method $($method.emailAddress) for user $upn" -ForegroundColor Yellow
        Add-ToLog("Removing email method $($method.emailAddress) for user $upn")
        Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/emailMethods/$($method.id)"
    }
}

#change password, disable account, sync, clear tokens and MFA in Azure, re-enable account, sync again
function Invoke-AccLock {
    #Get DEETS!
    $ticketID = Get-TicketNum
    New-LogFile($ticketID)
    Add-ToLog("Start of Log`nTicket Number: #$ticketID")
    $upn = Get-CompedUser    
    $DN = Get-UserDN($upn)
    $password = Get-SeededPW
    #Password Secure String for Set-Pass cmdlet
    $passwordSS = (ConvertTo-SecureString -AsPlainText $password -Force)

    #reset password (try to at least)
    Try {
        Set-ADAccountPassword -Identity $DN -Reset -NewPassword $passwordSS
        Write-Host("Password for $upn has been changed to $password") -ForegroundColor Green
        Add-ToLog("Password for $upn has been changed")
    }
    Catch {
        Write-Host("Unable to reset password for $upn, please try this manually") -ForegroundColor Red
        Add-ToLog("Unable to reset password for $upn, please try this manually")
    }
    Start-Sleep -Seconds 2

    #Disable account
    Try {
        Disable-ADAccount -Identity $DN
        Write-Host("$upn's account disabled") -ForegroundColor Green
        Add-ToLog("$upn's account disabled")
    }
    Catch {
        Write-Host("Unable to disabled $upn's account, please perform this manually") -ForegroundColor Red
        Add-ToLog("Unable to disabled $upn's account, please perform this manually")
    }
    Start-Sleep -Seconds 2

    #sync
    Write-Host("Syncing Changes") -ForegroundColor Cyan
    Invoke-ADSync
    Start-Sleep -Seconds 5

    #revoke Azure sign-ins and tokens
    Write-Host("Clearing Azure tokens and sessions. Please sign-in to Azure with a privleged user") -ForegroundColor Yellow
    Try{
        Revoke-AzureSignIns($upn)
        Write-Host("All sessions for $upn have been revoked") -ForegroundColor Green
    }
    Catch {
        Write-Host("Unable to clear sessions, please perform this manually") -ForegroundColor Red
    }

    #revoke MFA methods in Azure, run twice to clear all then clear defaults
    Revoke-AzureMFA($upn)
    Revoke-AzureMFA($upn)

    #enable account
    Read-Host("Press Enter to re-enable the user account")
    Try {
        Enable-ADAccount -Identity $DN
        Write-Host("Account has been re-enabled") -ForegroundColor Green
        Add-ToLog("Account re-enabled after prompt")
    }
    Catch {
        Write-Host("Unable to re-enable the account, please perform this manually") -ForegroundColor Red
        Add-ToLog("Unable to re-enable the account, please perform this manually")
    }
    Start-Sleep -Seconds 2

    #sync again
    Write-Host("Syncing Changes") -ForegroundColor Cyan
    Invoke-ADSync

    Write-Host("Account has been locked down. Any Red Text items will likely need to be manually addressed") -ForegroundColor Yellow
    Write-Host("New password for $upn is: $password") -ForegroundColor Green
    Add-ToLog("Script finished and password printed to CLI`nEnd of log")
    $ticketNote = Get-Content $logFile | Out-String
    Add-TicketNote -Note $ticketNote -ticketID $ticketID
    Read-Host("Press Enter to close")
    Disconnect-MGGraph | Out-Null
}

#add note to ticket with entire log
function Add-TicketNote {
    param (
        $Note,$ticketID
    )
    $UpdateBody = [pscustomobject]@{
        juicyTicketDetails
    } | ConvertTo-JSON
    Invoke-RestMethod -uri "Juicy Ticket URL" -Method Post -Body $UpdateBody
}

# Check if ticket number is valid and ticket exists
function Check-Ticket ($ticketID){
    $body = @{
        juicyTicketDetails
    } | ConvertTo-JSON
    try {
        Invoke-WebRequest -Uri "Juicy Ticket URL" -Body $body -Method post | Out-Null
    }
        catch {
                $result = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($result)
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                $readerError = Write-Error $reader.ReadToEnd()
        }
    return $readerError
}

#Pull the lever Kronk
Invoke-AccLock