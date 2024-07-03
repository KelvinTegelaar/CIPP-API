function Invoke-CIPPStandardAddDKIM {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    AddDKIM
    .CAT
    Exchange Standards
    .TAG
    "lowimpact"
    "CIS"
    .HELPTEXT
    Enables DKIM for all domains that currently support it
    .ADDEDCOMPONENT
    .LABEL
    Enables DKIM for all domains that currently support it
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    New-DkimSigningConfig and Set-DkimSigningConfig
    .RECOMMENDEDBY
    "CIS"
    .DOCSDESCRIPTION
    Enables DKIM for all domains that currently support it
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)

    $AllDomains = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/domains?$top=999' -tenantid $Tenant | Where-Object { $_.supportedServices -contains 'Email' -or $_.id -like '*mail.onmicrosoft.com' }).id
    $DKIM = (New-ExoRequest -tenantid $tenant -cmdlet 'Get-DkimSigningConfig') | Select-Object Domain, Enabled, Status

    # List of domains for each way to enable DKIM
    $NewDomains = $AllDomains | Where-Object { $DKIM.Domain -notcontains $_ }
    $SetDomains = $DKIM | Where-Object { $AllDomains -contains $_.Domain -and $_.Enabled -eq $false }

    If ($Settings.remediate -eq $true) {

        if ($null -eq $NewDomains -and $null -eq $SetDomains) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DKIM is already enabled for all available domains.' -sev Info
        } else {
            $ErrorCounter = 0
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Trying to enable DKIM for:$($NewDomains -join ', ' ) $($SetDomains.Domain -join ', ')" -sev Info

            # New-domains
            $Request = $NewDomains | ForEach-Object {
                @{
                    CmdletInput = @{
                        CmdletName = 'New-DkimSigningConfig'
                        Parameters = @{ KeySize = 2048; DomainName = $_; Enabled = $true }
                    }
                }
            }
            if ($null -ne $Request) { $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request) -useSystemMailbox $true }
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
                        Parameters = @{ Identity = $_.Domain; Enabled = $true }
                    }
                }
            }
            if ($null -ne $Request) { $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request) -useSystemMailbox $true }
            $BatchResults | ForEach-Object {
                if ($_.error) {
                    $ErrorCounter ++
                    $ErrorMessage = Get-NormalizedError -Message $_.error
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set DKIM. Error: $ErrorMessage" -sev Error
                }
            }

            if ($ErrorCounter -eq 0) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled DKIM for all domains in tenant' -sev Info
            } elseif ($ErrorCounter -gt 0 -and $ErrorCounter -lt ($NewDomains.Count + $SetDomains.Count)) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Failed to enable DKIM for some domains in tenant' -sev Error
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Failed to enable DKIM for all domains in tenant' -sev Error
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




