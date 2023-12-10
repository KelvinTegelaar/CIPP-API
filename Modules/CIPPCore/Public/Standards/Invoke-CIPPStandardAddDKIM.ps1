function Invoke-CIPPStandardAddDKIM {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $DKIM = (New-ExoRequest -tenantid $tenant -cmdlet 'Get-DkimSigningConfig') | Where-Object -Property Enabled -EQ $false 
    If ($Settings.remediate) {
        try {
            $DKIM | ForEach-Object {
        (New-ExoRequest -tenantid $tenant -cmdlet 'New-DkimSigningConfig' -cmdparams @{ KeySize = 2048; DomainName = $_.Identity; Enabled = $true } -useSystemMailbox $true)
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled DKIM Setup' -sev Info
    
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable DKIM. Error: $($_.exception.message)" -sev Error
        }
    }

    if ($Settings.alert) {

        if ($DKIM) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DKIM is enabled for all available domains' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DKIM is not enabled for all available domains' -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'DKIM' -FieldValue [bool]$DKIM -StoreAs bool -Tenant $tenant
    }
}
