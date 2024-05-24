function Invoke-CIPPStandardAtpPolicyForO365 {
    <#
    .FUNCTIONALITY
    Internal
    #>

    param($Tenant, $Settings)
    $AtpPolicyForO365State = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AtpPolicyForO365' |
    Select-Object EnableATPForSPOTeamsODB, EnableSafeDocs, AllowSafeDocsOpen

    $StateIsCorrect = if (
        ($AtpPolicyForO365State.EnableATPForSPOTeamsODB -eq $true) -and
        ($AtpPolicyForO365State.EnableSafeDocs -eq $true) -and
        ($AtpPolicyForO365State.AllowSafeDocsOpen -eq $Settings.AllowSafeDocsOpen)
    ) { $true } else { $false }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Atp Policy For O365 already set.' -sev Info
        } else {
            $cmdparams = @{
                EnableATPForSPOTeamsODB = $true
                EnableSafeDocs = $true
                AllowSafeDocsOpen = $Settings.AllowSafeDocsOpen
            }

            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-AntiPhishPolicy' -cmdparams $cmdparams
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Updated Atp Policy For O365' -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Atp Policy For O365. Error: $($_.exception.message)" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Atp Policy For O365 is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Atp Policy For O365 is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'AtpPolicyForO365' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}