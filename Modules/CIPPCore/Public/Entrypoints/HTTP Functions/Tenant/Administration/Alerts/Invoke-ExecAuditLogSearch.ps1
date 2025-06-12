function Invoke-ExecAuditLogSearch {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Query = $Request.Body
    if (!$Query.TenantFilter) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'TenantFilter is required'
            })
        return
    }
    if (!$Query.StartTime -or !$Query.EndTime) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'StartTime and EndTime are required'
            })
        return
    }

    $Command = Get-Command New-CippAuditLogSearch
    $AvailableParameters = $Command.Parameters.Keys
    $BadProps = foreach ($Prop in $Query.PSObject.Properties.Name) {
        if ($AvailableParameters -notcontains $Prop) {
            $Prop
        }
    }
    if ($BadProps) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = "Invalid parameters: $($BadProps -join ', ')"
            })
        return
    }

    try {
        $Query = $Query | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
        $Results = New-CippAuditLogSearch @Query
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Results
            })
    } catch {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $_.Exception.Message
            })
    }
}
