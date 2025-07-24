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

    # Convert StartTime and EndTime to DateTime from unixtime
    if ($Query.StartTime -match '^\d+$') {
        $Query.StartTime = [DateTime]::UnixEpoch.AddSeconds([long]$Query.StartTime)
    } else {
        $Query.StartTime = [DateTime]$Query.StartTime
    }

    if ($Query.EndTime -match '^\d+$') {
        $Query.EndTime = [DateTime]::UnixEpoch.AddSeconds([long]$Query.EndTime)
    } else {
        $Query.EndTime = [DateTime]$Query.EndTime
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
        Write-Information "Executing audit log search with parameters: $($Query | ConvertTo-Json -Depth 10)"

        $Query = $Query | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
        $NewSearch = New-CippAuditLogSearch @Query

        if ($NewSearch) {
            $Results = @{
                resultText = "Created audit log search: $($NewSearch.displayName)"
                state      = 'success'
                details    = $NewSearch
            }
        } else {
            $Results = @{
                resultText = 'Failed to initiate search'
                state      = 'error'
            }
        }
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
