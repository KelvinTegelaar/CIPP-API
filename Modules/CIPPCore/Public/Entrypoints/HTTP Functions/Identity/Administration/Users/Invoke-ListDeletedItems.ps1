using namespace System.Net

function Invoke-ListDeletedItems {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $Types = 'Application', 'User', 'Group'
    $GraphRequest = foreach ($Type in $Types) {
        (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directory/deletedItems/microsoft.graph.$($Type)" -tenantid $TenantFilter) |
            Where-Object -Property '@odata.context' -NotLike '*graph.microsoft.com*' |
            Select-Object *, @{ Name = 'TargetType'; Expression = { $Type } }
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    }
}
