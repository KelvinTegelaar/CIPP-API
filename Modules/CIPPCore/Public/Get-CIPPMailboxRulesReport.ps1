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

        $RulesByTenant = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxRules' -ByTenant
        if ($TenantFilter -ne 'AllTenants' -and $RulesByTenant.Count -eq 0) {
            throw 'No mailbox rules data found in reporting database. Sync the report data first.'
        }

        $AllRules = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in @($RulesByTenant.Keys)) {
            # Take each tenant's rows and drop them here so they can be freed once processed
            $RulesItems = $RulesByTenant[$Tenant]; $RulesByTenant[$Tenant] = $null
            $CacheTimestamp = ($RulesItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
            foreach ($Item in $RulesItems) {
                $Rule = $Item.Data | ConvertFrom-Json
                $RuleProps = [ordered]@{ CacheTimestamp = $CacheTimestamp }
                if (-not $Rule.Tenant) {
                    $RuleProps['Tenant'] = $Tenant
                }
                $Rule | Add-Member -NotePropertyMembers $RuleProps -Force -ErrorAction SilentlyContinue
                $AllRules.Add($Rule)
            }
        }

        return $AllRules

    } catch {
        Write-LogMessage -API 'MailboxRulesReport' -tenant $TenantFilter -message "Failed to get mailbox rules report: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw $_
    }
}
