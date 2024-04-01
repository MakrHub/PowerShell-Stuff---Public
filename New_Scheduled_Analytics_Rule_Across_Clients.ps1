# need Az.OperationalInsights, Az.SecurityInsights, Az.Accounts

<#
 Use a lighthouse connection to all clients to select and deploy a 
 Scheduled Analytics rule that is based on a JSON template after creating 
 the rule manually and exporting the JSON. Manually intervention is 
 needed to select the Subscriptions->Resource Group->Workspace in which to deploy to Alert
#>

#connect
Connect-AzAccount | Out-Null

function GetTemplatePath {
    Add-Type -AssemblyName System.Windows.Forms

    # Create an OpenFileDialog object
    $fileDialog = New-Object System.Windows.Forms.OpenFileDialog

    # Set properties for the file dialog
    $fileDialog.Title = "Select a File"
    $fileDialog.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*"
    $fileDialog.InitialDirectory = [System.IO.Path]::GetFullPath("C:\")
    
    # Show the file dialog and check if the user clicked OK
    while ($fileDialog.ShowDialog -ne 'OK') {
        if ($fileDialog.ShowDialog() -eq 'OK') {
            # User selected a file, print the selected file path
            $filePath = $fileDialog.FileName
        }
    }
    return $filePath
}

#pull data from exported rule which could be manually created
$templatePath = GetTemplatePath
$RuleTemplate = get-content $templatePath | convertfrom-json 

$TemplateProps = ($RuleTemplate).resources.properties
$ruleDisplayName = $TemplateProps.displayName
$ruleDescription = $TemplateProps.description
$ruleSeverity = $TemplateProps.severity
$ruleQuery = $TemplateProps.query
$ruleTactics = $TemplateProps.tactics
$eventGrouping = $TemplateProps.eventGroupingSettings.aggregationKind