function Invoke-HaloAutoMap {
    <#
    .SYNOPSIS
        Auto-maps CIPP tenants to HaloPSA clients using Halo's own Azure tenant IDs
    .DESCRIPTION
        HaloPSA's Microsoft 365 integration stores the Azure tenant ID on each client it is
        connected to. Those IDs are exact matches for CIPP's tenant customerId, so mappings
        can be created without any name guessing. Existing mappings are never overwritten.
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

    # type=2 connections are Halo's customer-tenant (Microsoft 365) integrations; the
    # connection detail carries the client <-> Azure tenant ID mapping table.
    try {
        $ConnectionsResponse = Invoke-RestMethod -UserAgent $UserAgent -Uri "$($Configuration.ResourceURL)/AzureADConnection?type=2" -Method GET -ContentType 'application/json' -Headers $Headers
        $Connections = if ($ConnectionsResponse -is [array]) {
            $ConnectionsResponse
        } elseif ($ConnectionsResponse.id) {
            @($ConnectionsResponse)
        } else {
            @($ConnectionsResponse.PSObject.Properties | Where-Object { $_.Value -is [array] } | Select-Object -First 1).Value
        }

        $HaloTenantMappings = foreach ($Connection in $Connections) {
            $Detail = Invoke-RestMethod -UserAgent $UserAgent -Uri "$($Configuration.ResourceURL)/AzureADConnection/$($Connection.id)?type=2&includedetails=true&includetenants=true" -Method GET -ContentType 'application/json' -Headers $Headers
            $Detail.mappings_client | Where-Object { $_.azure_tenant_id -match $GuidRegex -and $_.client_id }
        }
    } catch {
        $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-LogMessage -API 'HaloAutoMap' -message "Could not get Azure tenant mappings from HaloPSA: $Message" -Sev 'Error'
        return "Could not get Azure tenant mappings from HaloPSA: $Message. Check that Halo's Azure AD/Microsoft 365 integration is configured and the API agent may read integration settings."
    }

    if (($HaloTenantMappings | Measure-Object).Count -eq 0) {
        return "No Azure tenant IDs were found on any HaloPSA client. Map tenants to clients in Halo's Azure AD/Microsoft 365 integration first, or map them manually here."
    }

    $MappingsByTenantId = $HaloTenantMappings | Group-Object -Property azure_tenant_id
    $Tenants = Get-Tenants -IncludeErrors
    $ExistingMappings = Get-ExtensionMapping -Extension 'Halo'

    $Matched = 0
    $AlreadyMapped = 0
    $Ambiguous = 0
    $Unmatched = 0

    foreach ($Tenant in $Tenants) {
        if ($Tenant.customerId -in $ExistingMappings.RowKey) {
            $AlreadyMapped++
            continue
        }
        $Group = $MappingsByTenantId | Where-Object { $_.Name -eq $Tenant.customerId }
        if (!$Group) {
            $Unmatched++
            continue
        }
        $ClientIds = @($Group.Group.client_id | Sort-Object -Unique)
        if ($ClientIds.Count -gt 1) {
            $Ambiguous++
            $ClientNames = ($Group.Group | Sort-Object -Property client_id -Unique | ForEach-Object { "$($_.client_name) ($($_.client_id))" }) -join ', '
            Write-LogMessage -API 'HaloAutoMap' -message "Skipped tenant $($Tenant.displayName): its Azure tenant ID is present on multiple HaloPSA clients: $ClientNames" -Sev 'Warning'
            continue
        }
        $Entry = $Group.Group | Select-Object -First 1
        $AddObject = @{
            PartitionKey    = 'HaloMapping'
            RowKey          = "$($Tenant.customerId)"
            IntegrationId   = "$($Entry.client_id)"
            IntegrationName = "$($Entry.client_name)"
        }
        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        Write-LogMessage -API 'HaloAutoMap' -message "Added mapping from Azure tenant ID match for $($Tenant.displayName) to $($Entry.client_name)" -Sev 'Info'
        $Matched++
    }

    Write-LogMessage -API 'HaloAutoMap' -message "AutoMap complete: $Matched tenant(s) mapped from HaloPSA Azure tenant IDs, $AlreadyMapped already mapped, $Ambiguous skipped as ambiguous, $Unmatched with no matching Halo client" -Sev 'Info'
    return "AutoMap complete: $Matched new tenant mapping(s) added, $($Matched + $AlreadyMapped) tenant(s) mapped in total."
}
