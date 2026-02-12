function Invoke-SetAuthMethod {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    Param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $State = if ($Request.Body.state -eq 'enabled') { $true } else { $false }
    $TenantFilter = $Request.Body.tenantFilter
    $AuthenticationMethodId = $Request.Body.Id
    $GroupIdsRaw = $Request.Body.GroupIds

    function Get-StandardizedList {
        param($InputObject)

        if ($null -eq $InputObject) { return @() }

        if ($InputObject -is [string]) {
            return @(
                $InputObject -split ',' |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
        }

        if ($InputObject -is [array] -or $InputObject -is [System.Collections.IEnumerable]) {
            return @(
                $InputObject |
                    ForEach-Object { "$_".Trim() } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
        }

        return @("$InputObject".Trim()) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $GroupIds = Get-StandardizedList -InputObject $GroupIdsRaw


    try {
        $Params = @{
            Tenant                 = $TenantFilter
            APIName                = $APIName
            AuthenticationMethodId = $AuthenticationMethodId
            Enabled                = $State
            Headers                = $Headers
        }
        if (@($GroupIds).Count -gt 0) {
            $Params.GroupIds = @($GroupIds)
        }
        $Result = Set-CIPPAuthenticationPolicy @Params
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = [pscustomobject]@{'Results' = $Result }
        })
}
