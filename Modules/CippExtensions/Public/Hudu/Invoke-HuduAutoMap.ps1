function Invoke-HuduAutoMap {
    <#
    .SYNOPSIS
        Auto-maps CIPP tenants to Hudu companies through their HaloPSA client, then by exact company name
    .DESCRIPTION
        Hudu companies synced from HaloPSA carry the Halo client ID in their 'halo' integration. A tenant
        mapped to a Halo client in CIPP is matched to the Hudu company holding that client ID. Tenants
        without one fall back to a Hudu company whose name exactly matches the tenant display name.
        Existing mappings are never overwritten. Runs from the mapping page and from the extension timer.
    .PARAMETER CIPPMapping
        The CippMapping table context from Get-CIPPTable
    #>
    [CmdletBinding()]
    param (
        $CIPPMapping
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ErrorAction Stop
    if (!$Configuration.Hudu.BaseURL) {
        return 'Hudu is not configured. Configure the extension before running AutoMap.'
    }

    try {
        Connect-HuduAPI -configuration $Configuration
        $Companies = @(Get-HuduCompanies)
    } catch {
        $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
        return "Could not get Hudu companies: $Message"
    }

    $CompaniesByHaloId = @{}
    $CompaniesByName = @{}
    foreach ($Company in $Companies) {
        if ($Company.archived -eq $true) { continue }
        foreach ($Integration in $Company.integrations) {
            if ($Integration.integrator_name -ne 'halo' -or !$Integration.sync_id) { continue }
            $HaloId = "$($Integration.sync_id)"
            if (!$CompaniesByHaloId.ContainsKey($HaloId)) { $CompaniesByHaloId[$HaloId] = [System.Collections.Generic.List[object]]::new() }
            $CompaniesByHaloId[$HaloId].Add($Company)
        }
        $Name = "$($Company.name)".Trim()
        if (!$Name) { continue }
        if (!$CompaniesByName.ContainsKey($Name)) { $CompaniesByName[$Name] = [System.Collections.Generic.List[object]]::new() }
        $CompaniesByName[$Name].Add($Company)
    }

    $HaloClientByTenant = @{}
    foreach ($HaloMapping in Get-ExtensionMapping -Extension 'Halo') {
        if ($HaloMapping.IntegrationId) { $HaloClientByTenant["$($HaloMapping.RowKey)"] = "$($HaloMapping.IntegrationId)" }
    }

    $Tenants = Get-Tenants -IncludeErrors
    $MappedTenantIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@((Get-ExtensionMapping -Extension 'Hudu').RowKey), [System.StringComparer]::OrdinalIgnoreCase)

    $Matched = 0
    $AlreadyMapped = 0
    $Unmatched = 0
    $Ambiguous = [System.Collections.Generic.List[string]]::new()

    foreach ($Tenant in $Tenants) {
        if ($MappedTenantIds.Contains("$($Tenant.customerId)")) {
            $AlreadyMapped++
            continue
        }

        $HaloId = $HaloClientByTenant["$($Tenant.customerId)"]
        $HaloMatches = if ($HaloId) { $CompaniesByHaloId[$HaloId] }
        $NameMatches = $CompaniesByName["$($Tenant.displayName)".Trim()]

        if ($HaloMatches.Count -gt 1) {
            $Ambiguous.Add("$($Tenant.displayName) (HaloPSA client $HaloId on $($HaloMatches.Count) companies)")
            continue
        } elseif ($HaloMatches.Count -eq 1) {
            $Company = $HaloMatches[0]
            $MatchType = 'HaloPSA client'
        } elseif ($NameMatches.Count -gt 1) {
            $Ambiguous.Add("$($Tenant.displayName) (name shared by $($NameMatches.Count) companies)")
            continue
        } elseif ($NameMatches.Count -eq 1) {
            $Company = $NameMatches[0]
            $MatchType = 'company name'
        } else {
            $Unmatched++
            continue
        }

        $AddObject = @{
            PartitionKey    = 'HuduMapping'
            RowKey          = "$($Tenant.customerId)"
            IntegrationId   = "$($Company.id)"
            IntegrationName = "$($Company.name)"
            SyncPasswords   = $true
        }
        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        Write-LogMessage -API 'HuduAutoMap' -tenant $Tenant.defaultDomainName -message "Mapped $($Tenant.displayName) to Hudu company $($Company.name) by $MatchType match" -Sev 'Info'
        $Matched++
    }

    $Notes = if ($Ambiguous.Count -gt 0) { "Skipped as ambiguous: $($Ambiguous -join '; ')." }
    if ($Matched -gt 0) {
        Register-CIPPExtensionScheduledTasks
        Write-LogMessage -API 'HuduAutoMap' -message "AutoMap complete: $Matched tenant(s) mapped, $AlreadyMapped already mapped, $($Ambiguous.Count) skipped as ambiguous, $Unmatched with no matching Hudu company" -Sev 'Info'
    }
    return "AutoMap complete: $Matched new tenant mapping(s) added, $($Matched + $AlreadyMapped) tenant(s) mapped in total, $Unmatched unmatched. $Notes".Trim()
}
