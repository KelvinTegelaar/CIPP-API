function Invoke-CIPPStandardAtpPolicyForO365 {
    <#
    .FUNCTIONALITY
    Internal
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
