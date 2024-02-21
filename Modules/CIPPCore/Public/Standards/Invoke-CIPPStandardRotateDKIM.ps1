function Invoke-CIPPStandardRotateDKIM {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $DKIM = (New-ExoRequest -tenantid $tenant -cmdlet 'Get-DkimSigningConfig') | Where-Object { $_.Selector1KeySize -Eq 1024 -and $_.Enabled -eq $true } 

    If ($Settings.remediate) {

        $DKIM | ForEach-Object {
            try {
                (New-ExoRequest -tenantid $tenant -cmdlet 'Rotate-DkimSigningConfig' -cmdparams @{ KeySize = 2048; Identity = $_.Identity } -useSystemMailbox $true)
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Rotated DKIM for $($_.Identity)" -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to rotate DKIM Error: $($_.exception.message)" -sev Error
            }
        }
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Rotated DKIM' -sev Info
    }

    if ($Settings.alert) {
        if ($null -eq $DKIM) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DKIM is rotated for all domains' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "DKIM is not rotated for $($DKIM.Identity -join ';')" -sev Alert
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'DKIM' -FieldValue $DKIM -StoreAs json -Tenant $tenant
    }
}
