using namespace System.Net

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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Tenants = ($Request.Body.tenantFilter.value)
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }
    $DisplayName = $Request.Body.displayName
    $Description = $Request.Body.Description
    $AssignTo = if ($Request.Body.AssignTo -ne 'on') { $Request.Body.AssignTo }
    $ExcludeGroup = $Request.Body.excludeGroup
    $Request.Body.customGroup ? ($AssignTo = $Request.Body.customGroup) : $null
    $RawJSON = $Request.Body.RAWJson

    $Results = foreach ($Tenant in $Tenants) {
        if ($Request.Body.replacemap.$tenant) {
            ([pscustomobject]$Request.Body.replacemap.$tenant).psobject.properties | ForEach-Object { $RawJson = $RawJson -replace $_.name, $_.value }
        }
        try {
            Set-CIPPIntunePolicy -TemplateType $Request.Body.TemplateType -Description $Description -DisplayName $DisplayName -RawJSON $RawJSON -AssignTo $AssignTo -ExcludeGroup $ExcludeGroup -tenantFilter $Tenant -Headers $Headers
        } catch {
            "$($_.Exception.Message)"
            continue
        }
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = @($Results) }
    }
}
