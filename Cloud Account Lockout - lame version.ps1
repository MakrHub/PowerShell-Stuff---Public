#################################
#                               #
#            Cloud              #
#  Account Lockout using Graph  #
#         Mike Gardner          #
#                               #
#################################


#Install Microsoft Graph PowerShell module
$module = Get-InstalledModule Microsoft.Graph -errorAction SilentlyContinue
if ($module -eq $null) {
    Write-Output "Microsoft Graph module is not installed. Installing module..."
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

#get comped user and check if exists
function Get-CompedUser {
    #!!1!ACTIVATE GRAPH POWERS!!!!
    Write-Host("Connect to MS Graph")
    Disconnect-MgGraph -erroraction SilentlyContinue | Out-Null
    Connect-MgGraph -Scopes "Directory.AccessAsUser.All" | Out-Null

    $upn = Read-Host "Enter compromised user's email address (user@domain.com)"
    $upn = $upn.trim()
    $user = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/users/$upn" -Method GET
    $userId = $user.id
    while($userId -eq $null) {
        $upn = Read-Host "User not found, please enter a valid user email address (user@domain.com)"
        $user = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/users/$upn" -Method GET
        $userId = $user.id
    }
    $immutableId = $user.onPremisesImmutableId
    if ($immutableId -ne $null) {
    Write-Host ("This is a synced/hybrid account. Please run the Local AD account lockout script") -ForegroundColor Yellow
    Exit
    }
    else {
        Write-Host "Account is cloud only" -ForegroundColor Cyan
    }
        Add-ToLog("Confirmed user $upn exists and is cloud only")
        return $upn
}

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

#create log file
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
    $logName = "CloudAccountLockout.log"
    $global:logFile = $logPath + '\' + $currentDate + "_ticket_" + $ticketID + "_" + $logName
    New-Item $logFile | Out-Null
}

#write to log file
function Add-ToLog {
    param (
        $someWords
    )
    $someWords | Out-File -FilePath $script:logFile -Append
}

#Lock Account
function Invoke-AccLock {
    $uri = "https://graph.microsoft.com/v1.0/users/$upn"
    $body = @{
        accountEnabled = "false"
    }
    try {
        Invoke-MgGraphRequest -Method PATCH -Uri $uri -Body $body -ErrorAction Stop | Out-Null
        Write-Host("{0}'s account has been locked" -f $upn) -foregroundColor green
        Add-ToLog("$upn's account has been locked")
    }
    catch {
        Write-Host("Unable to lock account, please manually lock the account in 365") -foregroundColor red
        Add-ToLog("Unable to lock account, please manually lock the account in 365")
    }
}

#revoke sign-in sessions and MFA tokens
function Revoke-Sessions {
    param (
        $upn
    )

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
        Write-Host("MFA Tokens cleared for $upn") -foregroundColor green
        Add-ToLog("MFA Tokens cleared for $upn")
    }
    catch {
        Write-Host("Unable to clear MFA Tokens for $upn. Please clear MFA tokens in Azure") -foregroundColor red
        Add-ToLog("Unable to clear MFA Tokens for $upn. Please clear MFA tokens in Azure")
    }
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
    Write-Host("Password is: $password")
    return $password
}

#Set the new password for the user
function Reset-Password {   
    param (
        $upn
    )
    $password = Get-SeededPW
    $uri = "https://graph.microsoft.com/v1.0/users/$upn/passwordProfile"
    $body = @{
        password = $password
    }
    try {
        Invoke-MgGraphRequest -Method PATCH -Uri $uri -Body $body -ErrorAction Stop
        Write-Host("Password reset successfully") -foregroundColor green
        Add-ToLog("Password reset successfully")
    }
    catch {
        Write-Host("Unable to change password, please perform this manually") -foregroundColor red
        Add-ToLog("Unable to reset password, please perform this manually")
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

#unlock account
function Invoke-AccUnlock {
    param (
        $upn
    )
    $uri = "https://graph.microsoft.com/v1.0/users/$upn"
    $body = @{
    accountEnabled = "true"
    }
    try {
        Invoke-MgGraphRequest -Method PATCH -Uri $uri -Body $body
        # Output success message
        Write-Host ("$upn's account has been unlocked.") -foregroundColor green
        Add-ToLog("$upn's account unlocked")
    }
    catch {
        Write-Host ("Unable to unlock account for $upn, please perform this manually in 365") -foregroundColor red
        Add-ToLog("Unable to unlock account for $upn, please perform this manually in 365")
    }
}

#add ticket note
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

#main
function Start-AccLock {
    $ticketID = Get-TicketNum
    New-LogFile($ticketID)
    Add-ToLog("Start of Log`nTicket Number: #$ticketID")
    Write-Host("Connect to the tenant using the Global Admin account") -ForegroundColor Yellow
    $upn = Get-CompedUser
    Start-Sleep -seconds 2
    Invoke-AccLock($upn)
    Start-Sleep -seconds 2
    Revoke-Sessions($upn)
    Start-Sleep -seconds 2
    Reset-Password($upn)
    Start-Sleep -seconds 2
    #twice to clear defaults
    Revoke-AzureMFA($upn)
    Revoke-AzureMFA($upn)
    Start-Sleep -seconds 2
    Invoke-AccUnlock($upn)
    Start-Sleep -seconds 2

    #Prompt before closing
    Write-Host("Account has been locked down. Any Red Text items will likely need to be manually addressed") -ForegroundColor Yellow
    Read-Host ("Copy the password above for $upn and press Enter to exit")
    Add-ToLog("Script finshed and password printed to CLI`nEnd of Log")
    
    $ticketNote = Get-Content $logFile | Out-String
    Add-TicketNote -Note $ticketNote -ticketID $ticketID
    Disconnect-MgGraph | Out-Null
}

# pull the lever Kronk
Start-AccLock