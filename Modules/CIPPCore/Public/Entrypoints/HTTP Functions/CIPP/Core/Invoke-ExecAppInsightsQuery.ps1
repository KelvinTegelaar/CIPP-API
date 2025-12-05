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
                Error = 'No query provided in request body.'
            }
        }
    }

    try {
        $LogData = Get-ApplicationInsightsQuery -Query $Query

        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results  = @($LogData)
                Metadata = @{
                    Query = $Query
                }
            }
        }

    } catch {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{
                Results  = "Failed to execute Application Insights query: $($_.Exception.Message)"
                Metadata = @{
                    Query     = $Query
                    Exception = Get-CippException -Exception $_
                }
            }
        }
    }
}
