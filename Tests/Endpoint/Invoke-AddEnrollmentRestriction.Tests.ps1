# Pester tests for the enrollment restriction endpoints.
#
# Invoke-AddEnrollmentRestriction: the create/edit split (tenant fan-out vs one tenant with the
# restriction's object ids and a forced priority), group ids only used for a single tenant,
# deploying a saved template by id from the deploy drawer, and the request checks.
# Invoke-AddEnrollmentRestrictionTemplate: a row from ListEnrollmentRestrictions saves as a
# normalised template, and incomplete templates are refused.
# Invoke-ExecRemoveEnrollmentRestriction: the default restriction is never deleted.
# Invoke-ListEnrollmentRestrictions: the default restriction is listed last on each platform,
# and the platform filter limits the rows to one tab's platforms.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    foreach ($Name in @('Invoke-AddEnrollmentRestriction', 'Invoke-AddEnrollmentRestrictionTemplate', 'Invoke-ExecRemoveEnrollmentRestriction', 'Invoke-ListEnrollmentRestrictions',
            'Get-CIPPEnrollmentRestrictionPlatformTypes', 'ConvertTo-CIPPEnrollmentRestrictionSettings', 'New-CIPPEnrollmentRestrictionBody', 'Get-CIPPIntuneAssignTarget',
            'ConvertFrom-CIPPEnrollmentRestrictionConfiguration')) {
        $Path = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter "$Name.ps1" -File | Select-Object -First 1 -ExpandProperty FullName
        if (-not $Path) { throw "Could not locate $Name.ps1 under Modules/" }
        . $Path
    }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Set-CIPPEnrollmentRestriction { param($TenantFilter, $Settings, $ConfigurationIds, $GroupIds, $PriorityMode, [switch]$CreateGroups, $Headers, $APIName) }
    function Test-CippAccess { param($Request, [switch]$TenantList) 'AllTenants' }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = "$Exception" } }
    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function ConvertTo-CIPPIntunePolicyListItem { param($Policy, $URLName, $DefaultPolicyTypeName, $GroupLookup) [PSCustomObject]@{ PolicyAssignment = 'Assigned' } }

    function New-Request {
        param($Body, $Endpoint = 'AddEnrollmentRestriction')
        [PSCustomObject]@{ Params = @{ CIPPEndpoint = $Endpoint }; Headers = @{}; Body = [PSCustomObject]$Body }
    }
    # The form with some fields overridden or added.
    function With {
        param([hashtable]$Extra)
        $Merged = $script:Form.Clone()
        foreach ($Key in $Extra.Keys) { $Merged[$Key] = $Extra[$Key] }
        $Merged
    }
    $script:Form = @{
        displayName                = 'Android BYOD'
        platform                   = 'android'
        osMinimumVersion           = '13.0'
        deviceAdminPlatformBlocked = $true
        AssignTo                   = 'customGroup'
        customGroup                = 'BYOD*'
    }
}

Describe 'Invoke-AddEnrollmentRestriction' {
    BeforeEach {
        Mock Set-CIPPEnrollmentRestriction { "done $TenantFilter" }
    }

    It 'creates in every selected tenant and ignores picked group ids across tenants' {
        $Body = With @{ selectedTenants = @(@{ value = 'tenant-a' }, @{ value = 'tenant-b' }); GroupIds = @('g1') }
        $Response = Invoke-AddEnrollmentRestriction -Request (New-Request $Body) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Set-CIPPEnrollmentRestriction -Times 2 -Exactly -ParameterFilter {
            $Settings.platform -eq 'android' -and $Settings.customGroup -eq 'BYOD*' -and @($GroupIds).Count -eq 0 -and -not $ConfigurationIds
        }
    }

    It 'edits one restriction by its object ids, with picked groups and a forced priority' {
        $Body = With @{ tenantFilter = 'tenant-a'; ConfigurationIds = @('a_SinglePlatformRestriction', 'b_SinglePlatformRestriction'); GroupIds = @('g1'); priority = 2 }
        $null = Invoke-AddEnrollmentRestriction -Request (New-Request $Body) -TriggerMetadata $null

        Should -Invoke Set-CIPPEnrollmentRestriction -Times 1 -Exactly -ParameterFilter {
            $TenantFilter -eq 'tenant-a' -and $ConfigurationIds.Count -eq 2 -and $GroupIds -contains 'g1' -and $PriorityMode -eq 'Always' -and $Settings.priority -eq 2
        }
    }

    It 'deploys a saved template from the deploy drawer by its id' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ JSON = (@{ displayName = 'iOS BYOD'; platform = 'ios'; personalDeviceEnrollmentBlocked = $true; AssignTo = 'allLicensedUsers' } | ConvertTo-Json) } }
        $Body = @{ selectedTenants = @(@{ value = 'tenant-a'; label = 'Tenant A' }); TemplateList = @{ value = 'guid-1'; label = 'iOS BYOD (iOS/iPadOS)' } }
        $null = Invoke-AddEnrollmentRestriction -Request (New-Request $Body) -TriggerMetadata $null

        Should -Invoke Set-CIPPEnrollmentRestriction -Times 1 -Exactly -ParameterFilter {
            $TenantFilter -eq 'tenant-a' -and $Settings.displayName -eq 'iOS BYOD' -and $Settings.personalDeviceEnrollmentBlocked -and $Settings.AssignTo -eq 'allLicensedUsers'
        }
    }

    It 'handles groups on deploy as conditional access templates do' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ JSON = (@{ displayName = 'Android BYOD'; platform = 'android'; AssignTo = 'customGroup'; customGroup = 'BYOD*' } | ConvertTo-Json) } }
        $Deploy = { param($Mode) @{ selectedTenants = @(@{ value = 'tenant-a' }); TemplateList = @{ value = 'guid-1' }; replacename = $Mode } }

        $null = Invoke-AddEnrollmentRestriction -Request (New-Request (& $Deploy 'displayName')) -TriggerMetadata $null
        Should -Invoke Set-CIPPEnrollmentRestriction -Times 1 -Exactly -ParameterFilter { $Settings.AssignTo -eq 'customGroup' -and $Settings.customGroup -eq 'BYOD*' }

        $null = Invoke-AddEnrollmentRestriction -Request (New-Request (& $Deploy 'leave')) -TriggerMetadata $null
        Should -Invoke Set-CIPPEnrollmentRestriction -Times 1 -Exactly -ParameterFilter { $Settings.AssignTo -eq 'On' -and -not $Settings.customGroup }

        $null = Invoke-AddEnrollmentRestriction -Request (New-Request (& $Deploy 'AllUsers')) -TriggerMetadata $null
        Should -Invoke Set-CIPPEnrollmentRestriction -Times 1 -Exactly -ParameterFilter { $Settings.AssignTo -eq 'allLicensedUsers' -and -not $Settings.customGroup }
        Should -Invoke Set-CIPPEnrollmentRestriction -Times 0 -ParameterFilter { $CreateGroups }

        $Body = & $Deploy 'displayName'
        $Body.CreateGroups = $true
        $null = Invoke-AddEnrollmentRestriction -Request (New-Request $Body) -TriggerMetadata $null
        Should -Invoke Set-CIPPEnrollmentRestriction -Times 1 -Exactly -ParameterFilter { $CreateGroups }
    }

    It 'rejects a missing platform, a missing name and custom groups with no groups' {
        foreach ($Bad in @(
                (With @{ selectedTenants = @('tenant-a'); platform = '' }),
                (With @{ selectedTenants = @('tenant-a'); displayName = ' ' }),
                (With @{ selectedTenants = @('tenant-a'); customGroup = '' }))) {
            (Invoke-AddEnrollmentRestriction -Request (New-Request $Bad) -TriggerMetadata $null).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        }
        Should -Invoke Set-CIPPEnrollmentRestriction -Times 0
    }

    It 'refuses to edit the default restriction' {
        $Body = With @{ tenantFilter = 'tenant-a'; ConfigurationIds = @('acc_DefaultPlatformRestrictions') }
        $Response = Invoke-AddEnrollmentRestriction -Request (New-Request $Body) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike '*DefaultPlatformRestrictions standard*'
        Should -Invoke Set-CIPPEnrollmentRestriction -Times 0
    }

    It 'reports a failure in one tenant as partial success' {
        Mock Set-CIPPEnrollmentRestriction -ParameterFilter { $TenantFilter -eq 'tenant-a' } -MockWith { throw 'boom' }
        $Response = Invoke-AddEnrollmentRestriction -Request (New-Request (With @{ selectedTenants = @('tenant-a', 'tenant-b') })) -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::MultiStatus)
    }
}

Describe 'Invoke-AddEnrollmentRestrictionTemplate' {
    BeforeEach {
        $script:Saved = $null
        Mock Add-CIPPAzDataTableEntity { $script:Saved = $Entity }
    }

    It 'saves a ListEnrollmentRestrictions row as a normalised template' {
        $Row = With @{ customGroup = @('BYOD Users'); ids = @('x_SinglePlatformRestriction'); priority = 1; platformLabel = 'Android' }
        $Response = Invoke-AddEnrollmentRestrictionTemplate -Request (New-Request $Row 'AddEnrollmentRestrictionTemplate') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:Saved.PartitionKey | Should -Be 'EnrollmentRestrictionTemplate'
        $Template = $script:Saved.JSON | ConvertFrom-Json
        $Template.customGroup | Should -Be 'BYOD Users'
        $Template.osMinimumVersion | Should -Be '13.0'
        $Template.PSObject.Properties.Name | Should -Not -Contain 'ids'
        $Template.GUID | Should -Be $script:Saved.RowKey
    }

    It 'keeps the GUID when updating and refuses custom groups without names' {
        $null = Invoke-AddEnrollmentRestrictionTemplate -Request (New-Request (With @{ GUID = 'keep-me' }) 'AddEnrollmentRestrictionTemplate') -TriggerMetadata $null
        $script:Saved.RowKey | Should -Be 'keep-me'

        $script:Saved = $null
        $Response = Invoke-AddEnrollmentRestrictionTemplate -Request (New-Request (With @{ customGroup = '' }) 'AddEnrollmentRestrictionTemplate') -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $script:Saved | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-ExecRemoveEnrollmentRestriction' {
    It 'deletes every object behind the restriction and refuses the default' {
        Mock New-GraphPOSTRequest { }
        $Response = Invoke-ExecRemoveEnrollmentRestriction -Request (New-Request @{ tenantFilter = 't'; ids = @('a_SinglePlatformRestriction', 'b_SinglePlatformRestriction') } 'ExecRemoveEnrollmentRestriction') -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphPOSTRequest -Times 2 -Exactly -ParameterFilter { $type -eq 'DELETE' }

        $Response = Invoke-ExecRemoveEnrollmentRestriction -Request (New-Request @{ tenantFilter = 't'; ids = @('acc_DefaultPlatformRestrictions') } 'ExecRemoveEnrollmentRestriction') -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        Should -Invoke New-GraphPOSTRequest -Times 2 -Exactly
    }
}

Describe 'Invoke-ListEnrollmentRestrictions' {
    BeforeEach {
        $Allowed = [PSCustomObject]@{ platformBlocked = $false; personalDeviceEnrollmentBlocked = $false; osMinimumVersion = $null; osMaximumVersion = $null; blockedManufacturers = @() }
        $script:Configurations = @(
            [PSCustomObject]@{
                '@odata.type' = '#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration'; id = 'acc_DefaultPlatformRestrictions'; displayName = 'All users and all devices'; priority = 0
                androidForWorkRestriction = $Allowed; androidRestriction = $Allowed; iosRestriction = $Allowed; macOSRestriction = $Allowed; windowsRestriction = $Allowed; tvosRestriction = $Allowed; visionOSRestriction = $Allowed
            }
            [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.deviceEnrollmentPlatformRestrictionConfiguration'; id = 'i1_SinglePlatformRestriction'; displayName = 'iOS BYOD'; priority = 1; platformType = 'ios'; platformRestriction = $Allowed }
            [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.deviceEnrollmentPlatformRestrictionConfiguration'; id = 'w1_SinglePlatformRestriction'; displayName = 'Windows Corporate'; priority = 1; platformType = 'windows'; platformRestriction = $Allowed }
        )
        Mock New-GraphBulkRequest {
            @(
                [PSCustomObject]@{ id = 'Configurations'; status = 200; body = [PSCustomObject]@{ value = $script:Configurations } }
                [PSCustomObject]@{ id = 'Groups'; status = 200; body = [PSCustomObject]@{ value = @() } }
            )
        }
    }

    It 'lists the Apple tab with the default last on every Apple platform, read-only' {
        $Request = [PSCustomObject]@{ Params = @{ CIPPEndpoint = 'ListEnrollmentRestrictions' }; Headers = @{}; Query = @{ tenantFilter = 't'; platform = 'ios,macOS,tvOS,visionOS' } }
        $Rows = @((Invoke-ListEnrollmentRestrictions -Request $Request -TriggerMetadata $null).Body.Results)

        @($Rows | ForEach-Object { "$($_.platform)|$($_.priority)" }) | Should -Be @('ios|1', 'ios|Default', 'macOS|Default', 'tvOS|Default', 'visionOS|Default')
        $Default = $Rows | Where-Object { $_.platform -eq 'tvOS' }
        $Default.isDefault | Should -BeTrue
        $Default.platformLabel | Should -Be 'tvOS'
        $Default.PolicyAssignment | Should -Be 'All users and all devices'
        @($Rows.id | Select-Object -Unique).Count | Should -Be $Rows.Count
    }

    It 'lists every platform when no platform is given' {
        $Request = [PSCustomObject]@{ Params = @{ CIPPEndpoint = 'ListEnrollmentRestrictions' }; Headers = @{}; Query = @{ tenantFilter = 't' } }
        $Rows = @((Invoke-ListEnrollmentRestrictions -Request $Request -TriggerMetadata $null).Body.Results)

        @($Rows | Where-Object isDefault).Count | Should -Be 6
        @($Rows | Where-Object { -not $_.isDefault }).Count | Should -Be 2
    }
}
