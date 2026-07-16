# Pester tests for Resolve-NinjaOneCveScanGroup
# Verifies the CVE sync scan-group lookup/auto-create behavior (GH issue #6349):
# - reuses an existing scan group when the name matches
# - creates a new scan group via the NinjaOne API when none exists
# - logs and returns $null (without throwing) when creation also fails, so the
#   overall tenant sync is not interrupted by CVE sync failures

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CippExtensions/Private/NinjaOne/Resolve-NinjaOneCveScanGroup.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }

    . $FunctionPath
}

Describe 'Resolve-NinjaOneCveScanGroup' {
    BeforeEach {
        $script:Configuration = [pscustomobject]@{
            Instance              = 'contoso.rmmservice.com'
            CveSyncDeviceIdHeader = 'deviceName'
            CveSyncCveIdHeader    = 'cveId'
        }
        $script:Token = [pscustomobject]@{ access_token = 'fake-token-value' }
        $script:TenantFilter = 'contoso.onmicrosoft.com'
        $script:ScanGroupName = 'CIPP-contoso.onmicrosoft.com'
        $script:NinjaBaseUrl = 'https://contoso.rmmservice.com/api/v2'

        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'returns the existing scan group without attempting to create one' {
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Get' } -MockWith {
            @(
                [pscustomobject]@{ id = 'existing-id'; groupName = $script:ScanGroupName; deviceIdHeader = 'deviceName'; cveIdHeader = 'cveId' }
            )
        }
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Post' } -MockWith { throw 'Should not be called' }

        $Result = Resolve-NinjaOneCveScanGroup -Configuration $script:Configuration -TenantFilter $script:TenantFilter -ScanGroupName $script:ScanGroupName -NinjaBaseUrl $script:NinjaBaseUrl -Token $script:Token

        $Result.id | Should -Be 'existing-id'
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Method -eq 'Get' } -Times 1 -Exactly
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Method -eq 'Post' } -Times 0 -Exactly
    }

    It 'creates a new scan group when no matching group exists' {
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Get' } -MockWith {
            @(
                [pscustomobject]@{ id = 'other-id'; groupName = 'SomeOtherGroup'; deviceIdHeader = 'deviceName'; cveIdHeader = 'cveId' }
            )
        }
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Post' } -MockWith {
            [pscustomobject]@{ id = 'new-id'; groupName = $script:ScanGroupName; deviceIdHeader = 'deviceName'; cveIdHeader = 'cveId' }
        }

        $Result = Resolve-NinjaOneCveScanGroup -Configuration $script:Configuration -TenantFilter $script:TenantFilter -ScanGroupName $script:ScanGroupName -NinjaBaseUrl $script:NinjaBaseUrl -Token $script:Token

        $Result.id | Should -Be 'new-id'
        $Result.groupName | Should -Be $script:ScanGroupName
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Method -eq 'Get' } -Times 1 -Exactly
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Method -eq 'Post' } -Times 1 -Exactly
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Info' -and $message -like '*created scan group*' } -Times 1 -Exactly
    }

    It 'sends the configured header names and a bearer token when creating a scan group' {
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Get' } -MockWith { @() }
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Post' } -MockWith {
            [pscustomobject]@{ id = 'new-id'; groupName = $script:ScanGroupName; deviceIdHeader = 'deviceName'; cveIdHeader = 'cveId' }
        }

        Resolve-NinjaOneCveScanGroup -Configuration $script:Configuration -TenantFilter $script:TenantFilter -ScanGroupName $script:ScanGroupName -NinjaBaseUrl $script:NinjaBaseUrl -Token $script:Token | Out-Null

        Should -Invoke Invoke-RestMethod -ParameterFilter {
            $Method -eq 'Post' -and
            $Uri -eq "$($script:NinjaBaseUrl)/vulnerability/scan-groups" -and
            $Headers.Authorization -eq "Bearer $($script:Token.access_token)" -and
            $Headers.'Content-Type' -eq 'application/json' -and
            ($Body | ConvertFrom-Json).groupName -eq $script:ScanGroupName -and
            ($Body | ConvertFrom-Json).deviceIdHeader -eq 'deviceName' -and
            ($Body | ConvertFrom-Json).cveIdHeader -eq 'cveId'
        } -Times 1 -Exactly
    }

    It 'returns $null and logs an error when the scan group cannot be found or created' {
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Get' } -MockWith { @() }
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Post' } -MockWith { throw 'NinjaOne API unavailable' }

        $Result = $null
        { $Result = Resolve-NinjaOneCveScanGroup -Configuration $script:Configuration -TenantFilter $script:TenantFilter -ScanGroupName $script:ScanGroupName -NinjaBaseUrl $script:NinjaBaseUrl -Token $script:Token } | Should -Not -Throw

        $Result | Should -BeNullOrEmpty
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Error' -and $message -like '*could not be created*' } -Times 1 -Exactly
    }

    It 'returns $null and logs an error without throwing when the initial lookup GET fails' {
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Get' } -MockWith { throw 'NinjaOne API unreachable' }
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Post' } -MockWith { throw 'Should not be called' }

        $Result = $null
        { $Result = Resolve-NinjaOneCveScanGroup -Configuration $script:Configuration -TenantFilter $script:TenantFilter -ScanGroupName $script:ScanGroupName -NinjaBaseUrl $script:NinjaBaseUrl -Token $script:Token } | Should -Not -Throw

        $Result | Should -BeNullOrEmpty
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Method -eq 'Post' } -Times 0 -Exactly
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Error' -and $message -like '*could not look up scan group*' } -Times 1 -Exactly
    }

    It 'returns a single scan group object when multiple groups share the same name' {
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Get' } -MockWith {
            @(
                [pscustomobject]@{ id = 'dup-1'; groupName = $script:ScanGroupName; deviceIdHeader = 'deviceName'; cveIdHeader = 'cveId' }
                [pscustomobject]@{ id = 'dup-2'; groupName = $script:ScanGroupName; deviceIdHeader = 'deviceName'; cveIdHeader = 'cveId' }
            )
        }
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Post' } -MockWith { throw 'Should not be called' }

        $Result = Resolve-NinjaOneCveScanGroup -Configuration $script:Configuration -TenantFilter $script:TenantFilter -ScanGroupName $script:ScanGroupName -NinjaBaseUrl $script:NinjaBaseUrl -Token $script:Token

        $Result.GetType().IsArray | Should -Be $false
        $Result.id | Should -Be 'dup-1'
    }

    It 'falls back to default header names when CveSyncDeviceIdHeader/CveSyncCveIdHeader are not configured' {
        $script:Configuration = [pscustomobject]@{ Instance = 'contoso.rmmservice.com' }
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Get' } -MockWith { @() }
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Method -eq 'Post' } -MockWith {
            [pscustomobject]@{ id = 'new-id'; groupName = $script:ScanGroupName; deviceIdHeader = 'deviceName'; cveIdHeader = 'cveId' }
        }

        Resolve-NinjaOneCveScanGroup -Configuration $script:Configuration -TenantFilter $script:TenantFilter -ScanGroupName $script:ScanGroupName -NinjaBaseUrl $script:NinjaBaseUrl -Token $script:Token | Out-Null

        Should -Invoke Invoke-RestMethod -ParameterFilter {
            $Method -eq 'Post' -and
            ($Body | ConvertFrom-Json).deviceIdHeader -eq 'deviceName' -and
            ($Body | ConvertFrom-Json).cveIdHeader -eq 'cveId'
        } -Times 1 -Exactly
    }
}
