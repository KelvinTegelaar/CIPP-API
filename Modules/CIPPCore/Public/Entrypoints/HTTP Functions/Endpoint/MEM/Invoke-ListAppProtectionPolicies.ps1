function Invoke-ListAppProtectionPolicies {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Query.tenantFilter

    try {
        # Use bulk requests to get both managed app policies and mobile app configurations
        $BulkRequests = @(
            @{
                id     = 'ManagedAppPolicies'
                method = 'GET'
                url    = '/deviceAppManagement/managedAppPolicies?$orderby=displayName'
            }
            @{
                id     = 'MobileAppConfigurations'
                method = 'GET'
                url    = '/deviceAppManagement/mobileAppConfigurations?$orderby=displayName'
            }
        )

        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

        $GraphRequest = [System.Collections.Generic.List[object]]::new()

        # Process Managed App Policies
        $ManagedAppPolicies = ($BulkResults | Where-Object { $_.id -eq 'ManagedAppPolicies' }).body.value
        if ($ManagedAppPolicies) {
            foreach ($Policy in $ManagedAppPolicies) {
                $policyType = switch -Wildcard ($Policy.'@odata.type') {
                    '*androidManagedAppProtection*' { 'Android App Protection' }
                    '*iosManagedAppProtection*' { 'iOS App Protection' }
                    '*windowsManagedAppProtection*' { 'Windows App Protection' }
                    '*mdmWindowsInformationProtectionPolicy*' { 'Windows Information Protection (MDM)' }
                    '*windowsInformationProtectionPolicy*' { 'Windows Information Protection' }
                    '*targetedManagedAppConfiguration*' { 'App Configuration (MAM)' }
                    '*defaultManagedAppProtection*' { 'Default App Protection' }
                    default { 'App Protection Policy' }
                }
                $Policy | Add-Member -NotePropertyName 'PolicyTypeName' -NotePropertyValue $policyType -Force
                $Policy | Add-Member -NotePropertyName 'URLName' -NotePropertyValue 'managedAppPolicies' -Force
                $Policy | Add-Member -NotePropertyName 'PolicySource' -NotePropertyValue 'AppProtection' -Force
                $GraphRequest.Add($Policy)
            }
        }

        # Process Mobile App Configurations
        $MobileAppConfigs = ($BulkResults | Where-Object { $_.id -eq 'MobileAppConfigurations' }).body.value
        if ($MobileAppConfigs) {
            foreach ($Config in $MobileAppConfigs) {
                $policyType = switch -Wildcard ($Config.'@odata.type') {
                    '*androidManagedStoreAppConfiguration*' { 'Android Enterprise App Configuration' }
                    '*androidForWorkAppConfigurationSchema*' { 'Android for Work Configuration' }
                    '*iosMobileAppConfiguration*' { 'iOS App Configuration' }
                    default { 'App Configuration Policy' }
                }
                $Config | Add-Member -NotePropertyName 'PolicyTypeName' -NotePropertyValue $policyType -Force
                $Config | Add-Member -NotePropertyName 'URLName' -NotePropertyValue 'mobileAppConfigurations' -Force
                $Config | Add-Member -NotePropertyName 'PolicySource' -NotePropertyValue 'AppConfiguration' -Force

                # Ensure isAssigned property exists for consistency
                if (-not $Config.PSObject.Properties['isAssigned']) {
                    $Config | Add-Member -NotePropertyName 'isAssigned' -NotePropertyValue $false -Force
                }
                $GraphRequest.Add($Config)
            }
        }

        # Sort combined results by displayName
        $GraphRequest = $GraphRequest | Sort-Object -Property displayName

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
