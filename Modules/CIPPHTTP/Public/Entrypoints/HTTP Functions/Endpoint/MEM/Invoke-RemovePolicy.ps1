function Invoke-RemovePolicy {
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


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.body.tenantFilter
    $PolicyId = $Request.Query.ID ?? $Request.body.ID
    $UrlName = $Request.Query.URLName ?? $Request.body.URLName
    # App protection policy lists expose the singular @odata.type as the URLName, but a Graph
    # DELETE needs the plural collection segment under deviceAppManagement. Normalize here.
    $GraphPath = switch ($UrlName) {
        'androidManagedAppProtection' { 'deviceAppManagement/androidManagedAppProtections' }
        'iosManagedAppProtection' { 'deviceAppManagement/iosManagedAppProtections' }
        'windowsManagedAppProtection' { 'deviceAppManagement/windowsManagedAppProtections' }
        'mdmWindowsInformationProtectionPolicy' { 'deviceAppManagement/mdmWindowsInformationProtectionPolicies' }
        'windowsInformationProtectionPolicy' { 'deviceAppManagement/windowsInformationProtectionPolicies' }
        'targetedManagedAppConfiguration' { 'deviceAppManagement/targetedManagedAppConfigurations' }
        'managedAppPolicies' { 'deviceAppManagement/managedAppPolicies' }
        'mobileAppConfigurations' { 'deviceAppManagement/mobileAppConfigurations' }
        default { "deviceManagement/$UrlName" }
    }
    if (!$PolicyId) { exit }

    try {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/$($GraphPath)('$($PolicyId)')" -type DELETE -tenant $TenantFilter

        $Results = "Successfully deleted the $UrlName policy with ID: $($PolicyId)"
        Write-LogMessage -headers $Headers -API $APINAME -message $Results -Sev Info -tenant $TenantFilter
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not delete policy: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APINAME -message $Results -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    $Body = [pscustomobject]@{'Results' = "$Results" }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })


}
