# Baseline prepare hook and executor for EnrollmentRestrictionTemplate. Pins the grading
# decisions: a restriction deployed from the template grades clean, a missing Android half
# grades as not deployed, the assignment is graded by Compare-CIPPIntuneAssignments (and left
# out when it cannot be completed or the template does not assign), and the executor patches
# the matched objects in place.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'
    $Core = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public'

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Compare-CIPPIntuneAssignments { param($ExistingAssignments, $ExpectedAssignTo, $ExpectedCustomGroup, $PolicyType, $TenantFilter) }
    function Set-CIPPEnrollmentRestriction { param($TenantFilter, $Settings, $ConfigurationIds, $GroupIds, $PriorityMode, $Headers, $APIName) }

    . (Join-Path $Baselines 'Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $Baselines 'Helpers/Get-CIPPBaselineCacheRows.ps1')
    . (Join-Path $Baselines 'Helpers/Test-CIPPBaselineCacheCollected.ps1')
    foreach ($Name in @('Get-CIPPEnrollmentRestrictionPlatformTypes', 'ConvertTo-CIPPEnrollmentRestrictionSettings', 'New-CIPPEnrollmentRestrictionBody',
            'ConvertFrom-CIPPEnrollmentRestrictionConfiguration', 'Get-CIPPEnrollmentRestrictionProjection', 'Get-CIPPIntuneAssignTarget')) {
        . (Join-Path $Core "$Name.ps1")
    }
    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselineEnrollmentRestrictionTemplateState.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineEnrollmentRestrictionTemplate.ps1')

    $script:Tenant = 'neptunenorth.co.uk'
    $script:GroupId = '3baf8b01-f9c5-4914-81b8-6afddfcb43e7'
    $script:Template = @{
        displayName                = 'Android - Baseline - BYOD - Enrolment Restriction'
        description                = 'BYOD'
        platform                   = 'android'
        priority                   = 1
        osMinimumVersion           = '13.0'
        deviceAdminPlatformBlocked = $true
        AssignTo                   = 'customGroup'
        customGroup                = 'Android - Baseline - BYOD*'
    }
    # The cached rows the executor would leave behind for that template.
    function New-CachedRows {
        param([switch]$WithoutDeviceAdmin)
        $Bodies = New-CIPPEnrollmentRestrictionBody -Settings (ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject ([PSCustomObject]$script:Template))
        foreach ($Type in $Bodies.Keys) {
            if ($WithoutDeviceAdmin -and $Type -eq 'android') { continue }
            $Row = [ordered]@{} + $Bodies[$Type]
            $Row.id = "$Type`_SinglePlatformRestriction"
            $Row.priority = 1
            $Row.assignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $script:GroupId } })
            [PSCustomObject]$Row | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        }
    }
    function Get-Drift {
        param($Prepared)
        @($Prepared.Expected.PSObject.Properties.Name | Where-Object { (ConvertTo-Json $Prepared.Expected.$_ -Compress) -ne (ConvertTo-Json $Prepared.Current.$_ -Compress) })
    }
    $script:Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ enrollmentRestrictionTemplate = [PSCustomObject]@{ label = 'Android BYOD'; value = 'guid-1' } } }
}

Describe 'Get-CIPPBaselineEnrollmentRestrictionTemplateState' {
    BeforeEach {
        $script:Rows = @(New-CachedRows)
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'X-Count'; DataCount = 1 } }
        Mock New-CIPPDbRequest { $script:Rows }
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ JSON = ($script:Template | ConvertTo-Json) } }
        Mock Compare-CIPPIntuneAssignments { [PSCustomObject]@{ Matched = $true; Unknown = $false } }
    }

    It 'grades a restriction deployed from the template as compliant, comparing its assignment the Intune way' {
        $Prepared = Get-CIPPBaselineEnrollmentRestrictionTemplateState -Item $script:Item -TenantFilter $script:Tenant
        Get-Drift $Prepared | Should -BeNullOrEmpty
        $Prepared.Expected.isAssigned | Should -BeTrue
        Should -Invoke Compare-CIPPIntuneAssignments -Times 1 -Exactly -ParameterFilter {
            $PolicyType -eq 'deviceEnrollmentConfigurations' -and $ExpectedAssignTo -eq 'customGroup' -and
            $ExpectedCustomGroup -eq 'Android - Baseline - BYOD*' -and @($ExistingAssignments).target.groupId -contains $script:GroupId
        }
    }

    It 'grades a missing device administrator half as not deployed' {
        $script:Rows = @(New-CachedRows -WithoutDeviceAdmin)
        $Prepared = Get-CIPPBaselineEnrollmentRestrictionTemplateState -Item $script:Item -TenantFilter $script:Tenant
        Get-Drift $Prepared | Should -Contain 'deployed'
    }

    It 'grades a mismatched assignment as drift' {
        Mock Compare-CIPPIntuneAssignments { [PSCustomObject]@{ Matched = $false; Unknown = $false } }
        $Prepared = Get-CIPPBaselineEnrollmentRestrictionTemplateState -Item $script:Item -TenantFilter $script:Tenant
        Get-Drift $Prepared | Should -Be @('isAssigned')
    }

    It 'leaves the assignment out when the comparison could not be completed or the template does not assign' {
        Mock Compare-CIPPIntuneAssignments { [PSCustomObject]@{ Matched = $null; Unknown = $true } }
        $Prepared = Get-CIPPBaselineEnrollmentRestrictionTemplateState -Item $script:Item -TenantFilter $script:Tenant
        $Prepared.Expected.PSObject.Properties.Name | Should -Not -Contain 'isAssigned'

        $script:Template.AssignTo = 'On'
        try {
            $Prepared = Get-CIPPBaselineEnrollmentRestrictionTemplateState -Item $script:Item -TenantFilter $script:Tenant
            $Prepared.Expected.PSObject.Properties.Name | Should -Not -Contain 'isAssigned'
        } finally {
            $script:Template.AssignTo = 'customGroup'
        }
    }

    It 'the executor patches the matched objects with the template' {
        Mock Set-CIPPEnrollmentRestriction { }
        $Prepared = Get-CIPPBaselineEnrollmentRestrictionTemplateState -Item $script:Item -TenantFilter $script:Tenant
        Invoke-CIPPBaselineEnrollmentRestrictionTemplate -Remediate ([PSCustomObject]@{ executor = 'EnrollmentRestrictionTemplate' }) -TenantFilter $script:Tenant -Current $Prepared.Current
        Should -Invoke Set-CIPPEnrollmentRestriction -Times 1 -Exactly -ParameterFilter {
            $ConfigurationIds.Count -eq 2 -and $Settings.platform -eq 'android' -and $Settings.priority -eq 1
        }
    }
}
