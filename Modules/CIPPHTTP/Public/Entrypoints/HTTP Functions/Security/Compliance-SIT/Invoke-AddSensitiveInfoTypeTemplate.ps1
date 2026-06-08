Function Invoke-AddSensitiveInfoTypeTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitiveInfoType.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # SIT templates are JSON-authored via the deploy drawer. Round-tripping from an existing tenant SIT is not
    # supported because the rule pack XML is not exposed reliably through IPPS REST.
    $AllowedFields = @(
        'Name', 'Description',
        'Pattern', 'Confidence',
        'PatternsProximity', 'Locale', 'Recommended', 'PublisherName',
        'FileDataBase64'
    )

    try {
        $GUID = (New-Guid).GUID

        $Source = if ($Request.Body.PowerShellCommand) {
            $Request.Body.PowerShellCommand | ConvertFrom-Json
        } else {
            [pscustomobject]$Request.Body
        }

        $Clean = [ordered]@{}
        foreach ($prop in $Source.PSObject.Properties) {
            if ($prop.Name -notin $AllowedFields) { continue }
            $val = $prop.Value
            if ($null -eq $val) { continue }
            if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { continue }
            $Clean[$prop.Name] = $val
        }

        if (-not $Clean.Contains('Pattern') -and -not $Clean.Contains('FileDataBase64')) {
            $Result = "Template requires either 'Pattern' (simple mode) or 'FileDataBase64' (advanced mode). The list-page action cannot fetch the rule pack XML from existing SITs — author the template JSON in the deploy drawer instead."
            Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Warning'
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = $Result }
                })
        }

        $Ordered = [ordered]@{
            name     = $Clean['Name'] ?? $Source.Name ?? $Source.name
            comments = $Source.Comment ?? $Source.comments
        }
        foreach ($k in $Clean.Keys) {
            if ($Ordered.Contains($k)) { continue }
            $Ordered[$k] = $Clean[$k]
        }

        $JSON = ([pscustomobject]$Ordered | ConvertTo-Json -Depth 10)
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'SensitiveInfoTypeTemplate'
        }
        $Result = "Successfully created Sensitive Information Type Template: $($Ordered['name']) with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Debug'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Sensitive Information Type Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
