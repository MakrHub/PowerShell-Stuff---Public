# need Az.OperationalInsights, Az.SecurityInsights, Az.Accounts

<#
 Use a lighthouse connection to all clients to 
 search and remove analytics rules based on rule name
#>

#connect
Connect-AzAccount | Out-Null

$subs = Get-AzSubscription | ogv -Title "Selct all Client Subscriptions you would like to deploy this rule to" -PassThru
foreach ($sub in $subs)
{
    Select-AzSubscription $sub.SubscriptionId | Out-Null
    $subName = $sub.Name
    #select RG
    $rg = Get-AzResourceGroup | Select-Object ResourceGroupName | ogv -Title "Select Sentinel Resource Group for $subName" -PassThru
    $rgName = $rg.ResourceGroupName
    #select Workspace
    $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $rgName | Select-Object Name | ogv -Title "Select Workspace that contains Sentinel from $rgName" -PassThru
    $workspaceName = $workspace.Name
    
    $ruleName = Read-Host ("Enter the name of the rule you would like to remove from the selected tenants")
    $rule = Get-AzSentinelAlertRule -ResourceGroupName $rgName -WorkspaceName $workspaceName | Where-Object {$_.DisplayName -like $ruleName}
    $ruleName = $rule.DisplayName
    $ruleID = $rule.Name
    
    Try {
        Remove-AzSentinelAlertRule -ResourceGroupName $rgName -RuleId $ruleID -WorkspaceName $workspaceName
        "$ruleName Removed from $workspaceName at $subName"
    }
    Catch {
        $_
    }
}