function Get-CIPPMailboxRulesReport {
    <#
    .SYNOPSIS
        Generates a mailbox rules report from the CIPP Reporting database

    .DESCRIPTION
        Retrieves mailbox rules data for a tenant from the reporting database

    .PARAMETER TenantFilter
        The tenant to generate the report for

    .EXAMPLE
        Get-CIPPMailboxRulesReport -TenantFilter 'contoso.onmicrosoft.com'
        Gets mailbox rules for all users in the tenant
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {

        # Handle AllTenants
        if ($TenantFilter -eq 'AllTenants') {
            # Get all tenants that have mailbox rules data
            $AllRulesItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'MailboxRules'
            $Tenants = @($AllRulesItems | Where-Object { $_.RowKey -ne 'MailboxRules-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $TenantResults = Get-CIPPMailboxRulesReport -TenantFilter $Tenant
                    foreach ($Result in $TenantResults) {
                        # Add Tenant property to each result if not already present
                        if (-not $Result.Tenant) {
                            $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        }
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'MailboxRulesReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults
        }

        # Get mailbox rules from reporting DB
        $RulesItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxRules' | Where-Object { $_.RowKey -ne 'MailboxRules-Count' }
        if (-not $RulesItems) {
            throw 'No mailbox rules data found in reporting database. Sync the report data first.'
        }

        # Get the most recent cache timestamp
        $CacheTimestamp = ($RulesItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp

        # Parse mailbox rules data
        $AllRules = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in $RulesItems | Where-Object { $_.RowKey -ne 'MailboxRules-Count' }) {
            $Rule = $Item.Data | ConvertFrom-Json

            # Add cache timestamp to the rule
            $Rule | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force -ErrorAction SilentlyContinue

            # Ensure Tenant property is set
            if (-not $Rule.Tenant) {
                $Rule | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $TenantFilter -Force -ErrorAction SilentlyContinue
            }

            $AllRules.Add($Rule)
        }

        return $AllRules

    } catch {
        Write-LogMessage -API 'MailboxRulesReport' -tenant $TenantFilter -message "Failed to get mailbox rules report: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw $_
    }
}
