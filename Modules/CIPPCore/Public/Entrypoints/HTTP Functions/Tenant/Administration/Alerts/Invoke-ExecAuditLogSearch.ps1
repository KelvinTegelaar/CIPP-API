function Invoke-ExecAuditLogSearch {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Query = $Request.Body
    if (!$Query.TenantFilter) {
        return @{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = 'TenantFilter is required'
        }
    }
    if (!$Query.StartTime -or !$Query.EndTime) {
        return @{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = 'StartTime and EndTime are required'
        }
    }

    $Command = Get-Command New-CippAuditLogSearch
    $AvailableParameters = $Command.Parameters.Keys
    $BadProps = foreach ($Prop in $Query.PSObject.Properties.Name) {
        if ($AvailableParameters -notcontains $Prop) {
            $Prop
        }
    }
    if ($BadProps) {
        return @{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = "Invalid parameters: $($BadProps -join ', ')"
        }
    }

    try {
        $Query = $Query | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
        $Results = New-CippAuditLogSearch @Query
        return @{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        }
    } catch {
        return @{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = $_.Exception.Message
        }
    }
}
