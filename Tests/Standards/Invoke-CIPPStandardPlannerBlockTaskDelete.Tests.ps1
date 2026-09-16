# Pester tests for Invoke-CIPPStandardPlannerBlockTaskDelete

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardPlannerBlockTaskDelete.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardPlannerBlockTaskDelete.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $RequiredCapabilities, $Preset, [switch]$SkipLog) }
    function Test-CIPPRerun { [CmdletBinding()] param($Tenant, $TenantFilter, $Type, $API, $Settings, $Headers, [switch]$Clear, [switch]$ClearAll, [int64]$Interval, [int64]$BaseTime) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $scope, $AsApp, $NoAuthCheck, $skipTokenCache) }
    function New-GraphPOSTRequest { [CmdletBinding()] param($uri, $tenantid, $body, $type, $scope, $AsApp, $NoAuthCheck, $skipTokenCache, $AddedHeaders, $contentType) }
    function New-GraphBulkRequest { [CmdletBinding()] param($tenantid, $Requests, $Version, $AsApp, $NoAuthCheck) }
    function New-CIPPDbRequest { [CmdletBinding()] param($TenantFilter, $Type) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter, $LicenseAvailable) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:PlannerPlan = [pscustomobject]@{ servicePlanId = 'b737dad2-2f6c-4c65-90e3-ca563267e8b9'; capabilityStatus = 'Enabled' }
    $script:Users = @(
        [pscustomobject]@{ id = '11111111-1111-1111-1111-111111111111'; userPrincipalName = 'ann@contoso.com'; displayName = 'Ann'; userType = 'Member'; accountEnabled = $true; assignedPlans = @($script:PlannerPlan) }
        [pscustomobject]@{ id = '22222222-2222-2222-2222-222222222222'; userPrincipalName = 'ben@contoso.com'; displayName = 'Ben'; userType = 'Member'; accountEnabled = $true; assignedPlans = @($script:PlannerPlan) }
        [pscustomobject]@{ id = '55555555-5555-5555-5555-555555555555'; userPrincipalName = 'disabled@contoso.com'; displayName = 'Disabled'; userType = 'Member'; accountEnabled = $false; assignedPlans = @($script:PlannerPlan) }
        [pscustomobject]@{ id = '44444444-4444-4444-4444-444444444444'; userPrincipalName = 'carl@contoso.com'; displayName = 'Carl'; userType = 'Member'; accountEnabled = $true; assignedPlans = @() }
        [pscustomobject]@{ id = '33333333-3333-3333-3333-333333333333'; userPrincipalName = 'guest@external.com'; displayName = 'Guest'; userType = 'Guest'; accountEnabled = $true; assignedPlans = @($script:PlannerPlan) }
    )
}

Describe 'Invoke-CIPPStandardPlannerBlockTaskDelete' {
    BeforeEach {
        $script:logs = [System.Collections.Generic.List[object]]::new()
        $script:getUris = [System.Collections.Generic.List[string]]::new()
        $script:putCalls = [System.Collections.Generic.List[object]]::new()
        $script:alerts = [System.Collections.Generic.List[object]]::new()
        $script:policyByUpn = @{
            'ann@contoso.com' = [pscustomobject]@{ blockDeleteTasksNotCreatedBySelf = $false }
            'ben@contoso.com' = [pscustomobject]@{ blockDeleteTasksNotCreatedBySelf = $true }
        }

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Test-CIPPRerun -MockWith { $false }
        Mock -CommandName New-CIPPDbRequest -MockWith { $script:Users }
        Mock -CommandName Write-StandardsAlert -MockWith {
            param($message, $object)
            $script:alerts.Add(@{ Message = $message; Object = $object })
        }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith { }
        Mock -CommandName Add-CIPPBPAField -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith {
            param($API, $tenant, $message, $sev, $LogData)
            $script:logs.Add(@{ Message = $message; Sev = $sev; LogData = $LogData })
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            param($uri, $tenantid, $scope)
            if ($uri -like 'https://graph.microsoft.com/*') {
                return @([pscustomobject]@{ id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; displayName = 'Dept Ticketing' })
            }
            $script:getUris.Add($uri)
            if ($uri -match "UserPolicy\('([^']+)'\)") {
                $Upn = $Matches[1]
                if ($script:policyByUpn.ContainsKey($Upn)) {
                    return $script:policyByUpn[$Upn]
                }
                throw '403 Forbidden: Access is denied'
            }
            throw "Unexpected GET $uri"
        }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            param($tenantid, $Requests)
            foreach ($Req in @($Requests)) {
                [pscustomobject]@{
                    id     = $Req.id
                    status = 200
                    body   = @{
                        value = @(
                            [pscustomobject]@{ id = '11111111-1111-1111-1111-111111111111' }
                        )
                    }
                }
            }
        }
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            param($uri, $tenantid, $body, $type, $scope, $AsApp)
            $script:putCalls.Add(@{
                    Uri   = $uri
                    Body  = $body
                    Type  = $type
                    Scope = $scope
                    AsApp = $AsApp
                })
            return $null
        }
    }

    It 'returns early when the license check fails' {
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $false }

        $Result = Invoke-CIPPStandardPlannerBlockTaskDelete -Tenant $script:Tenant -Settings @{ remediate = $true }

        $Result | Should -Be $true
        Should -Invoke -CommandName New-CIPPDbRequest -Times 0 -Exactly
        Should -Invoke -CommandName New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'aborts when a configured include group does not exist' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            param($uri)
            if ($uri -like 'https://graph.microsoft.com/*') { return @() }
            throw "Unexpected GET $uri"
        }

        Invoke-CIPPStandardPlannerBlockTaskDelete -Tenant $script:Tenant -Settings @{
            remediate     = $true
            includeGroups = @('Missing Group')
        }

        $Errors = @($script:logs | Where-Object { $_.Sev -eq 'Error' -and $_.Message -match 'partial scope|does not exist' })
        $Errors.Count | Should -BeGreaterThan 0
        Should -Invoke -CommandName New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'remediates with PUT for Planner-licensed members only and skips UserPolicy GET' {
        Invoke-CIPPStandardPlannerBlockTaskDelete -Tenant $script:Tenant -Settings @{ remediate = $true }

        # Guest, unlicensed Carl, and disabled account excluded; Ann + Ben get idempotent PUT
        $script:putCalls.Count | Should -Be 2
        ($script:putCalls.Uri | ForEach-Object { if ($_ -match "UserPolicy\('([^']+)'\)") { $Matches[1] } } | Sort-Object) |
            Should -Be @('ann@contoso.com', 'ben@contoso.com')
        foreach ($Call in $script:putCalls) {
            $Call.Type | Should -Be 'PUT'
            $Call.Scope | Should -Be 'https://tasks.office.com/.default'
            $Call.AsApp | Should -Be $true
            ($Call.Body | ConvertFrom-Json).blockDeleteTasksNotCreatedBySelf | Should -BeTrue
        }
        @($script:getUris | Where-Object { $_ -match 'UserPolicy' }).Count | Should -Be 0
        @($script:logs | Where-Object { $_.Message -match "Blocked Planner task delete" }).Count | Should -Be 0
        @($script:logs | Where-Object { $_.Message -match 'successfully updated 2 users' }).Count | Should -Be 1
    }

    It 'limits remediation to include-group members without UserPolicy GET' {
        Invoke-CIPPStandardPlannerBlockTaskDelete -Tenant $script:Tenant -Settings @{
            remediate     = $true
            includeGroups = @('Dept Ticketing')
        }

        $script:putCalls.Count | Should -Be 1
        $script:putCalls[0].Uri | Should -Match "UserPolicy\('ann@contoso.com'\)"
        @($script:getUris | Where-Object { $_ -match 'UserPolicy' }).Count | Should -Be 0
    }

    It 'GETs UserPolicy for alert and treats 403 as non-compliant' {
        $script:policyByUpn = @{
            'ben@contoso.com' = [pscustomobject]@{ blockDeleteTasksNotCreatedBySelf = $true }
        }

        Invoke-CIPPStandardPlannerBlockTaskDelete -Tenant $script:Tenant -Settings @{ alert = $true }

        @($script:getUris | Where-Object { $_ -match 'UserPolicy' }).Count | Should -Be 2
        Should -Invoke -CommandName New-GraphPOSTRequest -Times 0 -Exactly
        $script:alerts.Count | Should -Be 1
        @($script:alerts[0].Object.userPrincipalName) | Should -Contain 'ann@contoso.com'
        @($script:alerts[0].Object.userPrincipalName) | Should -Not -Contain 'ben@contoso.com'
        @($script:alerts[0].Object.userPrincipalName) | Should -Not -Contain 'carl@contoso.com'
        @($script:logs | Where-Object { $_.Message -match '1 in-scope account\(s\) are missing' }).Count | Should -Be 1
        @($script:logs | Where-Object { $_.Message -match 'ann@contoso.com' }).Count | Should -Be 0
    }

    It 'skips remediate within the 24h guard but still alerts' {
        Mock -CommandName Test-CIPPRerun -MockWith { $true }
        $script:policyByUpn = @{
            'ann@contoso.com' = [pscustomobject]@{ blockDeleteTasksNotCreatedBySelf = $false }
            'ben@contoso.com' = [pscustomobject]@{ blockDeleteTasksNotCreatedBySelf = $true }
        }

        Invoke-CIPPStandardPlannerBlockTaskDelete -Tenant $script:Tenant -Settings @{
            remediate = $true
            alert     = $true
        }

        Should -Invoke -CommandName New-GraphPOSTRequest -Times 0 -Exactly
        @($script:getUris | Where-Object { $_ -match 'UserPolicy' }).Count | Should -Be 2
        $script:alerts.Count | Should -Be 1
        $Skipped = @($script:logs | Where-Object { $_.Message -match '24h' })
        $Skipped.Count | Should -BeGreaterThan 0
    }

    It 'aggregates remediate failures into one error log' {
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            param($uri)
            if ($uri -match 'ann@') { throw '429 Too Many Requests' }
            $script:putCalls.Add(@{ Uri = $uri })
            return $null
        }

        Invoke-CIPPStandardPlannerBlockTaskDelete -Tenant $script:Tenant -Settings @{ remediate = $true }

        $Errors = @($script:logs | Where-Object { $_.Sev -eq 'Error' -and $_.Message -match 'one or more failed' })
        $Errors.Count | Should -Be 1
        $Errors[0].Message | Should -Match 'updated 1 of 2'
        $Errors[0].Message | Should -Match '429'
        @($script:logs | Where-Object { $_.Message -match 'Failed to set Planner UserPolicy for' }).Count | Should -Be 0
    }
}
