function Invoke-CIPPStandardAddDKIM {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AddDKIM
    .SYNOPSIS
        (Label) Enables DKIM for all domains that currently support it
    .DESCRIPTION
        (Helptext) Enables DKIM for all domains that currently support it
        (DocsDescription) Enables DKIM for all domains that currently support it
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2023-03-14
        POWERSHELLEQUIVALENT
            New-DkimSigningConfig and Set-DkimSigningConfig
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#low-impact
    #>

    param($Tenant, $Settings)
    #$Rerun -Type Standard -Tenant $Tenant -API 'AddDKIM' -Settings $Settings


    $DkimRequest = @(
        @{
            CmdletInput = @{
                CmdletName = 'Get-AcceptedDomain'
                Parameters = @{}
            }
        },
        @{
            CmdletInput = @{
                CmdletName = 'Get-DkimSigningConfig'
                Parameters = @{}
            }
        }
    )

    $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray $DkimRequest -useSystemMailbox $true

    # Check for errors in the batch results. Cannot continue if there are errors.
    $ErrorCounter = 0
    $ErrorMessages = [System.Collections.Generic.List[string]]::new()
    $BatchResults | ForEach-Object {
        if ($_.error) {
            $ErrorCounter++
            $ErrorMessage = Get-NormalizedError -Message $_.error
            $ErrorMessages.Add($ErrorMessage)
        }
    }
    if ($ErrorCounter -gt 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to get DKIM config. Error: $($ErrorMessages -join ', ')" -sev Error
        return
    }


    $AllDomains = ($BatchResults | Where-Object { $_.DomainName }).DomainName
    $DKIM = $BatchResults | Where-Object { $_.Domain } | Select-Object Domain, Enabled, Status

    # List of domains for each way to enable DKIM
    $NewDomains = $AllDomains | Where-Object { $DKIM.Domain -notcontains $_ }
    $SetDomains = $DKIM | Where-Object { $AllDomains -contains $_.Domain -and $_.Enabled -eq $false }

    If ($Settings.remediate -eq $true) {

        if ($null -eq $NewDomains -and $null -eq $SetDomains) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'DKIM is already enabled for all available domains.' -sev Info
        } else {
            $ErrorCounter = 0
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Trying to enable DKIM for:$($NewDomains -join ', ' ) $($SetDomains.Domain -join ', ')" -sev Info

            # New-domains
            $Request = $NewDomains | ForEach-Object {
                @{
                    CmdletInput = @{
                        CmdletName = 'New-DkimSigningConfig'
                        Parameters = @{ KeySize = 2048; DomainName = $_; Enabled = $true }
                    }
                }
            }
            if ($null -ne $Request) { $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($Request) -useSystemMailbox $true }
            $BatchResults | ForEach-Object {
                if ($_.error) {
                    $ErrorCounter ++
                    $ErrorMessage = Get-NormalizedError -Message $_.error
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable DKIM. Error: $ErrorMessage" -sev Error
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
            if ($null -ne $Request) { $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($Request) -useSystemMailbox $true }
            $BatchResults | ForEach-Object {
                if ($_.error) {
                    $ErrorCounter ++
                    $ErrorMessage = Get-NormalizedError -Message $_.error
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set DKIM. Error: $ErrorMessage" -sev Error
                }
            }

            if ($ErrorCounter -eq 0) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Enabled DKIM for all domains in tenant' -sev Info
            } elseif ($ErrorCounter -gt 0 -and $ErrorCounter -lt ($NewDomains.Count + $SetDomains.Count)) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Failed to enable DKIM for some domains in tenant' -sev Error
            } else {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Failed to enable DKIM for all domains in tenant' -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($null -eq $NewDomains -and $null -eq $SetDomains) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DKIM is enabled for all available domains' -sev Info
        } else {
            $NoDKIM = ($NewDomains + $SetDomains.Domain) -join ';'
            Write-StandardsAlert -message "DKIM is not enabled for: $NoDKIM" -object @{NewDomains = $NewDomains; SetDomains = $SetDomains } -tenant $tenant -standardName 'AddDKIM' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "DKIM is not enabled for: $NoDKIM" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $DKIMState = if ($null -eq $NewDomains -and $null -eq $SetDomains) { $true } else { $SetDomains, $NewDomains }
        Set-CIPPStandardsCompareField -FieldName 'standards.AddDKIM' -FieldValue $DKIMState -TenantFilter $tenant
        Add-CIPPBPAField -FieldName 'DKIM' -FieldValue $DKIMState -StoreAs bool -Tenant $tenant
    }
}
