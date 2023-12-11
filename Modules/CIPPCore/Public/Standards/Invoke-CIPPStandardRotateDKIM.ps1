function Invoke-CIPPStandardRotateDKIM {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $DKIM = (New-ExoRequest -tenantid $tenant -cmdlet 'Get-DkimSigningConfig') | Where-Object { $_.Selector1KeySize -EQ 1024 -and $_.Enabled -eq $true } 
    If ($Settings.remediate) {
        try {
            $DKIM | ForEach-Object {
        (New-ExoRequest -tenantid $tenant -cmdlet 'Rotate-DkimSigningConfig' -cmdparams @{ KeySize = 2048; Identity = $_.Identity } -useSystemMailbox $true)
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Rotated DKIM' -sev Info
    
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to rotate DKIM Error: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        $DKIM | ForEach-Object {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "DKIM is not rotated for $($_.Identity)" -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'DKIM' -FieldValue $DKIM -StoreAs json -Tenant $tenant
    }
}
