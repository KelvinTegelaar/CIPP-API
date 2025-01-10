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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Tenants = ($Request.Body.tenantFilter.value)
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }
    $displayname = $Request.Body.displayName
    $description = $Request.Body.Description
    $AssignTo = if ($Request.Body.AssignTo -ne 'on') { $Request.Body.AssignTo }
    $RawJSON = $Request.Body.RAWJson

    $results = foreach ($Tenant in $tenants) {
        if ($Request.Body.replacemap.$tenant) {
        ([pscustomobject]$Request.Body.replacemap.$tenant).psobject.properties | ForEach-Object { $RawJson = $RawJson -replace $_.name, $_.value }
        }
        try {
            Write-Host 'Calling Adding policy'
            Set-CIPPIntunePolicy -TemplateType $Request.body.TemplateType -Description $description -DisplayName $displayname -RawJSON $RawJSON -AssignTo $AssignTo -tenantFilter $Tenant
            "Added policy $($Displayname) to $($Tenant)"
            Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added policy $($Displayname)" -Sev 'Info'
        } catch {
            "Failed to add policy for $($Tenant): $($_.Exception.Message)"
            Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Failed adding policy $($Displayname). Error: $($_.Exception.Message)" -Sev 'Error'
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
