function Invoke-CIPPStandardAtpPolicyForO365 {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AtpPolicyForO365
    .SYNOPSIS
        (Label) Default Atp Policy For O365
    .DESCRIPTION
        (Helptext) This creates a Atp policy that enables Defender for Office 365 for Sharepoint, OneDrive and Microsoft Teams.
        (DocsDescription) This creates a Atp policy that enables Defender for Office 365 for Sharepoint, OneDrive and Microsoft Teams.
    .NOTES
        CAT
            Defender Standards
        TAG
            "lowimpact"
            "CIS"
        ADDEDCOMPONENT
            {"type":"boolean","label":"Allow people to click through Protected View even if Safe Documents identified the file as malicious","name":"standards.AtpPolicyForO365.AllowSafeDocsOpen","default":false}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-AtpPolicyForO365
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AtpPolicyForO365' |
        Select-Object EnableATPForSPOTeamsODB, EnableSafeDocs, AllowSafeDocsOpen

    $StateIsCorrect = ($CurrentState.EnableATPForSPOTeamsODB -eq $true) -and
                      ($CurrentState.EnableSafeDocs -eq $true) -and
                      ($CurrentState.AllowSafeDocsOpen -eq $Settings.AllowSafeDocsOpen)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Atp Policy For O365 already set.' -sev Info
        } else {
            $cmdparams = @{
                EnableATPForSPOTeamsODB = $true
                EnableSafeDocs          = $true
                AllowSafeDocsOpen       = $Settings.AllowSafeDocsOpen
            }

            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-AtpPolicyForO365' -cmdparams $cmdparams -UseSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Atp Policy For O365' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Atp Policy For O365. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Atp Policy For O365 is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Atp Policy For O365 is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'AtpPolicyForO365' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
