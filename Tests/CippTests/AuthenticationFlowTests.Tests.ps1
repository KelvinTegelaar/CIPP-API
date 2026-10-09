BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $TestsRoot = Join-Path $RepoRoot 'Modules/CIPPTests/Public/Tests'
    . (Join-Path $TestsRoot 'CIS/Identity/Invoke-CippTestCIS_5_2_2_12.ps1')
    . (Join-Path $TestsRoot 'CIS/Identity/Invoke-CippTestCIS_5_2_2_17.ps1')
    . (Join-Path $TestsRoot 'ZTNA/Identity/Invoke-CippTestZTNA21808.ps1')
    . (Join-Path $TestsRoot 'ZTNA/Identity/Invoke-CippTestZTNA21828.ps1')

    function Get-CIPPTestData { param($TenantFilter, $Type) $script:Data[$Type] }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    # Graph returns transferMethods as one comma-separated flag string.
    function New-AuthFlowPolicy($TransferMethods) {
        [pscustomobject]@{
            displayName   = 'Block auth flows'
            state         = 'enabled'
            conditions    = [pscustomobject]@{
                users               = [pscustomobject]@{ includeUsers = @('All') }
                applications        = [pscustomobject]@{ includeApplications = @('All') }
                authenticationFlows = [pscustomobject]@{ transferMethods = $TransferMethods }
            }
            grantControls = [pscustomobject]@{ operator = 'OR'; builtInControls = @('block') }
        }
    }
}

Describe 'Authentication flow CA tests' {
    It '<Test> passes on one policy blocking both transfer methods' -ForEach @(
        @{ Test = 'CIS_5_2_2_12' }
        @{ Test = 'CIS_5_2_2_17' }
        @{ Test = 'ZTNA21808' }
        @{ Test = 'ZTNA21828' }
    ) {
        $script:Data = @{ ConditionalAccessPolicies = @(New-AuthFlowPolicy 'deviceCodeFlow,authenticationTransfer') }

        & "Invoke-CippTest$Test" -Tenant 't.com'

        $script:Result.Status | Should -Be 'Passed'
    }

    It '<Test> fails when only the other transfer method is blocked' -ForEach @(
        @{ Test = 'CIS_5_2_2_12'; Methods = 'authenticationTransfer' }
        @{ Test = 'CIS_5_2_2_17'; Methods = 'deviceCodeFlow' }
        @{ Test = 'ZTNA21808'; Methods = 'authenticationTransfer' }
        @{ Test = 'ZTNA21828'; Methods = 'deviceCodeFlow' }
    ) {
        $script:Data = @{ ConditionalAccessPolicies = @(New-AuthFlowPolicy $Methods) }

        & "Invoke-CippTest$Test" -Tenant 't.com'

        $script:Result.Status | Should -Be 'Failed'
    }
}
