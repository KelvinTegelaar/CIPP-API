function Invoke-SyncroAutoMap {
    <#
    .SYNOPSIS
        Auto-maps CIPP tenants to Syncro customers by exact business name.
    .DESCRIPTION
        Syncro customers carry no Microsoft tenant ID, so the only safe match is a customer
        whose business name is exactly the tenant's display name. Existing mappings are never
        overwritten and a name shared by more than one customer is skipped rather than guessed.
        Runs from the mapping page and from the extension timer.
    .PARAMETER CIPPMapping
        The CippMapping table context from Get-CIPPTable.
    #>
    [CmdletBinding()]
    param (
        $CIPPMapping
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ErrorAction Stop).Syncro
    if (-not $Configuration -or [string]::IsNullOrWhiteSpace($Configuration.Subdomain)) {
        return 'Syncro is not configured. Configure the extension before running AutoMap.'
    }

    try {
        $Customers = Get-SyncroCustomer -Configuration $Configuration
    } catch {
        $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
        return "Could not list Syncro customers: $Message"
    }

    $CustomersByName = @{}
    foreach ($Customer in $Customers) {
        $Name = "$(if ($Customer.business_name) { $Customer.business_name } else { $Customer.business_then_name })".Trim()
        if (-not $Name) { continue }
        if (-not $CustomersByName.ContainsKey($Name)) { $CustomersByName[$Name] = [System.Collections.Generic.List[object]]::new() }
        $CustomersByName[$Name].Add($Customer)
    }

    if ($CustomersByName.Count -eq 0) {
        return 'AutoMap found no Syncro customers to match against.'
    }

    $Tenants = Get-Tenants -IncludeErrors
    $MappedTenantIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@((Get-ExtensionMapping -Extension 'Syncro').RowKey), [System.StringComparer]::OrdinalIgnoreCase)

    $Matched = 0
    $AlreadyMapped = 0
    $Unmatched = 0
    $Ambiguous = [System.Collections.Generic.List[string]]::new()

    foreach ($Tenant in $Tenants) {
        if ($MappedTenantIds.Contains("$($Tenant.customerId)")) {
            $AlreadyMapped++
            continue
        }

        $NameMatches = $CustomersByName["$($Tenant.displayName)".Trim()]
        if ($NameMatches.Count -gt 1) {
            $Ambiguous.Add("$($Tenant.displayName) (name shared by $($NameMatches.Count) customers)")
            continue
        }
        if ($NameMatches.Count -ne 1) {
            $Unmatched++
            continue
        }

        $Customer = $NameMatches[0]
        $AddObject = @{
            PartitionKey    = 'SyncroMapping'
            RowKey          = "$($Tenant.customerId)"
            IntegrationId   = "$($Customer.id)"
            IntegrationName = "$(if ($Customer.business_then_name) { $Customer.business_then_name } else { $Customer.business_name })"
        }
        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        Write-LogMessage -API 'SyncroAutoMap' -tenant $Tenant.defaultDomainName -message "Mapped $($Tenant.displayName) to Syncro customer $($AddObject.IntegrationName) by business name match" -Sev 'Info'
        $Matched++
    }

    $Notes = [System.Collections.Generic.List[string]]::new()
    if ($Ambiguous.Count -gt 0) { $Notes.Add("Skipped as ambiguous: $($Ambiguous -join '; ').") }
    if ($Matched -gt 0) {
        Write-LogMessage -API 'SyncroAutoMap' -message "AutoMap complete: $Matched tenant(s) mapped, $AlreadyMapped already mapped, $($Ambiguous.Count) skipped as ambiguous, $Unmatched with no matching Syncro customer" -Sev 'Info'
    }
    return "AutoMap complete: $Matched new tenant mapping(s) added, $($Matched + $AlreadyMapped) tenant(s) mapped in total, $Unmatched unmatched. $($Notes -join ' ')".Trim()
}
