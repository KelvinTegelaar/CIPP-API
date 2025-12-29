
function Invoke-ListIntunePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $id = $Request.Query.ID
    $URLName = $Request.Query.URLName
    try {
        if ($ID) {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($URLName)('$ID')" -tenantid $TenantFilter
        } else {
            $BulkRequests = [PSCustomObject]@(
                @{
                    id     = 'Groups'
                    method = 'GET'
                    url    = '/groups?$top=999&$select=id,displayName'
                }
                @{
                    id     = 'DeviceConfigurations'
                    method = 'GET'
                    url    = "/deviceManagement/deviceConfigurations?`$select=id,displayName,lastModifiedDateTime,roleScopeTagIds,microsoft.graph.unsupportedDeviceConfiguration/originalEntityTypeName,description&`$expand=assignments&`$top=1000"
                }
                @{
                    id     = 'WindowsDriverUpdateProfiles'
                    method = 'GET'
                    url    = "/deviceManagement/windowsDriverUpdateProfiles?`$expand=assignments&`$top=200"
                }
                @{
                    id     = 'WindowsFeatureUpdateProfiles'
                    method = 'GET'
                    url    = "/deviceManagement/windowsFeatureUpdateProfiles?`$expand=assignments&`$top=200"
                }
                @{
                    id     = 'windowsQualityUpdatePolicies'
                    method = 'GET'
                    url    = "/deviceManagement/windowsQualityUpdatePolicies?`$expand=assignments&`$top=200"
                }
                @{
                    id     = 'windowsQualityUpdateProfiles'
                    method = 'GET'
                    url    = "/deviceManagement/windowsQualityUpdateProfiles?`$expand=assignments&`$top=200"
                }
                @{
                    id     = 'GroupPolicyConfigurations'
                    method = 'GET'
                    url    = "/deviceManagement/groupPolicyConfigurations?`$expand=assignments&`$top=1000"
                }
                @{
                    id     = 'MobileAppConfigurations'
                    method = 'GET'
                    url    = "/deviceAppManagement/mobileAppConfigurations?`$expand=assignments&`$filter=microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig%20eq%20true"
                }
                @{
                    id     = 'ConfigurationPolicies'
                    method = 'GET'
                    url    = "/deviceManagement/configurationPolicies?`$expand=assignments&`$top=1000"
                }
            )

            $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

            # Extract groups for resolving assignment names
            $Groups = ($BulkResults | Where-Object { $_.id -eq 'Groups' }).body.value

            $GraphRequest = $BulkResults | Where-Object { $_.id -ne 'Groups' } | ForEach-Object {
                $URLName = $_.Id
                $_.body.Value | ForEach-Object {
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
                        '*windowsFeatureUpdateProfiles*' { 'Feature Update' }
                        '*windowsQualityUpdatePolicies*' { 'Quality Update' }
                        '*windowsQualityUpdateProfiles*' { 'Quality Update' }
                        '*iosUpdateConfiguration*' { 'iOS Update Configuration' }
                        '*windowsDriverUpdateProfiles*' { 'Driver Update' }
                        '*configurationPolicies*' { 'Device Configuration' }
                        default { $_.'assignments@odata.context' }
                    }
                    $Assignments = $_.assignments.target | Select-Object -Property '@odata.type', groupId
                    $PolicyAssignment = [System.Collections.Generic.List[string]]::new()
                    $PolicyExclude = [System.Collections.Generic.List[string]]::new()
                    foreach ($target in $Assignments) {
                        switch ($target.'@odata.type') {
                            '#microsoft.graph.allDevicesAssignmentTarget' { $PolicyAssignment.Add('All Devices') }
                            '#microsoft.graph.exclusionallDevicesAssignmentTarget' { $PolicyExclude.Add('All Devices') }
                            '#microsoft.graph.allUsersAssignmentTarget' { $PolicyAssignment.Add('All Users') }
                            '#microsoft.graph.allLicensedUsersAssignmentTarget' { $PolicyAssignment.Add('All Licenced Users') }
                            '#microsoft.graph.exclusionallUsersAssignmentTarget' { $PolicyExclude.Add('All Users') }
                            '#microsoft.graph.groupAssignmentTarget' { $PolicyAssignment.Add($Groups.Where({ $_.id -eq $target.groupId }).displayName) }
                            '#microsoft.graph.exclusionGroupAssignmentTarget' { $PolicyExclude.Add($Groups.Where({ $_.id -eq $target.groupId }).displayName) }
                            default {
                                $PolicyAssignment.Add($null)
                                $PolicyExclude.Add($null)
                            }
                        }
                    }
                    if ($null -eq $_.displayname) { $_ | Add-Member -NotePropertyName displayName -NotePropertyValue $_.name }
                    $_ | Add-Member -NotePropertyName PolicyTypeName -NotePropertyValue $policyTypeName
                    $_ | Add-Member -NotePropertyName URLName -NotePropertyValue $URLName
                    $_ | Add-Member -NotePropertyName PolicyAssignment -NotePropertyValue ($PolicyAssignment -join ', ')
                    $_ | Add-Member -NotePropertyName PolicyExclude -NotePropertyValue ($PolicyExclude -join ', ')
                    $_
                } | Where-Object { $null -ne $_.DisplayName }
            }
        }

        # Filter the results to sort out linux scripts
        $GraphRequest = $GraphRequest | Where-Object { $_.platforms -ne 'linux' -and $_.templateReference.templateFamily -ne 'deviceConfigurationScripts' }
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
