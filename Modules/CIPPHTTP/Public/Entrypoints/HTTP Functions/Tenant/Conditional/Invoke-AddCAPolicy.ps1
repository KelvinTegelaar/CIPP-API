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

    $Failed = 0
    $results = foreach ($Tenant in $tenants) {
        try {
            $NewCAPolicy = @{
                replacePattern = $Request.Body.replacename
                Overwrite      = $Request.Body.overwrite
                TenantFilter   = $Tenant
                state          = $Request.Body.NewState
                DisableSD      = $Request.Body.DisableSD
                CreateGroups   = $Request.Body.CreateGroups
                RawJSON        = $Request.Body.RawJSON
                APIName        = $APIName
                Headers        = $Headers
            }
            $CAPolicy = New-CIPPCAPolicy @NewCAPolicy

            "$CAPolicy"
        } catch {
            $Failed++
            "$($_.Exception.Message)"
            continue
        }

    }

    $body = [pscustomobject]@{'Results' = @($results) }

    return ([HttpResponseContext]@{
            StatusCode = Get-CippBulkStatusCode -Total @($Tenants).Count -Failed $Failed
            Body       = $body
        })

}
