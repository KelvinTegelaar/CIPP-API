# ActiveSyncDefaultAccessLevel: a declarative definition over the ExoActiveSyncOrganizationSettings cache.
# The collector caches the singleton; the engine's own render feeds the generic ExoRequest executor.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox, [switch]$Compliance) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }

    . (Join-Path $script:RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheExoActiveSyncOrganizationSettings.ps1')
    . (Join-Path $Baselines 'Helpers/Expand-CIPPBaselineToken.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineExoRequest.ps1')

    # The engine's own $Render, lifted out of Invoke-CIPPBaselineStandard so the test runs it verbatim.
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Baselines 'Helpers/Invoke-CIPPBaselineStandard.ps1'), [ref]$null, [ref]$null)
    $Assign = $Ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$Render' }, $true)
    $script:Render = [scriptblock]::Create($Assign.Right.Expression.Extent.Text.Trim('{', '}'))
    function Invoke-Render { param($Definition, $Template, $Variables) $TenantFilter = 'contoso.onmicrosoft.com'; & $script:Render $Template $Variables }

    $script:Definition = Get-Content -Raw (Join-Path $script:RepoRoot 'Config/BaselineStandards/Exchange Standards/ActiveSyncDefaultAccessLevel.json') | ConvertFrom-Json
}

Describe 'Set-CIPPDBCacheExoActiveSyncOrganizationSettings' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
    }

    It 'caches the settings object as one counted row' {
        Mock New-ExoRequest { [pscustomobject]@{ Identity = 'Mobile Mailbox Settings'; DefaultAccessLevel = 'Allow' } }
        Set-CIPPDBCacheExoActiveSyncOrganizationSettings -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Get-ActiveSyncOrganizationSettings' }
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'ExoActiveSyncOrganizationSettings' -and $AddCount -and $ClearOnEmpty -and @($Data).Count -eq 1 -and $Data[0].DefaultAccessLevel -eq 'Allow'
        }
    }

    It 'writes nothing and logs when the read fails, so the last good row stays' {
        Mock New-ExoRequest { throw 'Exchange said no' }
        Set-CIPPDBCacheExoActiveSyncOrganizationSettings -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' }
    }
}

Describe 'ActiveSyncDefaultAccessLevel definition' {
    It 'needs the operator to pick a level and offers only the three Exchange values' {
        $Variable = $script:Definition.variables.accessLevel
        $Variable.required | Should -BeTrue
        $Variable.PSObject.Properties.Name | Should -Not -Contain 'default'
        @($Variable.options.value) | Should -Be @('Allow', 'Quarantine', 'Block')
    }

    It 'grades the cached DefaultAccessLevel against the chosen level' {
        $Expected = Invoke-Render -Definition $script:Definition -Template $script:Definition.expected -Variables ([pscustomobject]@{ accessLevel = 'Block' })
        $Expected.DefaultAccessLevel | Should -BeExactly 'Block'
        $script:Definition.read.cacheType | Should -Be 'ExoActiveSyncOrganizationSettings'
    }

    It 'remediates with one Set-ActiveSyncOrganizationSettings carrying only the level' {
        Mock New-ExoRequest {}
        $Spec = Invoke-Render -Definition $script:Definition -Template $script:Definition.remediate -Variables ([pscustomobject]@{ accessLevel = 'Block' })
        Invoke-CIPPBaselineExoRequest -Remediate $Spec -TenantFilter 'contoso.onmicrosoft.com' -Current ([pscustomobject]@{ DefaultAccessLevel = 'Allow' })
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-ActiveSyncOrganizationSettings' -and @($cmdParams.Keys).Count -eq 1 -and $cmdParams['DefaultAccessLevel'] -ceq 'Block'
        }
    }
}
