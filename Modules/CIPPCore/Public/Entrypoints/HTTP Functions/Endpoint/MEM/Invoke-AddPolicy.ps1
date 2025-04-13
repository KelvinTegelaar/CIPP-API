using namespace System.Net

Function Invoke-AddPolicy {
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
    $displayname = $Request.Body.displayName
    $description = $Request.Body.Description
    $AssignTo = if ($Request.Body.AssignTo -ne 'on') { $Request.Body.AssignTo }
    $ExcludeGroup = $Request.Body.excludeGroup
    $Request.body.customGroup ? ($AssignTo = $Request.body.customGroup) : $null
    $RawJSON = $Request.Body.RAWJson

    $results = foreach ($Tenant in $tenants) {
        if ($Request.Body.replacemap.$tenant) {
        ([pscustomobject]$Request.Body.replacemap.$tenant).psobject.properties | ForEach-Object { $RawJson = $RawJson -replace $_.name, $_.value }
        }
        try {
            Write-Host 'Calling Adding policy'
            Set-CIPPIntunePolicy -TemplateType $Request.body.TemplateType -Description $description -DisplayName $displayname -RawJSON $RawJSON -AssignTo $AssignTo -ExcludeGroup $ExcludeGroup -tenantFilter $Tenant -Headers $Request.Headers
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($Tenant) -message "Added policy $($Displayname)" -Sev 'Info'
        } catch {
            "$($_.Exception.Message)"
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($Tenant) -message "Failed adding policy $($Displayname). Error: $($_.Exception.Message)" -Sev 'Error'
            continue
        }

    }

    $body = [pscustomobject]@{'Results' = @($results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
