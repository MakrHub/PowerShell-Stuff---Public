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

$templatePath = GetTemplatePath
$templatePath