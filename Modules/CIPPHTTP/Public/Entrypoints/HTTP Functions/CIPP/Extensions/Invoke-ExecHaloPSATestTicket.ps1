Function Invoke-ExecHaloPSATestTicket {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Extension.ReadWrite
    .SYNOPSIS
        Create a HaloPSA test ticket so admins can check the integration works without waiting
        for a real alert to fire. Covers auth, tenant mapping, ticket type and default priority.

        Calls New-HaloPSATicket directly rather than going through Send-CIPPAlert, so the parts
        that live in the alert pipeline - the [CIPP] title prefix and per-user ticket linking -
        are not exercised here.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $ConfigTable = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @ConfigTable).config | ConvertFrom-Json).HaloPSA

        if (-not $Configuration -or -not $Configuration.Enabled) {
            $Results = [pscustomobject]@{ Results = 'HaloPSA integration is not enabled. Save the integration with Enable Integration ticked, then try again.' }
        } else {
            # Pick the first mapped tenant's Halo client id so the test ticket lands on a real
            # client. Filters to mappings whose IntegrationId is numeric (Halo client ids are
            # always integers); legacy or cross-integration rows with GUID-shaped IntegrationIds
            # are skipped instead of crashing the cast. Falls back to 1 (the same default the
            # alert pipeline uses) if no usable mapping exists.
            $MappingTable = Get-CIPPTable -TableName CippMapping
            $Mappings = Get-CIPPAzDataTableEntity @MappingTable -Filter "PartitionKey eq 'HaloMapping'"
            $Mapping = $Mappings | Where-Object { $_.IntegrationId -and (($_.IntegrationId -as [int]) -gt 0) } | Select-Object -First 1
            $ClientId = if ($Mapping) { [int]$Mapping.IntegrationId } else { 1 }
            $ClientName = if ($Mapping) { $Mapping.IntegrationName } else { 'Default Client (no numeric Tenant Mapping found)' }

            $Timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ssZ')
            $Title = 'Test ticket from CIPP integration'
            $Description = @"
<p>This is a <strong>test ticket</strong> created by CIPP at $Timestamp to verify end-to-end HaloPSA delivery.</p>
<p>Target client: <strong>$ClientName</strong> (id <code>$ClientId</code>).</p>
<p>It is raised the same way CIPP raises alert tickets, so the configured Ticket Type, Request Source and Default Priority should all apply.</p>
<p>It is safe to close this ticket.</p>
"@

            $Result = New-HaloPSATicket -Title $Title -Description $Description -Client $ClientId

            $Results = [pscustomobject]@{ Results = "$Result against client '$ClientName' (id $ClientId). It is safe to close this ticket." }
        }
    } catch {
        $Results = [pscustomobject]@{ Results = "Failed to create HaloPSA test ticket: $($_.Exception.Message). Line $($_.InvocationInfo.ScriptLineNumber)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })
}
