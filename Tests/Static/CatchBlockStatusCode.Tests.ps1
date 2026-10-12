# A catch block that answers 200 hides the failure from the frontend, MCP and Craft's response cache (which stores 2xx).

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:EntrypointRoot = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public'

    # Deliberate degradations: the catch handles an expected condition and the response is a real success.
    $script:Allowed = @{
        'Invoke-ListGraphRequest'          = 'IgnoreErrors=true opts in to errors as data'
        'Invoke-ListBrandingSettings'      = 'falls back to default branding'
        'Invoke-ExecSSOSetup'              = 'app created, secret failed: warning with Repair'
        'Invoke-ListUserOneDriveShortcuts' = 'user without a drive has no shortcuts'
        'Invoke-ListCSPsku'                = 'no Sherweb mapping means an empty catalog'
    }
}

Describe 'HTTP entrypoint catch blocks' {
    It 'do not return HttpStatusCode OK' {
        $Files = @(Get-ChildItem -Path $script:EntrypointRoot -Filter 'Invoke-*.ps1' -File -Recurse)
        $Files.Count | Should -BeGreaterThan 400

        $Offenders = foreach ($File in $Files) {
            if ($script:Allowed.ContainsKey($File.BaseName)) { continue }
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            $Catches = $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CatchClauseAst] }, $true)
            foreach ($Catch in $Catches) {
                $OkRefs = $Catch.Body.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.MemberExpressionAst] -and
                        $Node.Member.Extent.Text -eq 'OK' -and
                        $Node.Expression.Extent.Text -match 'HttpStatusCode' -and
                        $Node.Parent -isnot [System.Management.Automation.Language.BinaryExpressionAst]
                    }, $true)
                foreach ($Ref in $OkRefs) { "$($File.BaseName):$($Ref.Extent.StartLineNumber)" }
            }
        }

        @($Offenders) | Should -BeNullOrEmpty -Because 'a failure must return an error status; add the endpoint to the allow-list only when the catch handles an expected condition'
    }
}
