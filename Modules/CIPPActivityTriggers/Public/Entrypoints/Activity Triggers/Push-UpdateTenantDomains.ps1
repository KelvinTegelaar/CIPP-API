function Push-UpdateTenantDomains {
    <#
    .FUNCTIONALITY
        Entrypoint
    .SYNOPSIS
        Hydrates the domain details for one tenant cache row.
    .DESCRIPTION
        Runs one tenant per invocation: fetches the authoritative domain list, fills
        initialDomainName, and clears RequiresRefresh. Failures leave the row marked for
        the next refresh.
    #>
    Param($Item)

    try {
        $TenantsTable = Get-CippTable -tablename 'Tenants'
        $Row = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and RowKey eq '$($Item.customerId)'"
        if (!$Row) {
            Write-Information "Push-UpdateTenantDomains: no tenant row for $($Item.customerId), skipping."
            return
        }

        $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains?$top=999' -tenantid $Row.customerId -NoAuthCheck:$true -ErrorAction Stop
        $DefaultDomainName = ($Domains | Where-Object { $_.isDefault -eq $true }).id
        $InitialDomainName = ($Domains | Where-Object { $_.isInitial -eq $true }).id

        if ($DefaultDomainName) {
            $Row | Add-Member -MemberType NoteProperty -Name 'defaultDomainName' -Value $DefaultDomainName -Force
        }
        if ($InitialDomainName) {
            $Row | Add-Member -MemberType NoteProperty -Name 'initialDomainName' -Value $InitialDomainName -Force
        }
        $Row | Add-Member -MemberType NoteProperty -Name 'RequiresRefresh' -Value $false -Force
        $Row | Add-Member -MemberType NoteProperty -Name 'LastRefresh' -Value ((Get-Date).ToUniversalTime()) -Force
        Add-CIPPAzDataTableEntity @TenantsTable -Entity $Row -Force | Out-Null
        Write-Information "Push-UpdateTenantDomains: hydrated domains for $($Row.defaultDomainName) ($($Row.customerId))"
    } catch {
        Write-LogMessage -API 'UpdateTenantDomains' -tenant $Item.customerId -message "Failed to hydrate domains for tenant $($Item.customerId) - $($_.Exception.Message)" -Sev 'Warning' -LogData (Get-CippException -Exception $_)
    }
}
