# RecommendationEmailNotifications: a declarative definition over the DirectoryRecommendationConfiguration cache.
# The collector caches the singleton; the engine's own render feeds the generic GraphRequest executor.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function New-GraphGetRequest { param($uri, $tenantid, $NoPagination) }
    function New-GraphPostRequest { param($tenantid, $uri, $type, $body, $AsApp) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }

    . (Join-Path $script:RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheDirectoryRecommendationConfiguration.ps1')
    . (Join-Path $Baselines 'Helpers/Expand-CIPPBaselineToken.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineGraphRequest.ps1')

    # The engine's own $Render, lifted out of Invoke-CIPPBaselineStandard so the test runs it verbatim.
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Baselines 'Helpers/Invoke-CIPPBaselineStandard.ps1'), [ref]$null, [ref]$null)
    $Assign = $Ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$Render' }, $true)
    $script:Render = [scriptblock]::Create($Assign.Right.Expression.Extent.Text.Trim('{', '}'))
    function Invoke-Render { param($Definition, $Template, $Variables) $TenantFilter = 'contoso.onmicrosoft.com'; & $script:Render $Template $Variables }

    $script:Definition = Get-Content -Raw (Join-Path $script:RepoRoot 'Config/BaselineStandards/Entra (AAD) Standards/RecommendationEmailNotifications.json') | ConvertFrom-Json
}

Describe 'Set-CIPPDBCacheDirectoryRecommendationConfiguration' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
    }

    It 'caches the setting as one row under a fixed id' {
        Mock New-GraphGetRequest { [pscustomobject]@{ isNotificationEnabled = $true } }
        Set-CIPPDBCacheDirectoryRecommendationConfiguration -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -eq 'https://graph.microsoft.com/beta/directory/recommendationConfiguration' }
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'DirectoryRecommendationConfiguration' -and $AddCount -and $ClearOnEmpty -and @($Data).Count -eq 1 -and
            $Data[0].id -eq 'recommendationConfiguration' -and $Data[0].isNotificationEnabled -eq $true
        }
    }

    It 'writes nothing and logs when the read fails, so the last good row stays' {
        Mock New-GraphGetRequest { throw 'Forbidden' }
        Set-CIPPDBCacheDirectoryRecommendationConfiguration -TenantFilter 'contoso.onmicrosoft.com'
        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' }
    }
}

Describe 'RecommendationEmailNotifications definition' {
    It 'grades isNotificationEnabled against the switch as a boolean' {
        foreach ($Value in $true, $false) {
            $Expected = Invoke-Render -Definition $script:Definition -Template $script:Definition.expected -Variables ([pscustomobject]@{ sendEmails = $Value })
            $Expected.isNotificationEnabled | Should -BeOfType [bool]
            $Expected.isNotificationEnabled | Should -Be $Value
        }
        $script:Definition.read.cacheType | Should -Be 'DirectoryRecommendationConfiguration'
    }

    It 'defaults to turning the emails off' {
        $script:Definition.variables.sendEmails.default | Should -BeFalse
    }

    It 'remediates with one delegated PATCH carrying only the setting' {
        foreach ($Value in $true, $false) {
            Mock New-GraphPostRequest {}
            $Spec = Invoke-Render -Definition $script:Definition -Template $script:Definition.remediate -Variables ([pscustomobject]@{ sendEmails = $Value })
            Invoke-CIPPBaselineGraphRequest -Remediate $Spec -TenantFilter 'contoso.onmicrosoft.com' -Current ([pscustomobject]@{ isNotificationEnabled = -not $Value })
            $ExpectedBody = '{"isNotificationEnabled":' + "$Value".ToLower() + '}'
            Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
                $uri -eq 'https://graph.microsoft.com/beta/directory/recommendationConfiguration' -and $type -eq 'PATCH' -and
                $body -ceq $ExpectedBody -and $AsApp -eq $false
            }
        }
    }
}
