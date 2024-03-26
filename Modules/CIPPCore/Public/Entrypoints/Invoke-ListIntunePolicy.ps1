using namespace System.Net

Function Invoke-ListIntunePolicy {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $id = $Request.Query.ID
    $urlname = $Request.Query.URLName
    try {
        if ($ID) {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)('$ID')" -tenantid $tenantfilter
        } else {

            $GraphURLS = @("https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$select=id,displayName,lastModifiedDateTime,roleScopeTagIds,microsoft.graph.unsupportedDeviceConfiguration/originalEntityTypeName&`$expand=assignments&top=1000",
                "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?`$expand=assignments&top=1000"
                "https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations?`$expand=assignments&`$filter=microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig%20eq%20true"
                'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
            )

            $GraphRequest = $GraphURLS | ForEach-Object {
                $URLName = (($_).split('?') | Select-Object -First 1) -replace 'https://graph.microsoft.com/beta/deviceManagement/', ''
                New-GraphGetRequest -uri $_ -tenantid $TenantFilter

            } | ForEach-Object {
                $policyTypeName = switch -Wildcard ($_.'assignments@odata.context') {
                    '*microsoft.graph.windowsIdentityProtectionConfiguration*' { 'Identity Protection' }
                    '*microsoft.graph.windows10EndpointProtectionConfiguration*' { 'Endpoint Protection' }
                    '*microsoft.graph.windows10CustomConfiguration*' { 'Custom' }
                    '*groupPolicyConfigurations*' { 'Administrative Templates' }
                    '*windowsDomainJoinConfiguration*' { 'Domain Join configuration' }
                    '*windowsUpdateForBusinessConfiguration*' { 'Update Configuration' }
                    '*windowsHealthMonitoringConfiguration*' { 'Health Monitoring' }
                    default { $_.'assignments@odata.context' }
                }
                if ($_.displayname -eq $null) { $_ | Add-Member -NotePropertyName displayName -NotePropertyValue $_.name }
                $_ | Add-Member -NotePropertyName PolicyTypeName -NotePropertyValue $policyTypeName 
                $_ | Add-Member -NotePropertyName URLName -NotePropertyValue $URLName
                $_
            } | Where-Object { $_.DisplayName -ne $null }

        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
