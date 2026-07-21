function Invoke-CIPPStandardTeamsExternalFileSharing {
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
            "CIS M365 5.0 (8.4.1)"
        EXECUTIVETEXT
            Controls which external cloud storage services (like Google Drive, Dropbox, Box) employees can access through Teams, ensuring file sharing occurs only through approved and secure platforms. This helps maintain data governance while supporting necessary business integrations.
        ADDEDCOMPONENT
            {"type":"switch","name":"standards.TeamsExternalFileSharing.AllowGoogleDrive","label":"Allow Google Drive"}
            {"type":"switch","name":"standards.TeamsExternalFileSharing.AllowShareFile","label":"Allow ShareFile"}
            {"type":"switch","name":"standards.TeamsExternalFileSharing.AllowBox","label":"Allow Box"}
            {"type":"switch","name":"standards.TeamsExternalFileSharing.AllowDropBox","label":"Allow Dropbox"}
            {"type":"switch","name":"standards.TeamsExternalFileSharing.AllowEgnyte","label":"Allow Egnyte"}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-07-28
        POWERSHELLEQUIVALENT
            Set-CsTeamsClientConfiguration -AllowGoogleDrive \$false -AllowShareFile \$false -AllowBox \$false -AllowDropBox \$false -AllowEgnyte \$false
        RECOMMENDEDBY
            "CIS"
        REQUIREDCAPABILITIES
            "MCOSTANDARD"
            "MCOEV"
            "MCOIMP"
            "TEAMS1"
            "Teams_Room_Standard"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'TeamsExternalFileSharing' -TenantFilter $Tenant -Preset Teams

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $CurrentState = New-TeamsRequestV2 -TenantFilter $Tenant -Type 'TeamsClientConfiguration' -Action Get -Identity 'Global' |
            Select-Object AllowGoogleDrive, AllowShareFile, AllowBox, AllowDropBox, AllowEgnyte
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the TeamsExternalFileSharing state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Untoggled switches are absent from the settings; default them to $false so we never send null to the ConfigApi
    $AllowGoogleDrive = $Settings.AllowGoogleDrive ?? $false
    $AllowShareFile = $Settings.AllowShareFile ?? $false
    $AllowBox = $Settings.AllowBox ?? $false
    $AllowDropBox = $Settings.AllowDropBox ?? $false
    $AllowEgnyte = $Settings.AllowEgnyte ?? $false

    $StateIsCorrect = ($CurrentState.AllowGoogleDrive -eq $AllowGoogleDrive) -and
    ($CurrentState.AllowShareFile -eq $AllowShareFile) -and
    ($CurrentState.AllowBox -eq $AllowBox) -and
    ($CurrentState.AllowDropBox -eq $AllowDropBox) -and
    ($CurrentState.AllowEgnyte -eq $AllowEgnyte)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams External File Sharing already set.' -sev Info
        } else {
            $cmdParams = @{
                Identity         = 'Global'
                AllowGoogleDrive = $AllowGoogleDrive
                AllowShareFile   = $AllowShareFile
                AllowBox         = $AllowBox
                AllowDropBox     = $AllowDropBox
                AllowEgnyte      = $AllowEgnyte
            }

            try {
                $null = New-TeamsRequestV2 -TenantFilter $Tenant -Type 'TeamsClientConfiguration' -Action Set -Parameters $cmdParams
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
            Write-StandardsAlert -message 'Teams External File Sharing is not set correctly.' -object $CurrentState -tenant $Tenant -standardName 'TeamsExternalFileSharing' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams External File Sharing is not set correctly.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TeamsExternalFileSharing' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant

        $CurrentValue = @{
            AllowGoogleDrive = $CurrentState.AllowGoogleDrive
            AllowShareFile   = $CurrentState.AllowShareFile
            AllowBox         = $CurrentState.AllowBox
            AllowDropBox     = $CurrentState.AllowDropBox
            AllowEgnyte      = $CurrentState.AllowEgnyte
        }
        $ExpectedValue = @{
            AllowGoogleDrive = $AllowGoogleDrive
            AllowShareFile   = $AllowShareFile
            AllowBox         = $AllowBox
            AllowDropBox     = $AllowDropBox
            AllowEgnyte      = $AllowEgnyte
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsExternalFileSharing' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
