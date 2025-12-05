function Invoke-AddCAPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $Tenants = $Request.body.tenantFilter.value
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }

    $results = foreach ($Tenant in $tenants) {
        try {
            $CAPolicy = New-CIPPCAPolicy -replacePattern $Request.Body.replacename -Overwrite $request.Body.overwrite -TenantFilter $Tenant -state $Request.Body.NewState -DisableSD $Request.Body.DisableSD -RawJSON $Request.Body.RawJSON -APIName $APIName -Headers $Headers
            "$CAPolicy"
        } catch {
            "$($_.Exception.Message)"
            continue
        }

    }

    $body = [pscustomobject]@{'Results' = @($results) }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
