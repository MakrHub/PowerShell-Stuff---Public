# Get all mailbox users
$mailboxUsers = Get-Mailbox -ResultSize Unlimited

# Create an empty array to store the results
$results = @()

# Iterate through each mailbox user
foreach ($user in $mailboxUsers) {
    $mailbox = $user.UserPrincipalName

    # Get inbox rules for the mailbox
    $rules = Get-InboxRule -Mailbox $mailbox

    # Check if any inbox rules exist
    if ($rules) {
        Write-Host "Inbox rules found for user: $mailbox"

        # Iterate through each rule and add the details to the results array
        foreach ($rule in $rules) {
            $result = [PSCustomObject] @{
                "User" = $mailbox
                "RuleName" = $rule.Name
                "Description" = $rule.Description
                "Enabled" = $rule.Enabled
                "Actions" = $rule.Actions
                "Exceptions" = $rule.Exceptions
            }
            $rule | Format-List -Property *
            # Add the result to the array
            $results += $result
        }
    } else {
        Write-Host "No inbox rules found for user: $mailbox"
    }
}

# Export the results to a CSV file
#$results | Export-Csv -Path "<Destination>\OutputFile.csv" -NoTypeInformation