function Invoke-ListBaselineStandards {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.Read
    .DESCRIPTION
        Lists the Baseline definition catalog: the standards available to add to a baseline,
        including their configurable variables and metadata.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $Results = @(Get-CIPPBaselineDefinition)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to list baseline standards: $($_.Exception.Message)" -Sev 'Error'
        $Results = @{ Results = "Failed to list baseline standards: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
