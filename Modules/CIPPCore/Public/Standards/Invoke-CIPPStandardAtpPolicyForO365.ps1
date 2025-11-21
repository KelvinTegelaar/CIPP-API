function Invoke-CIPPStandardAtpPolicyForO365 {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AtpPolicyForO365
    .SYNOPSIS
        (Label) Default Atp Policy For O365
    .DESCRIPTION
        (Helptext) This creates a Atp policy that enables Defender for Office 365 for SharePoint, OneDrive and Microsoft Teams.
        (DocsDescription) This creates a Atp policy that enables Defender for Office 365 for SharePoint, OneDrive and Microsoft Teams.
    .NOTES
        CAT
            Defender Standards
        TAG
            "CIS M365 5.0 (2.1.5)"
            "NIST CSF 2.0 (DE.CM-09)"
        ADDEDCOMPONENT
            {"type":"switch","label":"Allow people to click through Protected View even if Safe Documents identified the file as malicious","name":"standards.AtpPolicyForO365.AllowSafeDocsOpen","defaultValue":false,"required":false}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-03-25
        POWERSHELLEQUIVALENT
            Set-AtpPolicyForO365
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'AtpPolicyForO365' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'SHAREPOINTENTERPRISE_EDU', 'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'AtpPolicyForO365'

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.
    try {
        $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AtpPolicyForO365' |
            Select-Object EnableATPForSPOTeamsODB, EnableSafeDocs, AllowSafeDocsOpen
    } catch {
        $CurrentState = @{
            License = 'This tenant might not be licensed for this feature'
        }
    }
    $StateIsCorrect = ($CurrentState.EnableATPForSPOTeamsODB -eq $true) -and
    ($CurrentState.EnableSafeDocs -eq $true) -and
    ($CurrentState.AllowSafeDocsOpen -eq $Settings.AllowSafeDocsOpen)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Atp Policy For O365 already set.' -sev Info
        } else {
            $cmdParams = @{
                EnableATPForSPOTeamsODB = $true
                EnableSafeDocs          = $true
                AllowSafeDocsOpen       = $Settings.AllowSafeDocsOpen
            }

            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-AtpPolicyForO365' -cmdParams $cmdParams -UseSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Atp Policy For O365' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Atp Policy For O365. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Atp Policy For O365 is enabled' -sev Info
        } else {
            Write-StandardsAlert -message 'Atp Policy For O365 is not enabled' -object $CurrentState -tenant $Tenant -standardName 'AtpPolicyForO365' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Atp Policy For O365 is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $StateIsCorrect -eq $true ? $true : $CurrentState
        Set-CIPPStandardsCompareField -FieldName 'standards.AtpPolicyForO365' -FieldValue $state -TenantFilter $tenant
        Add-CIPPBPAField -FieldName 'AtpPolicyForO365' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
