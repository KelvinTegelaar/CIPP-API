function Get-CIPPBaselineExchangeConnectorTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for ExchangeConnectorTemplate: is this instance's connector deployed.
    .DESCRIPTION
        One instance grades ONE template. Grades PRESENCE BY NAME (Identity) only, matching
        the classic - connector settings drift is repaired by the executor's Set- branch on
        every remediation run (checkBeforeRun:false), which reapplies the full template.

        The connector's DIRECTION lives as a column on the template ENTITY, not inside its
        JSON - the classic read $Template.direction off the row - and it decides both which
        cache is consulted (ExoInboundConnector vs ExoOutboundConnector) and which cmdlet
        family the executor calls.

        Template resolution stays per-family: PartitionKey 'ExConnectorTemplate' - one of
        the three partitions that do NOT match their standard name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Reference = $Item.Variables.exConnectorTemplate
    if ($Reference -is [System.Management.Automation.PSCustomObject] -and $Reference.PSObject.Properties.Name -contains 'value') { $Reference = $Reference.value }
    if ([string]::IsNullOrWhiteSpace("$Reference")) { return @{ Current = $null } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value "$Reference"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ExConnectorTemplate' and RowKey eq '$SafeReference'" | Select-Object -First 1
    if (-not $Entity -or [string]::IsNullOrWhiteSpace($Entity.JSON)) { return @{ Current = $null } }
    $Body = $(try { $Entity.JSON | ConvertFrom-Json -Depth 20 -ErrorAction Stop } catch { $null })
    $Direction = "$($Entity.direction)".ToLower()
    $ConnectorName = "$($Body.name)"
    if (-not $Body -or [string]::IsNullOrWhiteSpace($ConnectorName) -or $Direction -notin @('inbound', 'outbound')) { return @{ Current = $null } }

    $CacheType = if ($Direction -eq 'inbound') { 'ExoInboundConnector' } else { 'ExoOutboundConnector' }
    $Connectors = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type $CacheType)
    if ($Connectors.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type $CacheType)) {
        return @{ Current = $null }
    }

    $Existing = $Connectors | Where-Object { "$($_.Identity)" -eq $ConnectorName } | Select-Object -First 1

    $Current = [PSCustomObject]@{ deployed = [bool]$Existing }
    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyName 'connectorBody' -NotePropertyValue $Body
    $Current | Add-Member -NotePropertyName 'direction' -NotePropertyValue $Direction
    $Current | Add-Member -NotePropertyName 'existingIdentity' -NotePropertyValue "$($Existing.Identity)"

    @{
        Expected = [PSCustomObject]@{ deployed = $true }
        Current  = $Current
    }
}
