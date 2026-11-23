# Pester tests for Invoke-ListIntuneDeploymentStatus: which Graph source each object type reads,
# how rows are normalized into Devices/Users, and the input checks.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphPOSTRequest { param($uri, $tenantid, $body) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneReportRows.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneDeploymentStatus.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyReportTypeFilter.ps1')

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ListIntuneDeploymentStatus.ps1'
    $EndpointScript = [ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw))
    . $EndpointScript
    $AppEndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/Applications/Invoke-ListAppDeploymentStatus.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $AppEndpointPath -Raw)))

    function Invoke-Status {
        param([string]$Type, [string]$Id = '3697484d-68b1-4888-b143-5b281cecc156')
        $Request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListIntuneDeploymentStatus' }
            Headers = @{}
            Query   = [pscustomobject]@{ tenantFilter = 'contoso.com'; ID = $Id; Type = $Type }
        }
        Invoke-ListIntuneDeploymentStatus -Request $Request -TriggerMetadata $null
    }

    function New-Report {
        param([string[]]$Columns, [object[]]$Rows)
        [pscustomobject]@{
            TotalRowCount = $Rows.Count
            Schema        = @($Columns | ForEach-Object { [pscustomobject]@{ Column = $_ } })
            Values        = $Rows
        }
    }
}

Describe 'Invoke-ListIntuneDeploymentStatus' {
    It 'rejects an id that could break out of the OData filter' {
        Mock -CommandName New-GraphPOSTRequest -MockWith { }

        $Response = Invoke-Status -Type 'mobileApps' -Id "x' or 1 eq 1"

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'reads app device and user install reports filtered on the app' {
        Mock -CommandName New-GraphPOSTRequest -ParameterFilter { $uri -like '*retrieveDeviceAppInstallationStatusReport' } -MockWith {
            New-Report -Columns @('DeviceName', 'UserPrincipalName', 'AppInstallState_loc', 'AppInstallStateDetails_loc', 'HexErrorCode', 'Platform', 'LastModifiedDateTime') -Rows @(
                , @('PC1', 'a@contoso.com', 'Failed', 'Download failed', '0x87D1041C', 'Windows', '2026-11-01T10:00:00')
            )
        }
        Mock -CommandName New-GraphPOSTRequest -ParameterFilter { $uri -like '*getUserInstallStatusReport' } -MockWith {
            New-Report -Columns @('UserPrincipalName', 'UserName', 'InstalledCount', 'FailedCount', 'PendingInstallCount', 'NotInstalledCount', 'NotApplicableCount') -Rows @(
                , @('a@contoso.com', 'A', 1, 1, 0, 0, 0)
            )
        }

        $Response = Invoke-Status -Type 'mobileApps'

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results.Devices[0].Status | Should -Be 'Failed'
        $Response.Body.Results.Devices[0].StatusDetail | Should -Be 'Download failed 0x87D1041C'
        $Response.Body.Results.Users[0].Status | Should -Be 'Failed'
        $Response.Body.Results.Users[0].DeviceCount | Should -Be 2
        Should -Invoke New-GraphPOSTRequest -Times 2 -Exactly -ParameterFilter { ($body | ConvertFrom-Json).filter -eq "(ApplicationId eq '3697484d-68b1-4888-b143-5b281cecc156')" }
    }

    It 'derives users from the devices report for settings catalog, keeping each user''s worst status' {
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            New-Report -Columns @('DeviceName', 'UPN', 'ReportStatus_loc', 'UnifiedPolicyPlatformType_loc', 'PspdpuLastModifiedTimeUtc') -Rows @(
                , @('PC1', 'a@contoso.com', 'Succeeded', 'Windows10', '2026-11-01T10:00:00')
                , @('PC2', 'a@contoso.com', 'Error', 'Windows10', '2026-11-02T10:00:00')
                , @('PC3', '', 'Succeeded', 'Windows10', '2026-11-02T10:00:00')
            )
        }

        # List pages send URLName in their own casing
        $Response = Invoke-Status -Type 'ConfigurationPolicies'

        $Response.Body.Results.Devices | Should -HaveCount 3
        $UserA = $Response.Body.Results.Users | Where-Object UserPrincipalName -EQ 'a@contoso.com'
        $UserA.Status | Should -Be 'Error'
        $UserA.DeviceCount | Should -Be 2
        ($Response.Body.Results.Users | Where-Object UserName -EQ 'No user').DeviceCount | Should -Be 1
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -like '*/reports/getConfigurationPolicyDevicesReport' -and ($body | ConvertFrom-Json).filter -like "*DeviceManagementConfigurationPolicy*PolicyId eq '3697484d-68b1-4888-b143-5b281cecc156'*"
        }
    }

    It 'reads legacy status collections and keeps Compliant for compliance policies' {
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/deviceStatuses' } -MockWith {
            @(
                [pscustomobject]@{ deviceDisplayName = 'PC1'; userPrincipalName = 'a@contoso.com'; status = 'nonCompliant'; lastReportedDateTime = '2026-11-01T10:00:00Z' }
                [pscustomobject]@{ deviceDisplayName = ''; userPrincipalName = 'b@contoso.com'; status = 'compliant'; lastReportedDateTime = '0001-01-01T00:00:00Z' }
            )
        }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/userStatuses' } -MockWith {
            [pscustomobject]@{ userPrincipalName = ''; userDisplayName = ''; status = 'compliant'; devicesCount = 3 }
        }

        $Response = Invoke-Status -Type 'deviceCompliancePolicies'

        $Response.Body.Results.Devices[0].Status | Should -Be 'Non compliant'
        $Response.Body.Results.Devices[1].Status | Should -Be 'Compliant'
        $Response.Body.Results.Devices[1].LastReported | Should -BeNullOrEmpty
        $Response.Body.Results.Users[0].UserName | Should -Be 'System account'
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like "*/deviceManagement/deviceCompliancePolicies('3697484d-68b1-4888-b143-5b281cecc156')/deviceStatuses" }
    }

    It 'calls a compliant configuration profile Succeeded, like the Intune portal' {
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ deviceDisplayName = 'PC1'; status = 'compliant' } }

        $Response = Invoke-Status -Type 'DeviceConfigurations'

        $Response.Body.Results.Devices[0].Status | Should -Be 'Succeeded'
    }

    It 'reads script run states with the managed device expanded' {
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/deviceRunStates*' } -MockWith {
            [pscustomobject]@{ runState = 'scriptError'; errorDescription = 'exit 1'; managedDevice = [pscustomobject]@{ deviceName = 'PC1'; userPrincipalName = 'a@contoso.com' } }
        }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/userRunStates' } -MockWith {
            [pscustomobject]@{ userPrincipalName = 'a@contoso.com'; successDeviceCount = 1; errorDeviceCount = 1 }
        }

        $Response = Invoke-Status -Type 'deviceManagementScripts'

        $Response.Body.Results.Devices[0].DeviceName | Should -Be 'PC1'
        $Response.Body.Results.Devices[0].Status | Should -Be 'Script error'
        $Response.Body.Results.Users[0].Status | Should -Be 'Error'
        $Response.Body.Results.Users[0].DeviceCount | Should -Be 2
    }

    It 'lists app protection users from the registrations the policy applies to, with no device side' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{ userId = 'u1'; deviceName = 'Phone'; deviceType = 'iPhone'; flaggedReasons = @('none'); appIdentifier = [pscustomobject]@{ bundleId = 'com.microsoft.outlook' }; appliedPolicies = @([pscustomobject]@{ id = 'T_abc' }) }
                [pscustomobject]@{ userId = 'u2'; deviceName = 'Other'; flaggedReasons = @('none'); appIdentifier = [pscustomobject]@{ packageId = 'x' }; appliedPolicies = @([pscustomobject]@{ id = 'T_other' }) }
            )
        }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            [pscustomobject]@{ id = 'u1'; body = [pscustomobject]@{ id = 'u1'; userPrincipalName = 'a@contoso.com'; displayName = 'A' } }
        }

        $Response = Invoke-Status -Type 'iosManagedAppProtection' -Id 'T_abc'

        $Response.Body.Results.Devices | Should -BeNullOrEmpty
        $Response.Body.Results.Users | Should -HaveCount 1
        $Response.Body.Results.Users[0].UserPrincipalName | Should -Be 'a@contoso.com'
        $Response.Body.Results.Users[0].Status | Should -Be 'Checked in'
        $Response.Body.Results.Users[0].StatusDetail | Should -Be 'com.microsoft.outlook on Phone (iPhone)'
    }

    It 'keeps empty and single-row results as arrays, so a supported type never looks unsupported' {
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/deviceStatuses' } -MockWith { }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/userStatuses' } -MockWith { [pscustomobject]@{ userPrincipalName = 'a@contoso.com'; status = 'compliant' } }

        $Response = Invoke-Status -Type 'deviceCompliancePolicies'

        ($Response.Body | ConvertTo-Json -Depth 5 -Compress) | Should -BeLike '*"Devices":`[`]*'
        ($Response.Body | ConvertTo-Json -Depth 5 -Compress) | Should -BeLike '*"Users":`[{*'
    }

    It 'returns null Devices and Users for a type without a status source' {
        Mock -CommandName New-GraphGetRequest -MockWith { }

        $Response = Invoke-Status -Type 'windowsFeatureUpdateProfiles'

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results.Devices | Should -BeNullOrEmpty
        $Response.Body.Results.Users | Should -BeNullOrEmpty
        $Response.Body.Results.Contains('Devices') | Should -BeTrue
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
    }

    It 'returns the Graph error as a 500' {
        Mock -CommandName New-GraphPOSTRequest -MockWith { throw 'Forbidden' }

        $Response = Invoke-Status -Type 'mobileApps'

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Match 'Failed to load deployment status for mobileApps'
    }
}

Describe 'Invoke-ListAppDeploymentStatus' {
    It 'is readable with application permissions' {
        (Get-Help Invoke-ListAppDeploymentStatus).Role | Should -Be 'Endpoint.Application.Read'
    }

    It 'only ever reads app status, whatever Type the caller sends' {
        Mock -CommandName New-GraphPOSTRequest -MockWith { New-Report -Columns @('DeviceName') -Rows @() }
        Mock -CommandName New-GraphGetRequest -MockWith { }
        $Request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListAppDeploymentStatus' }
            Headers = @{}
            Query   = [pscustomobject]@{ tenantFilter = 'contoso.com'; ID = 'app-1'; Type = 'deviceCompliancePolicies' }
        }

        $Response = Invoke-ListAppDeploymentStatus -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*retrieveDeviceAppInstallationStatusReport' -and ($body | ConvertFrom-Json).filter -eq "(ApplicationId eq 'app-1')" }
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
    }
}

Describe 'Invoke-ListIntuneDeploymentStatus response snapshots' {
    BeforeAll {
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        $script:Fail = $false

        Mock -CommandName New-GraphPOSTRequest -MockWith {
            if ($script:Fail) { throw 'Forbidden' }
            $script:Calls.Add("POST $uri $(($body | ConvertFrom-Json).filter)")
            switch -Wildcard ($uri) {
                '*retrieveDeviceAppInstallationStatusReport' {
                    New-Report -Columns @('DeviceId', 'DeviceName', 'UserPrincipalName', 'AppInstallState', 'AppInstallState_loc', 'AppInstallStateDetails_loc', 'HexErrorCode', 'Platform', 'LastModifiedDateTime') -Rows @(
                        , @('dev-1', 'PC1', 'a@contoso.com', 'failed', 'Failed', 'Download failed', '0x87D1041C', 'Windows', '2026-11-01T10:00:00')
                        , @('dev-2', 'PC2', 'b@contoso.com', 'notInstalled', $null, $null, $null, 'Windows', '0001-01-01T00:00:00')
                    )
                }
                '*getUserInstallStatusReport' {
                    New-Report -Columns @('UserPrincipalName', 'UserName', 'InstalledCount', 'FailedCount', 'PendingInstallCount', 'NotInstalledCount', 'NotApplicableCount') -Rows @(
                        , @('a@contoso.com', 'A', 1, 1, 0, 0, 0)
                        , @('b@contoso.com', 'B', 0, 0, 1, 0, 0)
                        , @('c@contoso.com', 'C', 0, 0, 0, 2, 0)
                        , @('d@contoso.com', 'D', 3, 0, 0, 0, 1)
                        , @('e@contoso.com', 'E', 0, 0, 0, 0, 0)
                    )
                }
                '*getConfigurationPolicyDevicesReport' {
                    New-Report -Columns @('IntuneDeviceId', 'DeviceId', 'DeviceName', 'UPN', 'ReportStatus', 'ReportStatus_loc', 'UnifiedPolicyPlatformType_loc', 'PspdpuLastModifiedTimeUtc') -Rows @(
                        , @('dev-1', '', 'PC1', 'a@contoso.com', 'succeeded', 'Succeeded', 'Windows10', '2026-11-01T10:00:00')
                        , @('dev-2', '', 'PC2', 'a@contoso.com', 'error', 'Error', 'Windows10', '2026-11-02T10:00:00')
                        , @('', 'dev-3', 'PC3', '', 'conflict', $null, 'Windows10', '2026-11-03T10:00:00')
                    )
                }
            }
        }

        Mock -CommandName New-GraphGetRequest -MockWith {
            if ($script:Fail) { throw 'Forbidden' }
            $script:Calls.Add("GET $uri")
            switch -Wildcard ($uri) {
                '*/deviceStatuses' {
                    @(
                        [pscustomobject]@{ id = 'pol_user-a_dev-1'; deviceDisplayName = 'PC1'; userPrincipalName = 'a@contoso.com'; status = 'compliant'; deviceModel = 'Surface'; lastReportedDateTime = '2026-11-01T10:00:00Z' }
                        [pscustomobject]@{ id = 'pol_user-b_dev-2'; deviceDisplayName = 'PC2'; userPrincipalName = 'b@contoso.com'; status = 'nonCompliant'; deviceModel = 'Latitude'; lastReportedDateTime = '0001-01-01T00:00:00Z' }
                        [pscustomobject]@{ deviceDisplayName = 'PC3'; userPrincipalName = ''; status = $null; deviceModel = $null; lastReportedDateTime = $null }
                    )
                }
                '*/userStatuses' {
                    @(
                        [pscustomobject]@{ userPrincipalName = 'a@contoso.com'; userDisplayName = 'A'; status = 'compliant'; devicesCount = 1; lastReportedDateTime = '2026-11-01T10:00:00Z' }
                        [pscustomobject]@{ userPrincipalName = ''; userDisplayName = ''; status = 'error'; devicesCount = 3; lastReportedDateTime = '2026-11-02T10:00:00Z' }
                    )
                }
                '*/deviceRunStates*' {
                    @(
                        [pscustomobject]@{ runState = 'success'; detectionState = 'success'; remediationState = 'skipped'; errorDescription = $null; lastStateUpdateDateTime = '2026-11-01T10:00:00Z'; managedDevice = [pscustomobject]@{ id = 'dev-1'; deviceName = 'PC1'; userPrincipalName = 'a@contoso.com'; operatingSystem = 'Windows' } }
                        [pscustomobject]@{ runState = 'scriptError'; detectionState = 'fail'; remediationState = 'remediationFailed'; errorDescription = 'exit 1'; lastStateUpdateDateTime = '2026-11-02T10:00:00Z'; managedDevice = [pscustomobject]@{ id = 'dev-2'; deviceName = 'PC2'; userPrincipalName = 'a@contoso.com'; operatingSystem = 'macOS' } }
                    )
                }
                '*/userRunStates' {
                    [pscustomobject]@{ userPrincipalName = 'a@contoso.com'; successDeviceCount = 1; errorDeviceCount = 1 }
                    [pscustomobject]@{ userPrincipalName = 'b@contoso.com'; successDeviceCount = 2; errorDeviceCount = 0 }
                }
                '*/managedAppRegistrations*' {
                    [pscustomobject]@{ userId = 'u1'; deviceName = 'Phone'; deviceType = 'iPhone'; lastSyncDateTime = '2026-11-01T10:00:00Z'; flaggedReasons = @('none'); appIdentifier = [pscustomobject]@{ bundleId = 'com.microsoft.outlook' }; appliedPolicies = @([pscustomobject]@{ id = 'T_abc' }) }
                    [pscustomobject]@{ userId = 'u2'; deviceName = 'Tablet'; deviceType = 'android'; lastSyncDateTime = '2026-11-02T10:00:00Z'; flaggedReasons = @('rootedDevice'); appIdentifier = [pscustomobject]@{ packageId = 'com.microsoft.teams' }; appliedPolicies = @([pscustomobject]@{ id = 'T_abc' }, [pscustomobject]@{ id = 'T_x' }) }
                    [pscustomobject]@{ userId = 'u3'; deviceName = 'Other'; flaggedReasons = @(); appIdentifier = [pscustomobject]@{ packageId = 'x' }; appliedPolicies = @([pscustomobject]@{ id = 'T_other' }) }
                }
            }
        }

        Mock -CommandName New-GraphBulkRequest -MockWith {
            $script:Calls.Add("BULK $(@($Requests.url) -join ' ')")
            [pscustomobject]@{ id = 'u1'; body = [pscustomobject]@{ id = 'u1'; userPrincipalName = 'a@contoso.com'; displayName = 'A' } }
        }

        function Get-Snapshot {
            param([string]$Type, [string]$Id = '3697484d-68b1-4888-b143-5b281cecc156')
            $script:Calls.Clear()
            $Response = Invoke-Status -Type $Type -Id $Id
            [ordered]@{
                StatusCode = $Response.StatusCode
                Body       = $Response.Body
                Calls      = @($script:Calls)
            } | ConvertTo-Json -Depth 10 -Compress
        }
    }

    AfterEach {
        $script:Fail = $false
    }

    It 'pins the <Type> response' -ForEach @(
        @{ Type = 'mobileApps'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":[{"DeviceId":"dev-1","DeviceName":"PC1","UserPrincipalName":"a@contoso.com","Status":"Failed","StatusDetail":"Download failed 0x87D1041C","Platform":"Windows","LastReported":"2026-11-01T10:00:00"},{"DeviceId":"dev-2","DeviceName":"PC2","UserPrincipalName":"b@contoso.com","Status":"Not installed","StatusDetail":"","Platform":"Windows","LastReported":null}],"Users":[{"UserPrincipalName":"a@contoso.com","UserName":"A","Status":"Failed","StatusDetail":"1 installed, 1 failed, 0 pending, 0 not installed, 0 not applicable","DeviceCount":2,"LastReported":null},{"UserPrincipalName":"b@contoso.com","UserName":"B","Status":"Install pending","StatusDetail":"0 installed, 0 failed, 1 pending, 0 not installed, 0 not applicable","DeviceCount":1,"LastReported":null},{"UserPrincipalName":"c@contoso.com","UserName":"C","Status":"Not installed","StatusDetail":"0 installed, 0 failed, 0 pending, 2 not installed, 0 not applicable","DeviceCount":2,"LastReported":null},{"UserPrincipalName":"d@contoso.com","UserName":"D","Status":"Installed","StatusDetail":"3 installed, 0 failed, 0 pending, 0 not installed, 1 not applicable","DeviceCount":4,"LastReported":null},{"UserPrincipalName":"e@contoso.com","UserName":"E","Status":"Not applicable","StatusDetail":"0 installed, 0 failed, 0 pending, 0 not installed, 0 not applicable","DeviceCount":0,"LastReported":null}]}},"Calls":["POST https://graph.microsoft.com/beta/deviceManagement/reports/retrieveDeviceAppInstallationStatusReport (ApplicationId eq ''3697484d-68b1-4888-b143-5b281cecc156'')","POST https://graph.microsoft.com/beta/deviceManagement/reports/getUserInstallStatusReport (ApplicationId eq ''3697484d-68b1-4888-b143-5b281cecc156'')"]}' }
        @{ Type = 'deviceConfigurations'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":[{"DeviceId":"dev-1","DeviceName":"PC1","UserPrincipalName":"a@contoso.com","Status":"Succeeded","StatusDetail":null,"Platform":"Surface","LastReported":"2026-11-01T10:00:00Z"},{"DeviceId":"dev-2","DeviceName":"PC2","UserPrincipalName":"b@contoso.com","Status":"Non compliant","StatusDetail":null,"Platform":"Latitude","LastReported":null},{"DeviceId":null,"DeviceName":"PC3","UserPrincipalName":"","Status":"Unknown","StatusDetail":null,"Platform":null,"LastReported":null}],"Users":[{"UserPrincipalName":"a@contoso.com","UserName":"A","Status":"Succeeded","StatusDetail":null,"DeviceCount":1,"LastReported":"2026-11-01T10:00:00Z"},{"UserPrincipalName":null,"UserName":"System account","Status":"Error","StatusDetail":null,"DeviceCount":3,"LastReported":"2026-11-02T10:00:00Z"}]}},"Calls":["GET https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations(''3697484d-68b1-4888-b143-5b281cecc156'')/deviceStatuses","GET https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations(''3697484d-68b1-4888-b143-5b281cecc156'')/userStatuses"]}' }
        @{ Type = 'deviceCompliancePolicies'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":[{"DeviceId":"dev-1","DeviceName":"PC1","UserPrincipalName":"a@contoso.com","Status":"Compliant","StatusDetail":null,"Platform":"Surface","LastReported":"2026-11-01T10:00:00Z"},{"DeviceId":"dev-2","DeviceName":"PC2","UserPrincipalName":"b@contoso.com","Status":"Non compliant","StatusDetail":null,"Platform":"Latitude","LastReported":null},{"DeviceId":null,"DeviceName":"PC3","UserPrincipalName":"","Status":"Unknown","StatusDetail":null,"Platform":null,"LastReported":null}],"Users":[{"UserPrincipalName":"a@contoso.com","UserName":"A","Status":"Compliant","StatusDetail":null,"DeviceCount":1,"LastReported":"2026-11-01T10:00:00Z"},{"UserPrincipalName":null,"UserName":"System account","Status":"Error","StatusDetail":null,"DeviceCount":3,"LastReported":"2026-11-02T10:00:00Z"}]}},"Calls":["GET https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies(''3697484d-68b1-4888-b143-5b281cecc156'')/deviceStatuses","GET https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies(''3697484d-68b1-4888-b143-5b281cecc156'')/userStatuses"]}' }
        @{ Type = 'mobileAppConfigurations'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":[{"DeviceId":"dev-1","DeviceName":"PC1","UserPrincipalName":"a@contoso.com","Status":"Succeeded","StatusDetail":null,"Platform":"Surface","LastReported":"2026-11-01T10:00:00Z"},{"DeviceId":"dev-2","DeviceName":"PC2","UserPrincipalName":"b@contoso.com","Status":"Non compliant","StatusDetail":null,"Platform":"Latitude","LastReported":null},{"DeviceId":null,"DeviceName":"PC3","UserPrincipalName":"","Status":"Unknown","StatusDetail":null,"Platform":null,"LastReported":null}],"Users":[{"UserPrincipalName":"a@contoso.com","UserName":"A","Status":"Succeeded","StatusDetail":null,"DeviceCount":1,"LastReported":"2026-11-01T10:00:00Z"},{"UserPrincipalName":null,"UserName":"System account","Status":"Error","StatusDetail":null,"DeviceCount":3,"LastReported":"2026-11-02T10:00:00Z"}]}},"Calls":["GET https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations(''3697484d-68b1-4888-b143-5b281cecc156'')/deviceStatuses","GET https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations(''3697484d-68b1-4888-b143-5b281cecc156'')/userStatuses"]}' }
        @{ Type = 'configurationPolicies'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":[{"DeviceId":"dev-1","DeviceName":"PC1","UserPrincipalName":"a@contoso.com","Status":"Succeeded","StatusDetail":null,"Platform":"Windows10","LastReported":"2026-11-01T10:00:00"},{"DeviceId":"dev-2","DeviceName":"PC2","UserPrincipalName":"a@contoso.com","Status":"Error","StatusDetail":null,"Platform":"Windows10","LastReported":"2026-11-02T10:00:00"},{"DeviceId":"dev-3","DeviceName":"PC3","UserPrincipalName":"","Status":"conflict","StatusDetail":null,"Platform":"Windows10","LastReported":"2026-11-03T10:00:00"}],"Users":[{"UserPrincipalName":null,"UserName":"No user","Status":"conflict","StatusDetail":null,"DeviceCount":1,"LastReported":"2026-11-03T10:00:00"},{"UserPrincipalName":"a@contoso.com","UserName":null,"Status":"Error","StatusDetail":null,"DeviceCount":2,"LastReported":"2026-11-02T10:00:00"}]}},"Calls":["POST https://graph.microsoft.com/beta/deviceManagement/reports/getConfigurationPolicyDevicesReport ((PolicyBaseTypeName eq ''Microsoft.Management.Services.Api.DeviceConfiguration'') or (PolicyBaseTypeName eq ''DeviceManagementConfigurationPolicy'') or (PolicyBaseTypeName eq ''DeviceConfigurationAdmxPolicy'') or (PolicyBaseTypeName eq ''Microsoft.Management.Services.Api.DeviceManagementIntent'')) and (PolicyId eq ''3697484d-68b1-4888-b143-5b281cecc156'')"]}' }
        @{ Type = 'groupPolicyConfigurations'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":[{"DeviceId":"dev-1","DeviceName":"PC1","UserPrincipalName":"a@contoso.com","Status":"Succeeded","StatusDetail":null,"Platform":"Windows10","LastReported":"2026-11-01T10:00:00"},{"DeviceId":"dev-2","DeviceName":"PC2","UserPrincipalName":"a@contoso.com","Status":"Error","StatusDetail":null,"Platform":"Windows10","LastReported":"2026-11-02T10:00:00"},{"DeviceId":"dev-3","DeviceName":"PC3","UserPrincipalName":"","Status":"conflict","StatusDetail":null,"Platform":"Windows10","LastReported":"2026-11-03T10:00:00"}],"Users":[{"UserPrincipalName":null,"UserName":"No user","Status":"conflict","StatusDetail":null,"DeviceCount":1,"LastReported":"2026-11-03T10:00:00"},{"UserPrincipalName":"a@contoso.com","UserName":null,"Status":"Error","StatusDetail":null,"DeviceCount":2,"LastReported":"2026-11-02T10:00:00"}]}},"Calls":["POST https://graph.microsoft.com/beta/deviceManagement/reports/getConfigurationPolicyDevicesReport ((PolicyBaseTypeName eq ''Microsoft.Management.Services.Api.DeviceConfiguration'') or (PolicyBaseTypeName eq ''DeviceManagementConfigurationPolicy'') or (PolicyBaseTypeName eq ''DeviceConfigurationAdmxPolicy'') or (PolicyBaseTypeName eq ''Microsoft.Management.Services.Api.DeviceManagementIntent'')) and (PolicyId eq ''3697484d-68b1-4888-b143-5b281cecc156'')"]}' }
        @{ Type = 'intents'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":[{"DeviceId":"dev-1","DeviceName":"PC1","UserPrincipalName":"a@contoso.com","Status":"Succeeded","StatusDetail":null,"Platform":"Windows10","LastReported":"2026-11-01T10:00:00"},{"DeviceId":"dev-2","DeviceName":"PC2","UserPrincipalName":"a@contoso.com","Status":"Error","StatusDetail":null,"Platform":"Windows10","LastReported":"2026-11-02T10:00:00"},{"DeviceId":"dev-3","DeviceName":"PC3","UserPrincipalName":"","Status":"conflict","StatusDetail":null,"Platform":"Windows10","LastReported":"2026-11-03T10:00:00"}],"Users":[{"UserPrincipalName":null,"UserName":"No user","Status":"conflict","StatusDetail":null,"DeviceCount":1,"LastReported":"2026-11-03T10:00:00"},{"UserPrincipalName":"a@contoso.com","UserName":null,"Status":"Error","StatusDetail":null,"DeviceCount":2,"LastReported":"2026-11-02T10:00:00"}]}},"Calls":["POST https://graph.microsoft.com/beta/deviceManagement/reports/getConfigurationPolicyDevicesReport ((PolicyBaseTypeName eq ''Microsoft.Management.Services.Api.DeviceConfiguration'') or (PolicyBaseTypeName eq ''DeviceManagementConfigurationPolicy'') or (PolicyBaseTypeName eq ''DeviceConfigurationAdmxPolicy'') or (PolicyBaseTypeName eq ''Microsoft.Management.Services.Api.DeviceManagementIntent'')) and (PolicyId eq ''3697484d-68b1-4888-b143-5b281cecc156'')"]}' }
        @{ Type = 'deviceManagementScripts'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":[{"DeviceId":"dev-1","DeviceName":"PC1","UserPrincipalName":"a@contoso.com","Status":"Success","StatusDetail":null,"Platform":"Windows","LastReported":"2026-11-01T10:00:00Z"},{"DeviceId":"dev-2","DeviceName":"PC2","UserPrincipalName":"a@contoso.com","Status":"Script error","StatusDetail":"exit 1","Platform":"macOS","LastReported":"2026-11-02T10:00:00Z"}],"Users":[{"UserPrincipalName":"a@contoso.com","UserName":null,"Status":"Error","StatusDetail":"1 succeeded, 1 failed","DeviceCount":2,"LastReported":null},{"UserPrincipalName":"b@contoso.com","UserName":null,"Status":"Success","StatusDetail":"2 succeeded, 0 failed","DeviceCount":2,"LastReported":null}]}},"Calls":["GET https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts(''3697484d-68b1-4888-b143-5b281cecc156'')/deviceRunStates?$expand=managedDevice($select=id,deviceName,userPrincipalName,operatingSystem)","GET https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts(''3697484d-68b1-4888-b143-5b281cecc156'')/userRunStates"]}' }
        @{ Type = 'deviceShellScripts'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":[{"DeviceId":"dev-1","DeviceName":"PC1","UserPrincipalName":"a@contoso.com","Status":"Success","StatusDetail":null,"Platform":"Windows","LastReported":"2026-11-01T10:00:00Z"},{"DeviceId":"dev-2","DeviceName":"PC2","UserPrincipalName":"a@contoso.com","Status":"Script error","StatusDetail":"exit 1","Platform":"macOS","LastReported":"2026-11-02T10:00:00Z"}],"Users":[{"UserPrincipalName":"a@contoso.com","UserName":null,"Status":"Error","StatusDetail":"1 succeeded, 1 failed","DeviceCount":2,"LastReported":null},{"UserPrincipalName":"b@contoso.com","UserName":null,"Status":"Success","StatusDetail":"2 succeeded, 0 failed","DeviceCount":2,"LastReported":null}]}},"Calls":["GET https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts(''3697484d-68b1-4888-b143-5b281cecc156'')/deviceRunStates?$expand=managedDevice($select=id,deviceName,userPrincipalName,operatingSystem)","GET https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts(''3697484d-68b1-4888-b143-5b281cecc156'')/userRunStates"]}' }
        @{ Type = 'deviceHealthScripts'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":[{"DeviceId":"dev-1","DeviceName":"PC1","UserPrincipalName":"a@contoso.com","Status":"Success","StatusDetail":"Remediation: Skipped","Platform":"Windows","LastReported":"2026-11-01T10:00:00Z"},{"DeviceId":"dev-2","DeviceName":"PC2","UserPrincipalName":"a@contoso.com","Status":"Fail","StatusDetail":"Remediation: Remediation failed","Platform":"macOS","LastReported":"2026-11-02T10:00:00Z"}],"Users":[{"UserPrincipalName":"a@contoso.com","UserName":null,"Status":"Fail","StatusDetail":null,"DeviceCount":2,"LastReported":"2026-11-02T10:00:00Z"}]}},"Calls":["GET https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts(''3697484d-68b1-4888-b143-5b281cecc156'')/deviceRunStates?$expand=managedDevice($select=id,deviceName,userPrincipalName,operatingSystem)"]}' }
        @{ Type = 'windowsFeatureUpdateProfiles'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":null,"Users":null}},"Calls":[]}' }
        @{ Type = 'hardwareConfigurations'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":null,"Users":null}},"Calls":[]}' }
    ) {
        Get-Snapshot -Type $Type | Should -BeExactly $Expected
    }

    It 'pins the <Type> app protection response' -ForEach @(
        @{ Type = 'androidManagedAppProtection'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":null,"Users":[{"UserPrincipalName":"a@contoso.com","UserName":"A","Status":"Checked in","StatusDetail":"com.microsoft.outlook on Phone (iPhone)","DeviceCount":null,"LastReported":"2026-11-01T10:00:00Z"},{"UserPrincipalName":"u2","UserName":null,"Status":"Rooted device","StatusDetail":"com.microsoft.teams on Tablet (android)","DeviceCount":null,"LastReported":"2026-11-02T10:00:00Z"}]}},"Calls":["GET https://graph.microsoft.com/beta/deviceAppManagement/managedAppRegistrations?$expand=appliedPolicies($select=id)","BULK /users/u1?$select=id,userPrincipalName,displayName /users/u2?$select=id,userPrincipalName,displayName"]}' }
        @{ Type = 'iosManagedAppProtections'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":null,"Users":[{"UserPrincipalName":"a@contoso.com","UserName":"A","Status":"Checked in","StatusDetail":"com.microsoft.outlook on Phone (iPhone)","DeviceCount":null,"LastReported":"2026-11-01T10:00:00Z"},{"UserPrincipalName":"u2","UserName":null,"Status":"Rooted device","StatusDetail":"com.microsoft.teams on Tablet (android)","DeviceCount":null,"LastReported":"2026-11-02T10:00:00Z"}]}},"Calls":["GET https://graph.microsoft.com/beta/deviceAppManagement/managedAppRegistrations?$expand=appliedPolicies($select=id)","BULK /users/u1?$select=id,userPrincipalName,displayName /users/u2?$select=id,userPrincipalName,displayName"]}' }
        @{ Type = 'windowsManagedAppProtection'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":null,"Users":[{"UserPrincipalName":"a@contoso.com","UserName":"A","Status":"Checked in","StatusDetail":"com.microsoft.outlook on Phone (iPhone)","DeviceCount":null,"LastReported":"2026-11-01T10:00:00Z"},{"UserPrincipalName":"u2","UserName":null,"Status":"Rooted device","StatusDetail":"com.microsoft.teams on Tablet (android)","DeviceCount":null,"LastReported":"2026-11-02T10:00:00Z"}]}},"Calls":["GET https://graph.microsoft.com/beta/deviceAppManagement/managedAppRegistrations?$expand=appliedPolicies($select=id)","BULK /users/u1?$select=id,userPrincipalName,displayName /users/u2?$select=id,userPrincipalName,displayName"]}' }
        @{ Type = 'mdmWindowsInformationProtectionPolicies'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":null,"Users":[{"UserPrincipalName":"a@contoso.com","UserName":"A","Status":"Checked in","StatusDetail":"com.microsoft.outlook on Phone (iPhone)","DeviceCount":null,"LastReported":"2026-11-01T10:00:00Z"},{"UserPrincipalName":"u2","UserName":null,"Status":"Rooted device","StatusDetail":"com.microsoft.teams on Tablet (android)","DeviceCount":null,"LastReported":"2026-11-02T10:00:00Z"}]}},"Calls":["GET https://graph.microsoft.com/beta/deviceAppManagement/managedAppRegistrations?$expand=appliedPolicies($select=id)","BULK /users/u1?$select=id,userPrincipalName,displayName /users/u2?$select=id,userPrincipalName,displayName"]}' }
        @{ Type = 'windowsInformationProtectionPolicy'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":null,"Users":[{"UserPrincipalName":"a@contoso.com","UserName":"A","Status":"Checked in","StatusDetail":"com.microsoft.outlook on Phone (iPhone)","DeviceCount":null,"LastReported":"2026-11-01T10:00:00Z"},{"UserPrincipalName":"u2","UserName":null,"Status":"Rooted device","StatusDetail":"com.microsoft.teams on Tablet (android)","DeviceCount":null,"LastReported":"2026-11-02T10:00:00Z"}]}},"Calls":["GET https://graph.microsoft.com/beta/deviceAppManagement/managedAppRegistrations?$expand=appliedPolicies($select=id)","BULK /users/u1?$select=id,userPrincipalName,displayName /users/u2?$select=id,userPrincipalName,displayName"]}' }
        @{ Type = 'targetedManagedAppConfigurations'; Expected = '{"StatusCode":200,"Body":{"Results":{"Devices":null,"Users":[{"UserPrincipalName":"a@contoso.com","UserName":"A","Status":"Checked in","StatusDetail":"com.microsoft.outlook on Phone (iPhone)","DeviceCount":null,"LastReported":"2026-11-01T10:00:00Z"},{"UserPrincipalName":"u2","UserName":null,"Status":"Rooted device","StatusDetail":"com.microsoft.teams on Tablet (android)","DeviceCount":null,"LastReported":"2026-11-02T10:00:00Z"}]}},"Calls":["GET https://graph.microsoft.com/beta/deviceAppManagement/managedAppRegistrations?$expand=appliedPolicies($select=id)","BULK /users/u1?$select=id,userPrincipalName,displayName /users/u2?$select=id,userPrincipalName,displayName"]}' }
    ) {
        Get-Snapshot -Type $Type -Id 'T_abc' | Should -BeExactly $Expected
    }

    It 'pins the response for <Name>' -ForEach @(
        @{ Name = 'a missing type'; Type = ''; Id = 'abc'; Expected = '{"StatusCode":400,"Body":{"Results":"A valid ID and Type are required."},"Calls":[]}' }
        @{ Name = 'an invalid id'; Type = 'deviceConfigurations'; Id = 'a/b'; Expected = '{"StatusCode":400,"Body":{"Results":"A valid ID and Type are required."},"Calls":[]}' }
        @{ Name = 'a missing id'; Type = 'deviceConfigurations'; Id = ''; Expected = '{"StatusCode":400,"Body":{"Results":"A valid ID and Type are required."},"Calls":[]}' }
    ) {
        Get-Snapshot -Type $Type -Id $Id | Should -BeExactly $Expected
    }

    It 'pins the Graph failure response for <Type>' -ForEach @(
        @{ Type = 'mobileApps'; Expected = '{"StatusCode":500,"Body":{"Results":"Failed to load deployment status for mobileApps 3697484d-68b1-4888-b143-5b281cecc156: Forbidden"},"Calls":[]}' }
        @{ Type = 'DeviceConfigurations'; Expected = '{"StatusCode":500,"Body":{"Results":"Failed to load deployment status for deviceConfigurations 3697484d-68b1-4888-b143-5b281cecc156: Forbidden"},"Calls":[]}' }
        @{ Type = 'ConfigurationPolicies'; Expected = '{"StatusCode":500,"Body":{"Results":"Failed to load deployment status for configurationPolicies 3697484d-68b1-4888-b143-5b281cecc156: Forbidden"},"Calls":[]}' }
        @{ Type = 'deviceHealthScripts'; Expected = '{"StatusCode":500,"Body":{"Results":"Failed to load deployment status for deviceHealthScripts 3697484d-68b1-4888-b143-5b281cecc156: Forbidden"},"Calls":[]}' }
        @{ Type = 'iosManagedAppProtection'; Expected = '{"StatusCode":500,"Body":{"Results":"Failed to load deployment status for iosManagedAppProtection 3697484d-68b1-4888-b143-5b281cecc156: Forbidden"},"Calls":[]}' }
    ) {
        $script:Fail = $true
        Get-Snapshot -Type $Type | Should -BeExactly $Expected
    }
}
