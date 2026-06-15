function Set-CIPPDBCacheHVEAccounts {
    <#
    .SYNOPSIS
        Caches HVE (High Volume Email) accounts for a tenant

    .PARAMETER TenantFilter
        The tenant to cache HVE accounts for

    .PARAMETER QueueId
        The queue ID to update with total tasks
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching HVE accounts' -sev Debug

        $HVEAccounts = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailUser' -cmdParams @{
            HVEAccount = $true
        } -Select 'DisplayName,PrimarySmtpAddress,ExternalDirectoryObjectId,Alias,WhenCreated,EmailAddresses'

        $Transformed = [System.Collections.Generic.List[PSObject]]::new()

        # Bulk-fetch billing policies for all HVE accounts in a single batched request
        $BillingPolicyMap = @{}
        if ($HVEAccounts.Count -gt 0) {
            $BulkCmdlets = [System.Collections.Generic.List[object]]::new()
            foreach ($HVE in $HVEAccounts) {
                $BulkCmdlets.Add(@{
                        CmdletInput = @{
                            CmdletName = 'Get-HVEAccountBillingPolicy'
                            Parameters = @{ Identity = $HVE.PrimarySmtpAddress }
                        }
                    })
            }
            try {
                $BulkResults = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($BulkCmdlets)
                for ($i = 0; $i -lt $HVEAccounts.Count; $i++) {
                    $Result = $BulkResults[$i]
                    if ($Result.body -and -not $Result.body.error -and $Result.body.value) {
                        $PolicyData = $Result.body.value
                        $BillingPolicyMap[$HVEAccounts[$i].PrimarySmtpAddress] = @{
                            BillingPolicyId   = $PolicyData.BillingPolicyId
                            BillingPolicyName = $PolicyData.BillingPolicyName
                        }
                    }
                }
            } catch {
                Write-Host "Could not bulk-retrieve billing policies: $($_.Exception.Message)"
            }
        }

        foreach ($HVE in $HVEAccounts) {
            $Policy = $BillingPolicyMap[$HVE.PrimarySmtpAddress]

            $Transformed.Add(($HVE | Select-Object `
                    @{ Name = 'displayName'; Expression = { $_.DisplayName } },
                    @{ Name = 'primarySmtpAddress'; Expression = { $_.PrimarySmtpAddress } },
                    @{ Name = 'recipientTypeDetails'; Expression = { 'HVEAccount' } },
                    ExternalDirectoryObjectId,
                    Alias,
                    WhenCreated,
                    @{ Name = 'AdditionalEmailAddresses'; Expression = { ($_.'EmailAddresses' | Where-Object { $_ -clike 'smtp:*' }).Replace('smtp:', '') -join ', ' } },
                    @{ Name = 'BillingPolicyId'; Expression = { if ($Policy.BillingPolicyId) { $Policy.BillingPolicyId } else { $null } } },
                    @{ Name = 'BillingPolicyName'; Expression = { if ($Policy.BillingPolicyName) { $Policy.BillingPolicyName } else { 'None' } } }))
        }

        $Transformed | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'HVEAccounts' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Transformed.Count) HVE accounts successfully" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache HVE accounts: $($_.Exception.Message)" -sev Debug
    }
}
