Function Invoke-ExecSyncroTestTicket {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Extension.ReadWrite
    .SYNOPSIS
        Create a Syncro test ticket so admins can check the integration works without waiting
        for a real alert to fire. Covers auth, tenant mapping, problem type and default priority.

        Calls New-SyncroPSATicket directly rather than going through Send-CIPPAlert, so the
        [CIPP] title prefix the alert pipeline adds is not exercised here.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $StatusCode = [HttpStatusCode]::OK
    try {
        $ConfigTable = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @ConfigTable).config | ConvertFrom-Json).Syncro

        if (-not $Configuration -or -not $Configuration.Enabled) {
            $Results = [pscustomobject]@{ Results = 'Syncro integration is not enabled. Save the integration with Enable Integration ticked, then try again.' }
        } else {
            # The test ticket lands on the first mapped tenant's Syncro customer. Unlike HaloPSA
            # there is no safe default customer to fall back to, so with no mapping the test
            # stops here and says so rather than opening a ticket on an arbitrary customer.
            $MappingTable = Get-CIPPTable -TableName CippMapping
            $Mappings = Get-CIPPAzDataTableEntity @MappingTable -Filter "PartitionKey eq 'SyncroMapping'"
            $Mapping = $Mappings | Where-Object { $_.IntegrationId -and (($_.IntegrationId -as [int]) -gt 0) } | Select-Object -First 1
            if (-not $Mapping) {
                $StatusCode = [HttpStatusCode]::BadRequest
                $Results = [pscustomobject]@{ Results = 'No tenant is mapped to a Syncro customer yet. Map at least one tenant on the Tenant Mapping tab, then try again.' }
            } else {
                $CustomerId = [int]$Mapping.IntegrationId
                $CustomerName = $Mapping.IntegrationName

                $Timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ssZ')
                $Title = 'Test ticket from CIPP integration'
                $Description = @"
<p>This is a <strong>test ticket</strong> created by CIPP at $Timestamp to verify end-to-end Syncro delivery.</p>
<p>Target customer: <strong>$CustomerName</strong> (id <code>$CustomerId</code>).</p>
<p>It is raised the same way CIPP raises alert tickets, so the configured Problem Type, Status and Default Priority should all apply.</p>
<p>It is safe to close this ticket.</p>
"@

                $Result = New-SyncroPSATicket -Title $Title -Description $Description -Client $CustomerId
                if ("$Result" -match '^(Failed|Error)') { $StatusCode = [HttpStatusCode]::InternalServerError }
                $Results = [pscustomobject]@{ Results = "$Result against customer '$CustomerName' (id $CustomerId). It is safe to close this ticket." }
            }
        }
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Results = [pscustomobject]@{ Results = "Failed to create Syncro test ticket: $($_.Exception.Message). Line $($_.InvocationInfo.ScriptLineNumber)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
