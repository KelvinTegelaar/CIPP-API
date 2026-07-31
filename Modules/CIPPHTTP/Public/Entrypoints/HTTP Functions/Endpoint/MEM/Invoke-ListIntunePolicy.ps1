function Invoke-ListIntunePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists Intune device configuration policies for a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $id = $Request.Query.ID
    $URLName = $Request.Query.URLName
    $DefinitionIds = $Request.Query.DefinitionIds
    $UseReportDB = $Request.Query.UseReportDB
    $IncludeSettingDefinitions = [System.Convert]::ToBoolean($Request.Query.IncludeSettingDefinitions ?? 'false')
    $IsGroupPolicyDefinitionLookup = ($URLName -ieq 'GroupPolicyDefinitions') -and -not [string]::IsNullOrWhiteSpace($DefinitionIds)

    try {
        # Return cached report data when AllTenants is requested or UseReportDB is set
        if (-not $IsGroupPolicyDefinitionLookup -and ($TenantFilter -eq 'AllTenants' -or $UseReportDB -eq 'true')) {
            try {
                $GraphRequest = Get-CIPPIntunePolicyReport -TenantFilter $TenantFilter -ErrorAction Stop
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }
            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest)
                })
        }

        if ($IsGroupPolicyDefinitionLookup) {
            $DefinitionIdList = @($DefinitionIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { Test-IsGuid -String $_ } | Select-Object -Unique)

            if ($DefinitionIdList.Count -eq 0) {
                $GraphRequest = @()
            } else {
                $DefinitionRequests = [System.Collections.Generic.List[object]]::new()
                $DefinitionIndex = 0

                foreach ($DefinitionId in $DefinitionIdList) {
                    $RequestId = "definition$DefinitionIndex"
                    $DefinitionRequests.Add([PSCustomObject]@{
                            id     = $RequestId
                            method = 'GET'
                            url    = "/deviceManagement/groupPolicyDefinitions('$DefinitionId')?`$expand=presentations"
                        })
                    $DefinitionIndex++
                }

                $DefinitionResults = New-GraphBulkRequest -Requests @($DefinitionRequests) -tenantid $TenantFilter
                $GraphRequest = $DefinitionResults | Where-Object { $_.status -eq 200 -and $_.body.id } | ForEach-Object { $_.body }
            }
        } elseif ($ID) {
            if ($URLName -ieq 'ConfigurationPolicies') {
                $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$ID')?`$expand=settings" -tenantid $TenantFilter

                if ($IncludeSettingDefinitions -and $GraphRequest.settings) {
                    $DefinitionRequests = [System.Collections.Generic.List[object]]::new()
                    $SettingIdMap = @{}
                    $SettingIndex = 0

                    foreach ($Setting in $GraphRequest.settings) {
                        if ($Setting.id) {
                            $RequestId = "setting$SettingIndex"
                            $SettingIdMap[$RequestId] = $Setting.id
                            $DefinitionRequests.Add([PSCustomObject]@{
                                    id     = $RequestId
                                    method = 'GET'
                                    url    = "/deviceManagement/configurationPolicies('$ID')/settings('$($Setting.id)')/settingDefinitions"
                                })
                            $SettingIndex++
                        }
                    }

                    if ($DefinitionRequests.Count -gt 0) {
                        $HasDefinitionFailures = $false
                        $DefinitionResults = New-GraphBulkRequest -Requests @($DefinitionRequests) -tenantid $TenantFilter
                        foreach ($DefinitionResult in $DefinitionResults) {
                            if ($DefinitionResult.status -ne 200) {
                                $HasDefinitionFailures = $true
                                continue
                            }

                            $SettingId = $SettingIdMap[$DefinitionResult.id]
                            $Setting = $GraphRequest.settings | Where-Object { $_.id -eq $SettingId } | Select-Object -First 1
                            if ($Setting) {
                                $Definitions = @($DefinitionResult.body.value ?? $DefinitionResult.body)
                                $Setting | Add-Member -NotePropertyName settingDefinitions -NotePropertyValue $Definitions -Force
                            }
                        }

                        if ($HasDefinitionFailures -and $GraphRequest.templateReference.templateId) {
                            try {
                                $TemplateSettingsResponse = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates('$($GraphRequest.templateReference.templateId)')/settingTemplates?`$expand=settingDefinitions&`$top=1000" -tenantid $TenantFilter
                                $TemplateSettings = @($TemplateSettingsResponse.value ?? $TemplateSettingsResponse)
                                $TemplateDefinitionsByInstanceId = @{}

                                foreach ($TemplateSetting in $TemplateSettings) {
                                    $TemplateInstanceId = $TemplateSetting.settingInstanceTemplate.settingInstanceTemplateId
                                    $TemplateDefinitions = @($TemplateSetting.settingDefinitions | Where-Object { $_.id })
                                    if ($TemplateInstanceId -and $TemplateDefinitions.Count -gt 0) {
                                        $TemplateDefinitionsByInstanceId[$TemplateInstanceId] = $TemplateDefinitions
                                    }
                                }

                                foreach ($Setting in $GraphRequest.settings) {
                                    $ExistingDefinitions = @($Setting.settingDefinitions | Where-Object { $_.id })
                                    if ($ExistingDefinitions.Count -gt 0) { continue }

                                    $TemplateInstanceId = $Setting.settingInstance.settingInstanceTemplateReference.settingInstanceTemplateId
                                    if ($TemplateInstanceId -and $TemplateDefinitionsByInstanceId.ContainsKey($TemplateInstanceId)) {
                                        $Setting | Add-Member -NotePropertyName settingDefinitions -NotePropertyValue $TemplateDefinitionsByInstanceId[$TemplateInstanceId] -Force
                                    }
                                }
                            } catch {
                                Write-Information "Could not retrieve configuration policy template definitions for ${ID}: $($_.Exception.Message)"
                            }
                        }
                    }
                }
            } elseif ($URLName -ieq 'GroupPolicyConfigurations') {
                $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations('$ID')" -tenantid $TenantFilter

                if ($IncludeSettingDefinitions) {
                    $DefinitionValuesResponse = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations('$ID')/definitionValues?`$expand=definition" -tenantid $TenantFilter
                    $DefinitionValues = @($DefinitionValuesResponse.value ?? $DefinitionValuesResponse)
                    $GraphRequest | Add-Member -NotePropertyName definitionValues -NotePropertyValue $DefinitionValues -Force

                    if ($DefinitionValues.Count -gt 0) {
                        $PresentationRequests = [System.Collections.Generic.List[object]]::new()
                        $DefinitionValueLookup = @{}
                        $DefinitionValueIdMap = @{}
                        $DefinitionValueIndex = 0

                        foreach ($DefinitionValue in $DefinitionValues) {
                            if ($DefinitionValue.id) {
                                $RequestId = "definitionValue$DefinitionValueIndex"
                                $DefinitionValueIdMap[$RequestId] = $DefinitionValue.id
                                $DefinitionValueLookup[$DefinitionValue.id] = $DefinitionValue
                                $PresentationRequests.Add([PSCustomObject]@{
                                        id     = $RequestId
                                        method = 'GET'
                                        url    = "/deviceManagement/groupPolicyConfigurations('$ID')/definitionValues('$($DefinitionValue.id)')/presentationValues?`$expand=presentation"
                                    })
                                $DefinitionValueIndex++
                            }
                        }

                        if ($PresentationRequests.Count -gt 0) {
                            $PresentationResults = New-GraphBulkRequest -Requests @($PresentationRequests) -tenantid $TenantFilter
                            foreach ($PresentationResult in $PresentationResults) {
                                $DefinitionValueId = $DefinitionValueIdMap[$PresentationResult.id]
                                $DefinitionValue = $DefinitionValueLookup[$DefinitionValueId]
                                if ($DefinitionValue) {
                                    $PresentationValues = @($PresentationResult.body.value ?? $PresentationResult.body)
                                    $DefinitionValue | Add-Member -NotePropertyName presentationValues -NotePropertyValue $PresentationValues -Force
                                }
                            }
                        }
                    }
                }
            } else {
                $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($URLName)('$ID')" -tenantid $TenantFilter
            }
        } else {
            $PolicyDefinitions = @(Get-CIPPIntunePolicyListDefinitions)
            $BulkRequests = [System.Collections.Generic.List[object]]::new()
            # Fetch group names in the same batch snapshot used to render policy assignments.
            $BulkRequests.Add([PSCustomObject]@{
                    id     = 'Groups'
                    method = 'GET'
                    url    = '/groups?$top=999&$select=id,displayName'
                })
            foreach ($Definition in $PolicyDefinitions) {
                $BulkRequests.Add([PSCustomObject]@{
                        id     = $Definition.Id
                        method = 'GET'
                        url    = $Definition.GraphUri
                    })
            }

            $BulkResults = New-GraphBulkRequest -Requests @($BulkRequests) -tenantid $TenantFilter

            $GroupLookup = @{}
            $GroupResult = $BulkResults | Where-Object { $_.id -eq 'Groups' } | Select-Object -First 1
            foreach ($Group in @($GroupResult.body.value)) {
                if ($Group.id) { $GroupLookup[$Group.id] = $Group.displayName }
            }

            $GraphRequest = foreach ($Definition in $PolicyDefinitions) {
                $Result = $BulkResults | Where-Object { $_.id -eq $Definition.Id } | Select-Object -First 1
                if (-not $Result) { continue }
                if ($null -ne $Result.status -and ($Result.status -lt 200 -or $Result.status -ge 300)) { continue }

                foreach ($Policy in @($Result.body.value)) {
                    # @($null) contains one null element, so guard before parameter binding.
                    if ($null -eq $Policy) { continue }
                    ConvertTo-CIPPIntunePolicyListItem -Policy $Policy -URLName $Definition.Id -DefaultPolicyTypeName $Definition.PolicyTypeName -GroupLookup $GroupLookup
                }
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
