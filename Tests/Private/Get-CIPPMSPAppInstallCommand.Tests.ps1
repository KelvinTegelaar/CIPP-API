# Pester tests for Get-CIPPMSPAppInstallCommand and ConvertTo-CIPPSafePwshArg escaping

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $env:CIPPRootPath = $RepoRoot

    function Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/ConvertTo-CIPPScriptBlockValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPSafePwshArg.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPMSPAppInstallCommand.ps1')

    $script:Tenant = [PSCustomObject]@{ customerId = 'cust-1'; defaultDomainName = 'contoso.onmicrosoft.com' }

    # Parse generated PowerShell and return its first statement, failing on any parse error.
    function Get-FirstStatement {
        param([string]$Script)
        $Tokens = $null; $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Script, [ref]$Tokens, [ref]$Errors)
        $Errors | Should -BeNullOrEmpty
        , @($Ast.EndBlock.Statements)
    }
}

Describe 'Hostile values stay data in generated PowerShell' {
    BeforeDiscovery {
        $Hostile = @(
            @{ Name = 'single quote'; Value = "evil.example'; Set-Content x y; #" }
            @{ Name = 'left typographic quote'; Value = "evil.example$([char]0x2018); Set-Content x y; #" }
            @{ Name = 'right typographic quote'; Value = "evil.example$([char]0x2019); Set-Content x y; #" }
            @{ Name = 'low-9 quote'; Value = "evil.example$([char]0x201A); Set-Content x y; #" }
            @{ Name = 'reversed-9 quote'; Value = "evil.example$([char]0x201B); Set-Content x y; #" }
            @{ Name = 'subexpression'; Value = 'evil.example$(Set-Content x y)' }
            @{ Name = 'backtick and semicolon'; Value = 'evil.example`; Set-Content x y' }
            @{ Name = 'double quote'; Value = 'evil.example"; Set-Content x y; #' }
            @{ Name = 'regex replacement token'; Value = 'evil.example$&$1' }
        )
    }

    It 'Automate detection script keeps a <Name> value inside the server literal' -ForEach $Hostile {
        $Result = Get-CIPPMSPAppInstallCommand -RmmName 'automate' -Tenant $script:Tenant -Params @{ Server = $Value; InstallerToken = 't'; LocationID = '1' }
        $Statements = Get-FirstStatement -Script $Result.DetectionScriptContent
        $First = $Statements[0]
        $First | Should -BeOfType ([System.Management.Automation.Language.AssignmentStatementAst])
        $Literal = $First.Right.Expression
        $Literal | Should -BeOfType ([System.Management.Automation.Language.StringConstantExpressionAst])
        $Literal.Value | Should -BeExactly $Value
        ($Statements | Where-Object { $_.Extent.Text -like 'Set-Content*' }) | Should -BeNullOrEmpty
    }

    It 'ConvertTo-CIPPSafePwshArg keeps a <Name> value as one argument' -ForEach $Hostile {
        $Statements = Get-FirstStatement -Script "install.ps1 -Server $(ConvertTo-CIPPSafePwshArg -Value $Value)"
        $Statements.Count | Should -Be 1
        $Elements = $Statements[0].PipelineElements[0].CommandElements
        $Elements.Count | Should -Be 3
        $Elements[2].Value | Should -BeExactly $Value
    }

    It 'ConvertTo-CIPPSafePwshArg strips line breaks' {
        ConvertTo-CIPPSafePwshArg -Value "a`r`nb" | Should -Not -Match "[`r`n]"
    }

    It 'a normal server name is unchanged' {
        $Result = Get-CIPPMSPAppInstallCommand -RmmName 'automate' -Tenant $script:Tenant -Params @{ Server = 'https://automate.contoso.com'; InstallerToken = 't'; LocationID = '1' }
        $Result.DetectionScriptContent | Should -Match ([regex]::Escape("`$ServerAddress = 'https://automate.contoso.com'"))
        $Result.InstallCommandLine | Should -Match ([regex]::Escape("-Server 'https://automate.contoso.com'"))
    }
}
