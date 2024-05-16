function Invoke-CIPPStandardAddDKIM {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    $AllDomains = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/domains?$top=999' -tenantid $Tenant | Where-Object { $_.supportedServices -contains 'Email' }).id
    $DKIM = (New-ExoRequest -tenantid $tenant -cmdlet 'Get-DkimSigningConfig') | Select-Object Domain, Enabled, Status

    # List of domains for each way to enable DKIM
    $NewDomains = $AllDomains | Where-Object { $DKIM.Domain -notcontains $_ }
    $SetDomains = $DKIM | Where-Object { $AllDomains -contains $_.Domain -and $_.Enabled -eq $false }

    If ($Settings.remediate -eq $true) {

        if ($null -eq $NewDomains -and $null -eq $SetDomains) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DKIM is already enabled for all available domains.' -sev Info
        } else {
            $ErrorCounter = 0
            # New-domains
            $Request = $NewDomains | ForEach-Object {
                @{
                    CmdletInput = @{
                        CmdletName = 'New-DkimSigningConfig'
                        Parameters = @{ KeySize = 2048; DomainName = $_; Enabled = $true }
                    }
                }
            }

            $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request) -useSystemMailbox $true
            $BatchResults | ForEach-Object {
                if ($_.error) {
                    $ErrorCounter ++
                    $ErrorMessage = Get-NormalizedError -Message $_.error
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable DKIM. Error: $ErrorMessage" -sev Error
                }
            }
            # Set-domains
            $Request = $SetDomains | ForEach-Object {
                @{
                    CmdletInput = @{
                        CmdletName = 'Set-DkimSigningConfig'
                        Parameters = @{ Identity = $Domain.Domain; Enabled = $true }
                    }
                }
            }

            $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request) -useSystemMailbox $true
            $BatchResults | ForEach-Object {
                if ($_.error) {
                    $ErrorMessage = Get-NormalizedError -Message $_.error
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set DKIM. Error: $ErrorMessage" -sev Error
                    $ErrorCounter ++
                }

                if ($ErrorCounter -eq 0) {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled DKIM for all domains in tenant' -sev Info
                } else {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message 'Failed to enable DKIM for all domains in tenant' -sev Error
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($null -eq $NewDomains -and $null -eq $SetDomains) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DKIM is enabled for all available domains' -sev Info
        } else {
            $NoDKIM = ($NewDomains + $SetDomains.Domain) -join ';'
            Write-LogMessage -API 'Standards' -tenant $tenant -message "DKIM is not enabled for: $NoDKIM" -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        $DKIMState = if ($null -eq $NewDomains -and $null -eq $SetDomains) { $true } else { $false }
        Add-CIPPBPAField -FieldName 'DKIM' -FieldValue $DKIMState -StoreAs bool -Tenant $tenant
    }
}
