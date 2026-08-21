BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function Add-CIPPDbItem {
        param(
            $TenantFilter,
            $Type,
            [Alias('Data')]$InputObject,
            [switch]$AddCount,
            [switch]$ClearOnEmpty
        )
    }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyListDefinitions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPIntunePolicyListItem.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheIntunePolicies.ps1')
}

Describe 'Set-CIPPDBCacheIntunePolicies' {
    BeforeEach {
        $script:BulkRequestSets = [System.Collections.Generic.List[object]]::new()
        $script:CacheWrites = [System.Collections.Generic.List[object]]::new()
        $script:Logs = [System.Collections.Generic.List[object]]::new()
        $script:MissingInitialStatuses = @()
        $script:MissingSubresponseStatuses = $false

        Mock Test-CIPPStandardLicense { $true }
        Mock Write-LogMessage {
            $script:Logs.Add([PSCustomObject]@{ Severity = $sev; Message = $message })
        }
        Mock Add-CIPPDbItem {
            $script:CacheWrites.Add([PSCustomObject]@{
                    Type         = $Type
                    Data         = @($InputObject)
                    AddCount     = $AddCount.IsPresent
                    ClearOnEmpty = $ClearOnEmpty.IsPresent
                })
        }
        Mock New-GraphBulkRequest {
            $script:BulkRequestSets.Add(@($Requests))

            if (@($Requests)[0].url -like '*/deviceStatuses*') {
                return @($Requests | ForEach-Object {
                        $Response = [PSCustomObject]@{
                            id     = $_.id
                            body   = [PSCustomObject]@{ value = @() }
                        }
                        if (-not $script:MissingSubresponseStatuses) {
                            $Response | Add-Member -NotePropertyName status -NotePropertyValue 200
                        }
                        $Response
                    })
            }
            if (@($Requests)[0].url -like '*/assignments') {
                return @($Requests | ForEach-Object {
                        $Response = [PSCustomObject]@{
                            id     = $_.id
                            body   = [PSCustomObject]@{ value = @() }
                        }
                        if (-not $script:MissingSubresponseStatuses) {
                            $Response | Add-Member -NotePropertyName status -NotePropertyValue 200
                        }
                        $Response
                    })
            }

            return @($Requests | ForEach-Object {
                    $Value = if ($_.id -eq 'Groups') {
                        @([PSCustomObject]@{ id = 'group-1'; displayName = 'Group One' })
                    } else {
                        @([PSCustomObject]@{ id = "$($_.id)-1"; displayName = "$($_.id) policy" })
                    }
                    $Response = [PSCustomObject]@{
                        id     = $_.id
                        body   = [PSCustomObject]@{ value = $Value }
                    }
                    if ($script:MissingInitialStatuses -notcontains $_.id) {
                        $Response | Add-Member -NotePropertyName status -NotePropertyValue 200
                    }
                    $Response
                })
        }
    }

    It 'caches all live families, the group snapshot, and legacy datasets' {
        Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.onmicrosoft.com'

        $InitialRequests = @($script:BulkRequestSets[0])
        $InitialRequests.id | Should -Contain 'Intents'
        ($InitialRequests | Where-Object id -eq 'MobileAppConfigurations').url |
            Should -Be '/deviceAppManagement/mobileAppConfigurations?$expand=assignments&$filter=microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig%20eq%20true'

        $script:CacheWrites.Type | Should -Contain 'IntunePolicyGroups'
        $script:CacheWrites.Type | Should -Contain 'IntuneDeviceCompliancePolicies'
        $script:CacheWrites.Type | Should -Contain 'IntuneIntents'
        $script:CacheWrites.Type | Should -Contain 'IntuneAppProtectionPolicies'
        $script:CacheWrites.Type | Should -Contain 'IntuneDeviceEnrollmentConfigurations'
        $script:CacheWrites.Type | Should -Contain 'IntuneMobileApps'
        ($script:CacheWrites | Where-Object Type -eq 'IntuneIntents').ClearOnEmpty | Should -BeTrue

        $AllRequestedUrls = @($script:BulkRequestSets | ForEach-Object { $_.url })
        $AllRequestedUrls | Where-Object { $_ -like '/deviceAppManagement/managedAppPolicies/*/assignments' } | Should -BeNullOrEmpty
    }

    It 'preserves a failed family and completes with warning logs' {
        Mock New-GraphBulkRequest {
            if (@($Requests)[0].url -like '*/deviceStatuses*' -or @($Requests)[0].url -like '*/assignments') {
                return @()
            }

            return @($Requests | ForEach-Object {
                    if ($_.id -eq 'Intents') {
                        [PSCustomObject]@{
                            id     = $_.id
                            status = 403
                            body   = [PSCustomObject]@{ error = [PSCustomObject]@{ message = 'Forbidden' } }
                        }
                    } else {
                        [PSCustomObject]@{
                            id     = $_.id
                            status = 200
                            body   = [PSCustomObject]@{ value = @() }
                        }
                    }
                })
        }

        { Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.onmicrosoft.com' } | Should -Not -Throw

        $script:CacheWrites.Type | Should -Not -Contain 'IntuneIntents'
        $script:Logs | Where-Object {
            $_.Severity -eq 'Warning' -and $_.Message -match 'Intents.*HTTP 403'
        } | Should -Not -BeNullOrEmpty
    }

    It 'preserves group and family caches when their batch responses omit status' {
        $script:MissingInitialStatuses = @('Groups', 'Intents')

        { Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.onmicrosoft.com' } | Should -Not -Throw

        $script:CacheWrites.Type | Should -Not -Contain 'IntunePolicyGroups'
        $script:CacheWrites.Type | Should -Not -Contain 'IntuneIntents'
        $script:Logs | Where-Object {
            $_.Severity -eq 'Warning' -and $_.Message -match 'group lookup returned no HTTP status'
        } | Should -Not -BeNullOrEmpty
        $script:Logs | Where-Object {
            $_.Severity -eq 'Warning' -and $_.Message -match 'No HTTP status was returned for Intents'
        } | Should -Not -BeNullOrEmpty
    }

    It 'warns and skips assignment and device status responses without status' {
        $script:MissingSubresponseStatuses = $true

        { Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.onmicrosoft.com' } | Should -Not -Throw

        $script:Logs | Where-Object {
            $_.Severity -eq 'Warning' -and $_.Message -match 'No HTTP status.*fetching assignments'
        } | Should -Not -BeNullOrEmpty
        $script:Logs | Where-Object {
            $_.Severity -eq 'Warning' -and $_.Message -match 'No HTTP status.*fetching device statuses'
        } | Should -Not -BeNullOrEmpty
    }

    It 'still fails when no report family has a valid status' {
        $script:MissingInitialStatuses = @(
            'Groups'
            (Get-CIPPIntunePolicyListDefinitions).Id
            'WindowsAutopilotDeploymentProfiles'
            'DeviceEnrollmentConfigurations'
            'AppleUserInitiatedEnrollmentProfiles'
            'DeviceManagementScripts'
            'MobileApps'
        )

        { Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.onmicrosoft.com' } |
            Should -Throw '*No report-backed Intune policy families were cached successfully*'
        $script:CacheWrites | Should -BeNullOrEmpty
    }

    It 'throws when the initial Graph batch fails completely' {
        Mock New-GraphBulkRequest { throw 'Authentication failed' }

        { Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.onmicrosoft.com' } |
            Should -Throw '*Authentication failed*'
    }
}
