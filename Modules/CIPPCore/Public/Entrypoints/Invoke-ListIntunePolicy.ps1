
Function Invoke-ListIntunePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
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
            $Groups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $tenantfilter | Select-Object -Property id, displayName

            $BulkRequests = [PSCustomObject]@(
                @{
                    id     = 'DeviceConfigurations'
                    method = 'GET'
                    url    = "/deviceManagement/deviceConfigurations?`$select=id,displayName,lastModifiedDateTime,roleScopeTagIds,microsoft.graph.unsupportedDeviceConfiguration/originalEntityTypeName,description&`$expand=assignments&top=1000"
                }
                @{
                    id     = 'WindowsDriverUpdateProfiles'
                    method = 'GET'
                    url    = "/deviceManagement/windowsDriverUpdateProfiles?`$expand=assignments&top=200"
                }
                @{
                    id     = 'GroupPolicyConfigurations'
                    method = 'GET'
                    url    = "/deviceManagement/groupPolicyConfigurations?`$expand=assignments&top=1000"
                }
                @{
                    id     = 'MobileAppConfigurations'
                    method = 'GET'
                    url    = "/deviceAppManagement/mobileAppConfigurations?`$expand=assignments&`$filter=microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig%20eq%20true"
                }
                @{
                    id     = 'ConfigurationPolicies'
                    method = 'GET'
                    url    = "/deviceManagement/configurationPolicies?`$expand=assignments&top=1000"
                }
            )

            $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

            $GraphRequest = $BulkResults.body.value | ForEach-Object {
                $policyTypeName = switch -Wildcard ($_.'assignments@odata.context') {
                    '*microsoft.graph.windowsIdentityProtectionConfiguration*' { 'Identity Protection' }
                    '*microsoft.graph.windows10EndpointProtectionConfiguration*' { 'Endpoint Protection' }
                    '*microsoft.graph.windows10CustomConfiguration*' { 'Custom' }
                    '*microsoft.graph.windows10DeviceFirmwareConfigurationInterface*' { 'Firmware Configuration' }
                    '*groupPolicyConfigurations*' { 'Administrative Templates' }
                    '*windowsDomainJoinConfiguration*' { 'Domain Join configuration' }
                    '*windowsUpdateForBusinessConfiguration*' { 'Update Configuration' }
                    '*windowsHealthMonitoringConfiguration*' { 'Health Monitoring' }
                    '*microsoft.graph.macOSGeneralDeviceConfiguration*' { 'MacOS Configuration' }
                    '*microsoft.graph.macOSEndpointProtectionConfiguration*' { 'MacOS Endpoint Protection' }
                    '*microsoft.graph.androidWorkProfileGeneralDeviceConfiguration*' { 'Android Configuration' }
                    default { $_.'assignments@odata.context' }
                }
                $Assignments = $_.assignments.target | Select-Object -Property '@odata.type', groupId
                $PolicyAssignment = [System.Collections.Generic.List[string]]::new()
                $PolicyExclude = [System.Collections.Generic.List[string]]::new()
                ForEach ($target in $Assignments) {
                    switch ($target.'@odata.type') {
                        '#microsoft.graph.allDevicesAssignmentTarget' { $PolicyAssignment.Add('All Devices') }
                        '#microsoft.graph.exclusionallDevicesAssignmentTarget' { $PolicyExclude.Add('All Devices') }
                        '#microsoft.graph.allUsersAssignmentTarget' { $PolicyAssignment.Add('All Users') }
                        '#microsoft.graph.exclusionallUsersAssignmentTarget' { $PolicyExclude.Add('All Users') }
                        '#microsoft.graph.groupAssignmentTarget' { $PolicyAssignment.Add($Groups.Where({ $_.id -eq $target.groupId }).displayName) }
                        '#microsoft.graph.exclusionGroupAssignmentTarget' { $PolicyExclude.Add($Groups.Where({ $_.id -eq $target.groupId }).displayName) }
                        default {
                            $PolicyAssignment.Add($null)
                            $PolicyExclude.Add($null)
                        }
                    }
                }
                if ($_.displayname -eq $null) { $_ | Add-Member -NotePropertyName displayName -NotePropertyValue $_.name }
                $_ | Add-Member -NotePropertyName PolicyTypeName -NotePropertyValue $policyTypeName
                $_ | Add-Member -NotePropertyName URLName -NotePropertyValue $URLName
                $_ | Add-Member -NotePropertyName PolicyAssignment -NotePropertyValue ($PolicyAssignment -join ', ')
                $_ | Add-Member -NotePropertyName PolicyExclude -NotePropertyValue ($PolicyExclude -join ', ')
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
