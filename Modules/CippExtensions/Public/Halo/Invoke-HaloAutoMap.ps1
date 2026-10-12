function Invoke-HaloAutoMap {
    <#
    .SYNOPSIS
        Auto-maps CIPP tenants to HaloPSA clients by Azure tenant ID, then by exact client name
    .DESCRIPTION
        HaloPSA's Microsoft 365 integration stores the Azure tenant ID on each client it is
        connected to. Those IDs are exact matches for CIPP's tenant customerId. Tenants with no
        tenant ID match fall back to a HaloPSA client whose name exactly matches the tenant
        display name. Existing mappings are never overwritten. Runs from the mapping page and
        from the extension timer.
    .PARAMETER CIPPMapping
        The CippMapping table context from Get-CIPPTable
    #>
    [CmdletBinding()]
    param (
        $CIPPMapping
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ErrorAction Stop).HaloPSA
    if (!$Configuration.ResourceURL) {
        return 'HaloPSA is not configured. Configure the extension before running AutoMap.'
    }

    try {
        $Token = Get-HaloToken -configuration $Configuration
    } catch {
        $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
        return "Could not authenticate to HaloPSA: $Message"
    }

    $GuidRegex = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    $Headers = @{Authorization = "Bearer $($Token.access_token)" }
    $UserAgent = Get-CippUserAgent
    $Notes = [System.Collections.Generic.List[string]]::new()

    # type=2 connections are Halo's customer-tenant (Microsoft 365) integrations; the
    # connection detail carries the client <-> Azure tenant ID mapping table.
    $ClientsByTenantId = @{}
    try {
        $ConnectionsResponse = Invoke-RestMethod -UserAgent $UserAgent -Uri "$($Configuration.ResourceURL)/AzureADConnection?type=2" -Method GET -ContentType 'application/json' -Headers $Headers
        $Connections = if ($ConnectionsResponse -is [array]) {
            $ConnectionsResponse
        } elseif ($ConnectionsResponse.id) {
            @($ConnectionsResponse)
        } else {
            @($ConnectionsResponse.PSObject.Properties | Where-Object { $_.Value -is [array] } | Select-Object -First 1).Value
        }

        foreach ($Connection in $Connections) {
            $Detail = Invoke-RestMethod -UserAgent $UserAgent -Uri "$($Configuration.ResourceURL)/AzureADConnection/$($Connection.id)?type=2&includedetails=true&includetenants=true" -Method GET -ContentType 'application/json' -Headers $Headers
            foreach ($Entry in $Detail.mappings_client) {
                if ($Entry.azure_tenant_id -notmatch $GuidRegex -or !$Entry.client_id) { continue }
                if (!$ClientsByTenantId.ContainsKey($Entry.azure_tenant_id)) { $ClientsByTenantId[$Entry.azure_tenant_id] = @{} }
                $ClientsByTenantId[$Entry.azure_tenant_id]["$($Entry.client_id)"] = $Entry.client_name
            }
        }
    } catch {
        $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
        $Notes.Add("Azure tenant IDs could not be read from HaloPSA ($Message), so only name matches were used.")
    }

    $ClientsByName = @{}
    try {
        $Page = 1
        do {
            $Result = Invoke-RestMethod -UserAgent $UserAgent -Uri "$($Configuration.ResourceURL)/Client?page_no=$Page&page_size=999&pageinate=true" -ContentType 'application/json' -Method GET -Headers $Headers
            foreach ($Client in $Result.clients) {
                $Name = "$($Client.name)".Trim()
                if (!$Name) { continue }
                if (!$ClientsByName.ContainsKey($Name)) { $ClientsByName[$Name] = [System.Collections.Generic.List[object]]::new() }
                $ClientsByName[$Name].Add($Client)
            }
            $Page++
        } while ($Page -le [Math]::Ceiling($Result.record_count / 999))
    } catch {
        $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
        $Notes.Add("HaloPSA clients could not be listed ($Message), so only tenant ID matches were used.")
    }

    if ($ClientsByTenantId.Count -eq 0 -and $ClientsByName.Count -eq 0) {
        return "AutoMap found nothing to match against. $($Notes -join ' ')".Trim()
    }

    $Tenants = Get-Tenants -IncludeErrors
    $MappedTenantIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@((Get-ExtensionMapping -Extension 'Halo').RowKey), [System.StringComparer]::OrdinalIgnoreCase)

    $Matched = 0
    $AlreadyMapped = 0
    $Ambiguous = [System.Collections.Generic.List[string]]::new()
    $Unmatched = 0

    foreach ($Tenant in $Tenants) {
        if ($MappedTenantIds.Contains("$($Tenant.customerId)")) {
            $AlreadyMapped++
            continue
        }

        $ClientId = $null
        $ClientName = $null
        $MatchType = $null
        $IdMatches = $ClientsByTenantId["$($Tenant.customerId)"]
        $NameMatches = $ClientsByName["$($Tenant.displayName)".Trim()]

        if ($IdMatches.Count -gt 1) {
            $Ambiguous.Add("$($Tenant.displayName) (tenant ID on $($IdMatches.Values -join ', '))")
            continue
        } elseif ($IdMatches.Count -eq 1) {
            $ClientId = @($IdMatches.Keys)[0]
            $ClientName = $IdMatches[$ClientId]
            $MatchType = 'Azure tenant ID'
        } elseif ($NameMatches.Count -gt 1) {
            $Ambiguous.Add("$($Tenant.displayName) (name shared by $($NameMatches.Count) clients)")
            continue
        } elseif ($NameMatches.Count -eq 1) {
            $ClientId = "$($NameMatches[0].id)"
            $ClientName = $NameMatches[0].name
            $MatchType = 'client name'
        } else {
            $Unmatched++
            continue
        }

        $AddObject = @{
            PartitionKey    = 'HaloMapping'
            RowKey          = "$($Tenant.customerId)"
            IntegrationId   = "$ClientId"
            IntegrationName = "$ClientName"
        }
        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        Write-LogMessage -API 'HaloAutoMap' -tenant $Tenant.defaultDomainName -message "Mapped $($Tenant.displayName) to HaloPSA client $ClientName by $MatchType match" -Sev 'Info'
        $Matched++
    }

    if ($Ambiguous.Count -gt 0) { $Notes.Add("Skipped as ambiguous: $($Ambiguous -join '; ').") }
    if ($Matched -gt 0) {
        Write-LogMessage -API 'HaloAutoMap' -message "AutoMap complete: $Matched tenant(s) mapped, $AlreadyMapped already mapped, $($Ambiguous.Count) skipped as ambiguous, $Unmatched with no matching HaloPSA client" -Sev 'Info'
    }
    return "AutoMap complete: $Matched new tenant mapping(s) added, $($Matched + $AlreadyMapped) tenant(s) mapped in total, $Unmatched unmatched. $($Notes -join ' ')".Trim()
}
