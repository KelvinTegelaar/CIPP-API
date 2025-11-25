function Invoke-AddPolicy {
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
    $Tenants = $Request.Body.tenantFilter.value ? $Request.Body.tenantFilter.value : $Request.Body.tenantFilter
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }

    $DisplayName = $Request.Body.displayName
    $description = $Request.Body.Description
    $AssignTo = if ($Request.Body.AssignTo -ne 'on') { $Request.Body.AssignTo }
    $ExcludeGroup = $Request.Body.excludeGroup
    $Request.Body.customGroup ? ($AssignTo = $Request.Body.customGroup) : $null
    $RawJSON = $Request.Body.RAWJson

    $results = foreach ($Tenant in $Tenants) {
        if ($Request.Body.replacemap.$Tenant) {
            ([pscustomobject]$Request.Body.replacemap.$Tenant).PSObject.Properties | ForEach-Object { $RawJSON = $RawJSON -replace $_.name, $_.value }
        }
        try {
            Write-Host 'Calling Adding policy'
            $params = @{
                TemplateType = $Request.Body.TemplateType
                Description  = $description
                DisplayName  = $DisplayName
                RawJSON      = $RawJSON
                AssignTo     = $AssignTo
                ExcludeGroup = $ExcludeGroup
                tenantFilter = $Tenant
                Headers      = $Headers
            }
            Set-CIPPIntunePolicy @params
            Write-LogMessage -headers $Headers -API $APIName -tenant $($Tenant) -message "Added policy $($DisplayName)" -Sev 'Info'
        } catch {
            "$($_.Exception.Message)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $($Tenant) -message "Failed adding policy $($DisplayName). Error: $($_.Exception.Message)" -Sev 'Error'
            continue
        }

    }

    $body = [pscustomobject]@{'Results' = @($results) }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
