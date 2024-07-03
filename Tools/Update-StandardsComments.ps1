<#
.SYNOPSIS
    This script updates the comment block in the CIPP standard files.

.DESCRIPTION
    The script reads the standards.json file and updates the comment block in the corresponding CIPP standard files.
    It adds or modifies the comment block based on the properties defined in the standards.json file.
    This is made to be able to generate the help documentation for the CIPP standards automatically.

.INPUTS
    None. You cannot pipe objects to this script.

.OUTPUTS
    None. The script modifies the CIPP standard files directly.

.EXAMPLE
    Update-StandardsComments.ps1

    This example runs the script to update the comment block in the CIPP standard files.

#>
param (
    [switch]$WhatIf
)

# Find the paths to the standards.json file based on the current script path
$StandardsJSONPath = Split-Path (Split-Path $PSScriptRoot)
$StandardsJSONPath = Resolve-Path "$StandardsJSONPath\*\src\data\standards.json"
$StandardsInfo = Get-Content -Path $StandardsJSONPath | ConvertFrom-Json -Depth 10

foreach ($Standard in $StandardsInfo) {

    # Calculate the standards file name and path
    $StandardFileName = $Standard.name -replace 'standards.', 'Invoke-CIPPStandard'
    $StandardsFilePath = Resolve-Path "$(Split-Path $PSScriptRoot)\Modules\CIPPCore\Public\Standards\$StandardFileName.ps1"
    if (-not (Test-Path $StandardsFilePath)) {
        Write-Host "No file found for standard $($Standard.name)" -ForegroundColor Yellow
        continue
    }
    $Content = Get-Content -Path $StandardsFilePath -Raw

    # Regex to match the existing comment block
    $Regex = '<#(.|\n)*?\.FUNCTIONALITY\s*Internal(.|\n)*?#>'

    if ($Content -match $Regex) {
        $NewComment = [System.Collections.Generic.List[string]]::new()
        # Add the initial scatic comments
        $NewComment.Add("<#`n")
        $NewComment.Add("   .FUNCTIONALITY`n")
        $NewComment.Add("   Internal`n")
        $NewComment.Add("   .APINAME`n")
        $NewComment.Add("   $($Standard.name -replace 'standards.', '')`n")

        # Loop through the properties of the standard and add them to the comment block
        foreach ($Property in $Standard.PSObject.Properties) {
            if ($Property.Name -eq 'name') { continue }
            if ($Property.Name -eq 'impactColour') { continue }

            # If the property is docsDescription and is empty, use the helpText instead
            if ($Property.Name -eq 'docsDescription' -and ([string]::IsNullOrWhiteSpace($Property.Value))) {
                $NewComment.Add("   .$('docsDescription'.ToUpper())`n")
                $NewComment.Add("   $($Standard.helpText.ToString())`n")
                continue
            }

            $NewComment.Add("   .$($Property.Name.ToUpper())`n")
            # Flatten objects to JSON
            if ($Property.Value -is [System.Object[]]) {
                foreach ($Value in $Property.Value) {
                    $NewComment.Add("   $(ConvertTo-Json -InputObject $Value -Depth 5 -Compress)`n")
                }
                continue
            }
            $NewComment.Add("   $($Property.Value.ToString())`n")
        }

        # Add DOCSDESCRIPTION if it doesn't exist
        if ($NewComment -notcontains '.DOCSDESCRIPTION') {
            $NewComment.Add("   .DOCSDESCRIPTION`n")
            $NewComment.Add("   $($Standard.helpText.ToString())`n")
        }
        # Add header about how to update the comment block with this script
        $NewComment.Add("   .UPDATECOMMENTBLOCK`n")
        $NewComment.Add("   Run the Tools\Update-StandardsComments.ps1 script to update this comment block`n")
        $NewComment.Add("   #>`n")

        # Write the new comment block to the file
        if ($WhatIf.IsPresent) {
            Write-Host "Would update $StandardsFilePath with the following comment block:"
            $NewComment
        } else {
            $Content -replace $Regex, $NewComment | Set-Content -Path $StandardsFilePath
        }
    } else {
        Write-Host "No comment block found in $StandardsFilePath" -ForegroundColor Yellow
    }
}
