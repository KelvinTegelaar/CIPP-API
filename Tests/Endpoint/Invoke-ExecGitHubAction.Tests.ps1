# Pester tests for the status an inline template import returns when it fails.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function Import-CommunityTemplate { param($Template, $SHA, $Source, [switch]$Force) }

    $Endpoint = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecGitHubAction.ps1' | Select-Object -First 1 -ExpandProperty FullName
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $Endpoint -Raw)))

    function Invoke-Import {
        $Body = [pscustomobject]@{ Action = 'ImportTemplate'; Template = [pscustomobject]@{ PartitionKey = 'StandardsTemplateV2'; RowKey = 'r1'; JSON = '{}' }; SHA = 'x'; Source = 'test' }
        Invoke-ExecGitHubAction -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecGitHubAction' }; Headers = @{}; Query = [pscustomobject]@{}; Body = $Body })
    }
}

Describe 'ExecGitHubAction ImportTemplate' {
    It 'answers 403 when the import is refused for the caller' {
        Mock Import-CommunityTemplate { throw [System.UnauthorizedAccessException]::new("Your role can't update this template.") }
        $Response = Invoke-Import
        $Response.StatusCode | Should -Be 403
        $Response.Body.Results.resultText | Should -BeLike "*can't update this template*"
    }

    It 'answers 500 when the import fails for another reason' {
        Mock Import-CommunityTemplate { throw 'storage unavailable' }
        (Invoke-Import).StatusCode | Should -Be 500
    }

    It 'answers 200 when the import succeeds' {
        Mock Import-CommunityTemplate { "Created template 'r1'." }
        (Invoke-Import).StatusCode | Should -Be 200
    }
}
