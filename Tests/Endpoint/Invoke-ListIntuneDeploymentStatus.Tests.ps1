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
