function Get-CIPPMailboxForwardingReport {
    <#
    .SYNOPSIS
        Generates a mailbox forwarding report from the CIPP Reporting database

    .DESCRIPTION
        Retrieves mailbox forwarding settings for a tenant from the cached mailbox data.
        Shows mailboxes that have external forwarding, internal forwarding, or both configured.

    .PARAMETER TenantFilter
        The tenant to generate the report for

    .PARAMETER ForwardingOnly
        If specified, only returns mailboxes that have forwarding configured

    .EXAMPLE
        Get-CIPPMailboxForwardingReport -TenantFilter 'contoso.onmicrosoft.com'
        Gets all mailboxes with their forwarding settings

    .EXAMPLE
        Get-CIPPMailboxForwardingReport -TenantFilter 'contoso.onmicrosoft.com' -ForwardingOnly
        Gets only mailboxes that have forwarding configured
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [switch]$ForwardingOnly
    )

    try {
        Write-LogMessage -API 'MailboxForwardingReport' -tenant $TenantFilter -message 'Generating mailbox forwarding report' -sev Debug

        # Handle AllTenants
        if ($TenantFilter -eq 'AllTenants') {
            # Get all tenants that have mailbox data
            $AllMailboxItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'Mailboxes'
            $Tenants = @($AllMailboxItems | Where-Object { $_.RowKey -ne 'Mailboxes-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $TenantResults = Get-CIPPMailboxForwardingReport -TenantFilter $Tenant -ForwardingOnly:$ForwardingOnly
                    foreach ($Result in $TenantResults) {
                        # Add Tenant property to each result
                        $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'MailboxForwardingReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults
        }

        # Get mailboxes from reporting DB
        $MailboxItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_.RowKey -ne 'Mailboxes-Count' }
        if (-not $MailboxItems) {
            throw 'No mailbox data found in reporting database. Sync the mailbox data first.'
        }

        # Get the most recent cache timestamp
        $CacheTimestamp = ($MailboxItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp

        # Parse mailbox data and build report
        $Report = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in $MailboxItems) {
            $Mailbox = $Item.Data | ConvertFrom-Json

            # Determine forwarding status
            $HasExternalForwarding = -not [string]::IsNullOrWhiteSpace($Mailbox.ForwardingSmtpAddress)
            $HasInternalForwarding = -not [string]::IsNullOrWhiteSpace($Mailbox.InternalForwardingAddress)
            $HasAnyForwarding = $HasExternalForwarding -or $HasInternalForwarding

            # Skip mailboxes without forwarding if ForwardingOnly is specified
            if ($ForwardingOnly -and -not $HasAnyForwarding) {
                continue
            }

            # Determine forwarding type for display
            $ForwardingType = if ($HasExternalForwarding -and $HasInternalForwarding) {
                'Both'
            } elseif ($HasExternalForwarding) {
                'External'
            } elseif ($HasInternalForwarding) {
                'Internal'
            } else {
                'None'
            }

            # Build the forward-to address display
            $ForwardTo = if ($HasExternalForwarding) {
                $Mailbox.ForwardingSmtpAddress
            } elseif ($HasInternalForwarding) {
                $Mailbox.InternalForwardingAddress
            } else {
                $null
            }

            $Report.Add([PSCustomObject]@{
                    UPN                        = $Mailbox.UPN
                    DisplayName                = $Mailbox.displayName
                    PrimarySmtpAddress         = $Mailbox.primarySmtpAddress
                    RecipientTypeDetails       = $Mailbox.recipientTypeDetails
                    ForwardingType             = $ForwardingType
                    ForwardTo                  = $ForwardTo
                    ForwardingSmtpAddress      = $Mailbox.ForwardingSmtpAddress
                    InternalForwardingAddress  = $Mailbox.InternalForwardingAddress
                    DeliverToMailboxAndForward = $Mailbox.DeliverToMailboxAndForward
                    HasForwarding              = $HasAnyForwarding
                    Tenant                     = $TenantFilter
                    CacheTimestamp             = $CacheTimestamp
                })
        }

        # Sort by display name
        $Report = $Report | Sort-Object -Property DisplayName

        Write-LogMessage -API 'MailboxForwardingReport' -tenant $TenantFilter -message "Generated forwarding report with $($Report.Count) entries" -sev Debug
        return $Report

    } catch {
        Write-LogMessage -API 'MailboxForwardingReport' -tenant $TenantFilter -message "Failed to generate mailbox forwarding report: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw "Failed to generate mailbox forwarding report: $($_.Exception.Message)"
    }
}
