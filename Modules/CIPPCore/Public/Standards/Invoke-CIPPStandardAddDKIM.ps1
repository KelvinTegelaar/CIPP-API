function Invoke-CIPPStandardAddDKIM {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    $AllDomains = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/domains' -tenantid $Tenant | Where-Object { $_.supportedServices -contains 'Email' }).id
    $DKIM = (New-ExoRequest -tenantid $tenant -cmdlet 'Get-DkimSigningConfig') | Select-Object Domain, Enabled, Status

    # List of domains for each way to enable DKIM
    $NewDomains = $AllDomains | Where-Object { $DKIM.Domain -notcontains $_ }
    $SetDomains = $DKIM | Where-Object { $AllDomains -contains $_.Domain -and $_.Enabled -eq $false }

    If ($Settings.remediate) {
        $ErrorCounter = 0
        # New-domains
        foreach ($Domain in $NewDomains) {
            try {
                (New-ExoRequest -tenantid $tenant -cmdlet 'New-DkimSigningConfig' -cmdparams @{ KeySize = 2048; DomainName = $Domain; Enabled = $true } -useSystemMailbox $true)
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Enabled DKIM for $Domain" -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable DKIM. Error: $($_.Exception.Message)" -sev Error
                $ErrorCounter++
            }
        }

        # Set-domains
        foreach ($Domain in $SetDomains) {
            try {
                (New-ExoRequest -tenantid $tenant -cmdlet 'Set-DkimSigningConfig' -cmdparams @{ Identity = $Domain.Domain; Enabled = $true } -useSystemMailbox $true)
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Enabled DKIM for $($Domain.Domain)" -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable DKIM. Error: $($_.Exception.Message)" -sev Error
                $ErrorCounter++
            }
        }
        if ($ErrorCounter -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled DKIM for all domains in tenant' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Failed to enable DKIM for all domains in tenant' -sev Error
        }
    }

    if ($Settings.alert) {

        if ($null -eq $NewDomains -and $null -eq $SetDomains) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DKIM is enabled for all available domains' -sev Info
        } else {
            $NoDKIM = ($NewDomains + $SetDomains.Domain) -join ';'
            Write-LogMessage -API 'Standards' -tenant $tenant -message "DKIM is not enabled for: $NoDKIM" -sev Alert
        }
    }
    if ($Settings.report) {
        if ($null -eq $NewDomains -and $null -eq $SetDomains) { $DKIMState = $true } else { $DKIMState = $false }
        Add-CIPPBPAField -FieldName 'DKIM' -FieldValue [bool]$DKIMState -StoreAs bool -Tenant $tenant
    }
}
