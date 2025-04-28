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
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/teams-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TeamsExternalFileSharing'
    Write-Host "TeamsExternalFileSharing: $($Settings | ConvertTo-Json)"
    $CurrentState = New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Get-CsTeamsClientConfiguration' | Select-Object AllowGoogleDrive, AllowShareFile, AllowBox, AllowDropBox, AllowEgnyte

    $StateIsCorrect = ($CurrentState.AllowGoogleDrive -eq $Settings.AllowGoogleDrive ?? $false ) -and
    ($CurrentState.AllowShareFile -eq $Settings.AllowShareFile ?? $false ) -and
    ($CurrentState.AllowBox -eq $Settings.AllowBox ?? $false ) -and
    ($CurrentState.AllowDropBox -eq $Settings.AllowDropBox ?? $false ) -and
    ($CurrentState.AllowEgnyte -eq $Settings.AllowEgnyte ?? $false )

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Teams External File Sharing already set.' -sev Info
        } else {
            $cmdParams = @{
                Identity         = 'Global'
                AllowGoogleDrive = $Settings.AllowGoogleDrive
                AllowShareFile   = $Settings.AllowShareFile
                AllowBox         = $Settings.AllowBox
                AllowDropBox     = $Settings.AllowDropBox
                AllowEgnyte      = $Settings.AllowEgnyte
            }

            try {
                New-TeamsRequest -TenantFilter $Tenant -Cmdlet 'Set-CsTeamsClientConfiguration' -CmdParams $cmdParams
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

        if ($StateIsCorrect -eq $true) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.TeamsExternalFileSharing' -FieldValue $FieldValue -Tenant $Tenant
    }
}
