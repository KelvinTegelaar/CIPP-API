# Pester tests for Invoke-ListIntunePolicyFailures
# Validates the failing-only list, policyId validation, and the conflict pairing per policy type

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListIntunePolicyFailures.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListIntunePolicyFailures.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    # Rows per report action name; a scriptblock value throws to simulate a failed report
    function Get-CIPPIntuneReportRows {
        param($TenantFilter, $Uri, $Filter, $Select, $OrderBy, $PageSize)
        $Name = ($Uri -split '/')[-1]
        $script:reportCalls += , @{ Name = $Name; Filter = $Filter }
        $Rows = $script:reports[$Name]
        if ($Rows -is [scriptblock]) { throw 'report down' }
        , @($Rows)
    }
    function New-GraphBulkRequest {
        param($tenantid, $Requests)
        $script:bulkRequests += , @($Requests)
        # The real helper writes each response to the pipeline, not one wrapped array
        @($Requests | ForEach-Object { $script:bulkResponses[[string]$_.id] } | Where-Object { $_ })
    }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    function New-Request {
        param($Query)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListIntunePolicyFailures' }
            Headers = @{ Authorization = 'token' }
            Query   = [pscustomobject](@{ tenantFilter = 'contoso.onmicrosoft.com' } + $Query)
        }
    }
}

Describe 'Invoke-ListIntunePolicyFailures' {
    BeforeEach {
        $script:reportCalls = @()
        $script:bulkRequests = @()
        $script:bulkResponses = @{}
        $script:reports = @{}
        $script:policy = '11111111-1111-1111-1111-111111111111'
        $script:other = '22222222-2222-2222-2222-222222222222'
    }

    Context 'list mode' {
        It 'returns only policies with error or conflict devices, mapped to CIPP names' {
            $script:reports['getConfigurationPolicyNonComplianceSummaryReport'] = @(
                [pscustomobject]@{ PolicyId = 'a'; PolicyName = 'Healthy'; PolicyBaseTypeName = 'DeviceManagementConfigurationPolicy'; NumberOfErrorDevices = 0; NumberOfConflictDevices = 0; NumberOfCompliantDevices = 5; UnifiedPolicyType_loc = 'Settings catalog'; UnifiedPolicyPlatformType_loc = 'Windows 10 and later' }
                [pscustomobject]@{ PolicyId = 'b'; PolicyName = 'Broken'; PolicyBaseTypeName = 'Microsoft.Management.Services.Api.DeviceConfiguration'; NumberOfErrorDevices = 2; NumberOfConflictDevices = 1; NumberOfCompliantDevices = 3; UnifiedPolicyType_loc = 'Device restrictions'; UnifiedPolicyPlatformType_loc = 'Windows 10 and later' }
            )

            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{}) -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($response.Body.Results).Count | Should -Be 1
            $response.Body.Results[0].id | Should -Be 'b'
            $response.Body.Results[0].displayName | Should -Be 'Broken'
            $response.Body.Results[0].URLName | Should -Be 'deviceConfigurations'
            $response.Body.Results[0].PolicyTypeName | Should -Be 'Device restrictions'
            $response.Body.Results[0].errorDevices | Should -Be 2
            $reportCalls[0].Filter | Should -Match "PolicyBaseTypeName eq 'DeviceManagementConfigurationPolicy'"
        }

        It 'answers the pre-tenant first render with an empty list' {
            $request = New-Request @{}
            $request.Query.tenantFilter = $null

            $response = Invoke-ListIntunePolicyFailures -Request $request -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($response.Body.Results).Count | Should -Be 0
            $reportCalls.Count | Should -Be 0
        }

        It 'returns 500 with the reason when the report fails' {
            $script:reports['getConfigurationPolicyNonComplianceSummaryReport'] = { throw }

            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{}) -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $response.Body.Results | Should -Match 'report down'
        }
    }

    Context 'detail mode' {
        BeforeEach {
            $script:reports['getConfigurationPolicyNonComplianceReport'] = @(
                [pscustomobject]@{ IntuneDeviceId = 'd1'; UserId = 'u1'; DeviceName = 'PC1'; ReportStatus = 'Conflict' }
                [pscustomobject]@{ IntuneDeviceId = 'd2'; UserId = 'u2'; DeviceName = 'PC2'; ReportStatus = 'Error' }
                [pscustomobject]@{ IntuneDeviceId = 'd3'; UserId = 'u3'; DeviceName = 'PC3'; ReportStatus = 'Succeeded' }
            )
            $script:reports['getConfigurationPolicySettingsDeviceSummaryReport'] = @(
                [pscustomobject]@{ SettingId = 's-ok'; SettingName = 'Fine'; NumberOfErrorDevices = 0; NumberOfConflictDevices = 0 }
                [pscustomobject]@{ SettingId = 's-fw'; SettingName = 'Firewall'; NumberOfErrorDevices = 1; NumberOfConflictDevices = 1 }
            )
        }

        It 'rejects a policyId that is not a GUID' {
            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{ policyId = 'abc' }) -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $reportCalls.Count | Should -Be 0
        }

        It 'keeps only error and conflict devices and failing settings' {
            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{ policyId = $policy; policyBaseTypeName = 'DeviceConfigurationAdmxPolicy' }) -TriggerMetadata $null

            $response.Body.Results.errors.Count | Should -Be 0 -Because ($response.Body.Results.errors | ConvertTo-Json -Compress)
            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($response.Body.Results.devices).DeviceName | Should -Be @('PC1', 'PC2')
            @($response.Body.Results.settings).Count | Should -Be 1
            $response.Body.Results.settings[0].settingName | Should -Be 'Firewall'
            $response.Body.Results.settings[0].conflictingPolicies | Should -BeNullOrEmpty
            $reportCalls[0].Filter | Should -Be "(PolicyId eq '$policy')"
        }

        It 'pairs classic profile conflicts by the other profiles conflicting on the same setting path' {
            # Intune's settingStates.sources only names the policy itself, so pairing comes from the device's other profiles
            $third = '33333333-3333-3333-3333-333333333333'
            $path = './Vendor/MSFT/Policy/Config/Defender/AVGCPULoadFactor'
            $script:reports['getConfigurationPolicySettingsDeviceSummaryReport'] = @()
            $script:reports['getConfigurationPolicyNonComplianceReport'] = @(
                [pscustomobject]@{ IntuneDeviceId = 'd1'; UserId = 'u1'; DeviceName = 'PC1'; ReportStatus = 'Conflict' }
                [pscustomobject]@{ IntuneDeviceId = 'd1'; UserId = '00000000-0000-0000-0000-000000000000'; DeviceName = 'PC1'; ReportStatus = 'Conflict' }
            )
            $script:bulkResponses['d1'] = [pscustomobject]@{ id = 'd1'; status = 200; body = [pscustomobject]@{ value = @(
                        [pscustomobject]@{ id = $policy; displayName = 'Me'; state = 'conflict' }
                        [pscustomobject]@{ id = $other; displayName = 'Other profile'; state = 'conflict' }
                        [pscustomobject]@{ id = $third; displayName = 'Unrelated'; state = 'conflict' }
                        [pscustomobject]@{ id = '44444444-4444-4444-4444-444444444444'; displayName = 'Healthy'; state = 'compliant' }
                    )
                }
            }
            $ownState = [pscustomobject]@{ setting = $path; settingName = 'Windows10GeneralConfiguration.DefenderScanMaxCpu'; state = 'conflict'; sources = @([pscustomobject]@{ id = $policy; displayName = $null }) }
            $script:bulkResponses["d1/$policy"] = [pscustomobject]@{ id = "d1/$policy"; status = 200; body = [pscustomobject]@{ value = @($ownState, $ownState) } }
            $script:bulkResponses["d1/$other"] = [pscustomobject]@{ id = "d1/$other"; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ setting = $path; state = 'conflict' }) } }
            $script:bulkResponses["d1/$third"] = [pscustomobject]@{ id = "d1/$third"; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ setting = './Vendor/MSFT/Policy/Config/Other'; state = 'conflict' }) } }

            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{ policyId = $policy; policyBaseTypeName = 'Microsoft.Management.Services.Api.DeviceConfiguration' }) -TriggerMetadata $null

            $response.Body.Results.errors.Count | Should -Be 0 -Because ($response.Body.Results.errors | ConvertTo-Json -Compress)
            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            # one device despite two user rows, and only the profiles in conflict on it
            @($bulkRequests[0]).url | Should -Be @('/deviceManagement/managedDevices/d1/deviceConfigurationStates')
            @($bulkRequests[1]).url | Sort-Object | Should -Be @(
                "/deviceManagement/managedDevices/d1/deviceConfigurationStates/$policy/settingStates"
                "/deviceManagement/managedDevices/d1/deviceConfigurationStates/$other/settingStates"
                "/deviceManagement/managedDevices/d1/deviceConfigurationStates/$third/settingStates"
            )
            @($response.Body.Results.settings).Count | Should -Be 1
            $response.Body.Results.settings[0].settingName | Should -Be 'DefenderScanMaxCpu'
            $response.Body.Results.settings[0].conflictDevices | Should -Be 1
            @($response.Body.Results.settings[0].conflictingPolicies) | Should -Be @('Other profile')
        }

        It 'reports refused bulk lookups in errors instead of dropping them silently' {
            $script:reports['getConfigurationPolicySettingsDeviceSummaryReport'] = @()
            $script:reports['getConfigurationPolicyNonComplianceReport'] = @(
                [pscustomobject]@{ IntuneDeviceId = 'd1'; UserId = 'u1'; DeviceName = 'PC1'; ReportStatus = 'Conflict' }
            )
            $script:bulkResponses['d1'] = [pscustomobject]@{ id = 'd1'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Forbidden' } } }

            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{ policyId = $policy; policyBaseTypeName = 'Microsoft.Management.Services.Api.DeviceConfiguration' }) -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::MultiStatus)
            $response.Body.Results.errors.conflicts | Should -Match 'Failed 1 conflict lookup\(s\): d1: Forbidden'
        }

        It 'pairs settings catalog conflicts with applied policies sharing a setting definition' {
            $script:reports['getConfigurationSettingNonComplianceReport'] = @(
                [pscustomobject]@{ SettingName = 'Firewall'; SettingStatus = 6 }
            )
            $script:reports['getConfigurationPoliciesReportForDevice'] = @(
                [pscustomobject]@{ PolicyId = $policy }
                [pscustomobject]@{ PolicyId = $other }
                [pscustomobject]@{ PolicyId = '33333333-3333-3333-3333-333333333333' }
            )
            # The reports name a setting by its definition display name, not its id
            $script:bulkResponses[$policy] = [pscustomobject]@{ id = $policy; status = 200; body = [pscustomobject]@{ name = 'Me'; settings = @([pscustomobject]@{ settingInstance = [pscustomobject]@{ settingDefinitionId = 'device_vendor_msft_firewall_enable' }; settingDefinitions = @([pscustomobject]@{ id = 'device_vendor_msft_firewall_enable'; displayName = 'Firewall' }) }) } }
            $script:bulkResponses[$other] = [pscustomobject]@{ id = $other; status = 200; body = [pscustomobject]@{ name = 'Other catalog'; settings = @([pscustomobject]@{ settingInstance = [pscustomobject]@{ settingDefinitionId = 'device_vendor_msft_firewall_enable' } }) } }
            $script:bulkResponses['33333333-3333-3333-3333-333333333333'] = [pscustomobject]@{ id = '33333333-3333-3333-3333-333333333333'; status = 200; body = [pscustomobject]@{ name = 'Unrelated'; settings = @([pscustomobject]@{ settingInstance = [pscustomobject]@{ settingDefinitionId = 'device_vendor_msft_bitlocker' } }) } }

            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{ policyId = $policy; policyBaseTypeName = 'DeviceManagementConfigurationPolicy' }) -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $settingCall = $reportCalls | Where-Object { $_.Name -eq 'getConfigurationSettingNonComplianceReport' }
            $settingCall.Filter | Should -Be "(PolicyId eq '$policy') and (DeviceId eq 'd1') and (UserId eq 'u1')"
            # the partner lands on the report's own row instead of a second row keyed by the definition id
            @($response.Body.Results.settings).settingName | Should -Be @('Firewall')
            @($response.Body.Results.settings[0].conflictingPolicies) | Should -Be @('Other catalog')
            $response.Body.Results.settings[0].conflictDevices | Should -Be 1
        }

        It 'reports a failed sub-call in errors instead of failing the response' {
            $script:reports['getConfigurationPolicySettingsDeviceSummaryReport'] = { throw }

            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{ policyId = $policy; policyBaseTypeName = 'DeviceConfigurationAdmxPolicy' }) -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::MultiStatus)
            $response.Body.Results.errors.settings | Should -Match 'report down'
            @($response.Body.Results.devices).Count | Should -Be 2
        }
    }
}
