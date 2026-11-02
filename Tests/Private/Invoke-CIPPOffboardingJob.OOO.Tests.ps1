# Pester tests for OOO handling in Invoke-CIPPOffboardingJob:
# - CIPP %vars% are resolved via Get-CIPPTextReplacement before Set-CIPPOutOfOffice
# - Empty TipTap HTML does not enqueue an OOO task

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $JobPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPOffboardingJob.ps1'
    $HtmlPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPHtmlIsEmpty.ps1'
    if (-not (Test-Path $JobPath)) { throw "Could not locate Invoke-CIPPOffboardingJob.ps1 at $JobPath" }
    if (-not (Test-Path $HtmlPath)) { throw "Could not locate Test-CIPPHtmlIsEmpty.ps1 at $HtmlPath" }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-Information { param($MessageData) }

    . $HtmlPath
    . $JobPath
}

Describe 'Invoke-CIPPOffboardingJob OOO' {
    BeforeEach {
        $script:CapturedInput = $null
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-Information -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id                         = 'user-id-1'
                displayName                = 'Pat Lee'
                onPremisesSyncEnabled      = $false
                onPremisesImmutableId      = $null
            }
        }
        Mock -CommandName Start-CIPPOrchestrator -MockWith {
            $script:CapturedInput = $InputObject
            'orch-1'
        }
    }

    It 'resolves %vars% and passes the result to Set-CIPPOutOfOffice' {
        Mock -CommandName Get-CIPPTextReplacement -MockWith {
            $Text -replace '%tenantname%', 'Contoso Ltd'
        }

        $Options = [pscustomobject]@{
            OOO            = '<p>No longer at %tenantname%.</p>'
            RevokeSessions = $false
        }

        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options $Options

        Should -Invoke Get-CIPPTextReplacement -Times 1 -Exactly -ParameterFilter {
            $TenantFilter -eq 'contoso.com' -and $Text -eq '<p>No longer at %tenantname%.</p>'
        }

        $OooTask = $script:CapturedInput.Batch | Where-Object { $_.Cmdlet -eq 'Set-CIPPOutOfOffice' }
        $OooTask | Should -Not -BeNullOrEmpty
        $OooTask.Parameters.InternalMessage | Should -Be '<p>No longer at Contoso Ltd.</p>'
        $OooTask.Parameters.ExternalMessage | Should -Be '<p>No longer at Contoso Ltd.</p>'
        $OooTask.Parameters.state | Should -Be 'Enabled'
    }

    It 'does not enqueue Set-CIPPOutOfOffice for empty TipTap HTML' {
        Mock -CommandName Get-CIPPTextReplacement -MockWith { $Text }

        $Options = [pscustomobject]@{
            OOO            = '<p></p>'
            RevokeSessions = $true
        }

        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options $Options

        Should -Invoke Get-CIPPTextReplacement -Times 0 -Exactly
        $script:CapturedInput.Batch | Where-Object { $_.Cmdlet -eq 'Set-CIPPOutOfOffice' } | Should -BeNullOrEmpty
        $script:CapturedInput.Batch | Where-Object { $_.Cmdlet -eq 'Revoke-CIPPSessions' } | Should -Not -BeNullOrEmpty
    }
}
