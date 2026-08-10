function Invoke-CippMcpApiRequest {
    <#
    .SYNOPSIS
        Executes one catalog tool by re-dispatching it through the CIPP API router.
    .DESCRIPTION
        Invokes the corresponding /api endpoint via New-CippCoreRequest using the caller's own
        principal headers. This guarantees Test-CIPPAccess (RBAC + tenant scoping + logging) runs
        for every tool call exactly as for a normal API request. The synthetic request is tagged
        with 'X-CIPP-Origin: mcp' so model-initiated calls are distinguishable in logs.
        Returns an MCP tool result object ({ content, isError }). Not an HTTP entrypoint.

        Successful responses are normalised to one shape: a { Results, Metadata } envelope is
        unwrapped to its payload so every tool answers with its data at the top level, and any
        non-empty Metadata (the paging cursor) is returned as a second content block. Bare
        arrays and single objects pass through unchanged, as do errors.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Request,
        $TriggerMetadata,
        [string]$ToolName,
        $Arguments,
        [string]$Method = 'GET',
        # Wire-name -> real-name map from the catalog entry (_paramAlias), for parameters that
        # had to be renamed to satisfy the MCP property-name rules.
        [hashtable]$ParamAlias
    )

    $ArgHash = ConvertTo-CippMcpHashtable -InputObject $Arguments

    # Restore any parameter renamed for the wire. OData options ('$filter', '$top', ...) are
    # advertised as odata_filter / odata_top because MCP property names cannot contain '$';
    # the endpoint still reads the original name, so translate back before dispatching.
    if ($ParamAlias -and $ParamAlias.Count -gt 0) {
        foreach ($Alias in $ParamAlias.GetEnumerator()) {
            if ($ArgHash.ContainsKey($Alias.Key)) {
                $ArgHash[$Alias.Value] = $ArgHash[$Alias.Key]
                $ArgHash.Remove($Alias.Key)
            }
        }
    }

    # Clone caller headers (preserves the EasyAuth principal) and tag the origin for auditing.
    $Headers = ConvertTo-CippMcpHashtable -InputObject $Request.Headers
    $Headers['X-CIPP-Origin'] = 'mcp'

    $Query = @{}
    $Body = @{}
    if ($Method -eq 'POST') { $Body = $ArgHash } else { $Query = $ArgHash }

    $InnerRequest = [pscustomobject]@{
        Params  = @{ CIPPEndpoint = $ToolName }
        Method  = $Method
        Headers = $Headers
        Query   = $Query
        Body    = $Body
    }

    try {
        $Response = New-CippCoreRequest -Request $InnerRequest -TriggerMetadata $TriggerMetadata
    } catch {
        return [ordered]@{
            content = @(@{ type = 'text'; text = "Tool execution failed: $($_.Exception.Message)" })
            isError = $true
        }
    }

    $IsError = $null -ne $Response.StatusCode -and [int]$Response.StatusCode -ge 400
    $ResultBody = $Response.Body
    $Metadata = $null

    # CIPP answers in three shapes: a bare array (most list endpoints), a { Results, Metadata }
    # envelope, or a single object. Nothing in the tool contract says which, so a caller would
    # have to read the PowerShell to know whether the data is at the top level or inside
    # .Results. The envelope is unwrapped here, at the MCP boundary only - the HTTP responses
    # are untouched, because CippApiResults on the frontend renders the envelope directly and
    # every existing caller depends on that shape.
    #
    # Errors keep their envelope: there the message *is* the payload.
    if (-not $IsError -and $null -ne $ResultBody -and $ResultBody -isnot [string]) {
        $Keys = if ($ResultBody -is [System.Collections.IDictionary]) {
            @($ResultBody.Keys | ForEach-Object { [string]$_ })
        } elseif ($ResultBody -is [System.Management.Automation.PSCustomObject]) {
            @($ResultBody.PSObject.Properties.Name)
        } else {
            @()
        }

        # Only a pure envelope is unwrapped. An object carrying other keys alongside Results
        # would lose them, so it is passed through exactly as the endpoint returned it.
        $Extra = @($Keys | Where-Object { $_ -notin @('Results', 'Result', 'Metadata') })
        if ($Keys.Count -gt 0 -and $Extra.Count -eq 0) {
            $PayloadKey = @('Results', 'Result') | Where-Object { $Keys -contains $_ } | Select-Object -First 1
            if ($PayloadKey) {
                if ($ResultBody -is [System.Collections.IDictionary]) {
                    $Metadata = $ResultBody['Metadata']
                    $ResultBody = $ResultBody[$PayloadKey]
                } else {
                    $Metadata = $ResultBody.Metadata
                    $ResultBody = $ResultBody.$PayloadKey
                }
            }
        }
    }

    # Metadata carries the paging cursor (nextLink) on the endpoints that page, so dropping it
    # would silently hide that there is more data. It rides along as its own content block
    # rather than being merged back into the payload, which would reintroduce the envelope.
    $HasMetadata = if ($null -eq $Metadata) {
        $false
    } elseif ($Metadata -is [System.Collections.IDictionary]) {
        $Metadata.Count -gt 0
    } elseif ($Metadata -is [System.Management.Automation.PSCustomObject]) {
        @($Metadata.PSObject.Properties).Count -gt 0
    } else {
        -not [string]::IsNullOrWhiteSpace([string]$Metadata)
    }

    # -InputObject, not the pipeline: piping unrolls the collection, so a one-row result
    # serialises as a bare object and an empty one as an empty string. The same tool then
    # changes JSON shape with the row count - ListDomains returned an array for a tenant
    # with five domains and an object for a tenant with one - which is unusable for a
    # caller that has to parse it.
    $Text = if ($ResultBody -is [string]) { $ResultBody } else { ConvertTo-Json -InputObject $ResultBody -Depth 20 -Compress }

    $Content = [System.Collections.Generic.List[object]]::new()
    $Content.Add(@{ type = 'text'; text = "$Text" })
    if ($HasMetadata) {
        $MetaText = if ($Metadata -is [string]) { $Metadata } else { $Metadata | ConvertTo-Json -Depth 20 -Compress }
        $Content.Add(@{ type = 'text'; text = "Response metadata (paging cursor and query context): $MetaText" })
    }

    return [ordered]@{
        content = @($Content)
        isError = $IsError
    }
}
