Function Invoke-CIPPStandardTeamsExternalFileSharing {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TeamsExternalFileSharing
    .SYNOPSIS
        (Label) Define approved cloud storage services for external file sharing in Teams
    .DESCRIPTION
        (Helptext) Ensure external file sharing in Teams is enabled for only approved cloud storage services.
        (DocsDescription) Ensure external file sharing in Teams is enabled for only approved cloud storage services.
    .NOTES
        CAT
            Teams Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"boolean","name":"standards.TeamsExternalFileSharing.AllowGoogleDrive","label":"Allow Google Drive"}
            {"type":"boolean","name":"standards.TeamsExternalFileSharing.AllowShareFile","label":"Allow ShareFile"}
            {"type":"boolean","name":"standards.TeamsExternalFileSharing.AllowBox","label":"Allow Box"}
            {"type":"boolean","name":"standards.TeamsExternalFileSharing.AllowDropBox","label":"Allow Dropbox"}
            {"type":"boolean","name":"standards.TeamsExternalFileSharing.AllowEgnyte","label":"Allow Egnyte"}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-CsTeamsClientConfiguration -AllowGoogleDrive \$false -AllowShareFile \$false -AllowBox \$false -AllowDropBox \$false -AllowEgnyte \$false
        RECOMMENDEDBY
            "CIS 3.0"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TeamsExternalFileSharing'

    $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsClientConfiguration'
    | Select-Object AllowGoogleDrive, AllowShareFile, AllowBox, AllowDropBox, AllowEgnyte

    if ($null -eq $Settings.AllowGoogleDrive) { $Settings.AllowGoogleDrive = $false }
    if ($null -eq $Settings.AllowShareFile) { $Settings.AllowShareFile = $false }
    if ($null -eq $Settings.AllowBox) { $Settings.AllowBox = $false }
    if ($null -eq $Settings.AllowDropBox) { $Settings.AllowDropBox = $false }
    if ($null -eq $Settings.AllowEgnyte) { $Settings.AllowEgnyte = $false }

    $StateIsCorrect = ($CurrentState.AllowGoogleDrive -eq $Settings.AllowGoogleDrive) -and
                      ($CurrentState.AllowShareFile -eq $Settings.AllowShareFile) -and
                      ($CurrentState.AllowBox -eq $Settings.AllowBox) -and
                      ($CurrentState.AllowDropBox -eq $Settings.AllowDropBox) -and
                      ($CurrentState.AllowEgnyte -eq $Settings.AllowEgnyte)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams External File Sharing already set.' -sev Info
        } else {
            $cmdparams = @{
                AllowGoogleDrive = $Settings.AllowGoogleDrive
                AllowShareFile   = $Settings.AllowShareFile
                AllowBox         = $Settings.AllowBox
                AllowDropBox     = $Settings.AllowDropBox
                AllowEgnyte      = $Settings.AllowEgnyte
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsClientConfiguration' -CmdParams $cmdparams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Teams External File Sharing' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Teams External File Sharing. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams External File Sharing is set correctly.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams External File Sharing is not set correctly.' -sev Alert
        }
    }

    if ($Setings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TeamsExternalFileSharing' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
