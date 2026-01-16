function Invoke-ExecAppInsightsQuery {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.Read
    #>
    [CmdletBinding()]
    param (
        $Request,
        $TriggerMetadata
    )

    $Query = $Request.Body.query ?? $Request.Query.query
    if (-not $Query) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{
                Results = 'No query provided in request body.'
            }
        }
    }

    try {
        $LogData = Get-ApplicationInsightsQuery -Query $Query

        $Body = ConvertTo-Json -Depth 10 -Compress -InputObject @{
            Results  = @($LogData)
            Metadata = @{
                Query = $Query
            }
        }
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        }

    } catch {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{
                Results  = "$($_.Exception.Message)"
                Metadata = @{
                    Query     = $Query
                    Exception = Get-CippException -Exception $_
                }
            }
        }
    }
}
