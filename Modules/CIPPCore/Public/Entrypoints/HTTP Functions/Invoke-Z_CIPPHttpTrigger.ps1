function Invoke-Z_CIPPHttpTrigger {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    Param(
        $Request,
        $TriggerMetadata
    )

    $FunctionName = 'Invoke-{0}' -f $Request.Params.CIPPEndpoint

    Write-Host "Function: $($Request.Params.CIPPEndpoint)"

    $HttpTrigger = @{
        Request         = $Request
        TriggerMetadata = $TriggerMetadata
    }

    if (Get-Command -Name $FunctionName -ErrorAction SilentlyContinue) {
        & $FunctionName @HttpTrigger
    } else {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body       = 'Endpoint not found'
            })
    }
}