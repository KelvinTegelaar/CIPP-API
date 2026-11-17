# The Branding baseline's optional settings must express no opinion until set, so baselines saved before
# they existed keep grading and writing exactly the same properties. Drives the engine's own $Render.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    . (Join-Path $Baselines 'Helpers/Expand-CIPPBaselineToken.ps1')

    $Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Baselines 'Helpers/Invoke-CIPPBaselineStandard.ps1'), [ref]$null, [ref]$null)
    $Assign = $Ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$Render' }, $true)
    $script:Render = [scriptblock]::Create($Assign.Right.Expression.Extent.Text.Trim('{', '}'))
    function Invoke-Render { param($Definition, $Template, $Variables) $TenantFilter = 'contoso.onmicrosoft.com'; & $script:Render $Template $Variables }

    $script:Definition = Get-Content -Raw (Join-Path $script:RepoRoot 'Config/BaselineStandards/Global Standards/Branding.json') | ConvertFrom-Json
    $script:Saved = [PSCustomObject]@{
        signInPageText              = 'Welcome'
        usernameHintText            = 'you@contoso.com'
        hideAccountResetCredentials = $true
        layoutTemplateType          = [PSCustomObject]@{ label = 'Full-screen background'; value = 'default' }
        isHeaderShown               = $false
        isFooterShown               = $true
    }
    function Get-Rendered { param($Variables) @{
            Expected = Invoke-Render -Definition $script:Definition -Template $script:Definition.expected -Variables $Variables
            Bodies   = @((Invoke-Render -Definition $script:Definition -Template $script:Definition.remediate -Variables $Variables).requests.body)
        }
    }
}

Describe 'Branding baseline' {
    It 'renders a baseline saved before the new settings with exactly the original properties' {
        $Out = Get-Rendered $script:Saved

        foreach ($Object in @($Out.Expected) + $Out.Bodies) {
            @($Object.PSObject.Properties.Name | Sort-Object) | Should -Be @('loginPageLayoutConfiguration', 'loginPageTextVisibilitySettings', 'signInPageText', 'usernameHintText')
            @($Object.loginPageTextVisibilitySettings.PSObject.Properties.Name) | Should -Be @('hideAccountResetCredentials')
        }
    }

    It 'adds only the settings that were set, typed and in the right object' {
        $Variables = $script:Saved.PSObject.Copy()
        $Variables | Add-Member -NotePropertyMembers @{
            isKeepMeSignedInDisabled = $true
            hideTermsOfUse           = $false
            backgroundColor          = '#0078D4'
            customTermsOfUseUrl      = 'https://contoso.com/terms'
        }
        $Out = Get-Rendered $Variables

        foreach ($Object in @($Out.Expected) + $Out.Bodies) {
            $Object.isKeepMeSignedInDisabled | Should -BeOfType ([bool])
            $Object.isKeepMeSignedInDisabled | Should -BeTrue
            $Object.backgroundColor | Should -BeExactly '#0078D4'
            $Object.customTermsOfUseUrl | Should -BeExactly 'https://contoso.com/terms'
            $Object.PSObject.Properties.Name | Should -Not -Contain 'headerBackgroundColor'
            $Object.PSObject.Properties.Name | Should -Not -Contain 'customPrivacyAndCookiesUrl'
            $Object.loginPageTextVisibilitySettings.hideTermsOfUse | Should -BeFalse
            $Object.loginPageTextVisibilitySettings.PSObject.Properties.Name | Should -Not -Contain 'hidePrivacyAndCookies'
        }
    }

    It 'declares every new setting optional so nothing defaults into a write' {
        foreach ($Variable in $script:Definition.variables.PSObject.Properties | Where-Object { $_.Name -notin $script:Saved.PSObject.Properties.Name }) {
            $Variable.Value.omitWhenBlank | Should -BeTrue -Because $Variable.Name
            $Variable.Value.PSObject.Properties.Name | Should -Not -Contain 'default' -Because $Variable.Name
        }
    }
}
