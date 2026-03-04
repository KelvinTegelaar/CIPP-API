function Invoke-RemoveIntuneReusableSetting {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    $ID = $Request.Body.ID ?? $Request.Query.ID
    $DisplayName = $Request.Body.DisplayName ?? $Request.Query.DisplayName

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter is required' }
            })
    }

    if (-not $ID) {
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::BadRequest
                Body       = @{ Results = 'ID is required' }
            })
    }

    try {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings/$ID"
        $null = New-GraphPOSTRequest -uri $uri -type DELETE -tenantid $TenantFilter

        $name = if ($DisplayName) { $DisplayName } else { $ID }
        $Result = "Deleted Intune reusable setting '$name' ($ID)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [System.Net.HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete Intune reusable setting $($ID): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [System.Net.HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
