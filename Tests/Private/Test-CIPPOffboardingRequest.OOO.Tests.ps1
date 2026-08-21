# Pester tests for OOO / empty TipTap HTML in Test-CIPPOffboardingRequest.
# Real OOO alone must count as an action; <p></p> must not.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $RequestPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPOffboardingRequest.ps1'
    $HtmlPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPHtmlIsEmpty.ps1'
    if (-not (Test-Path $RequestPath)) { throw "Could not locate Test-CIPPOffboardingRequest.ps1 at $RequestPath" }
    if (-not (Test-Path $HtmlPath)) { throw "Could not locate Test-CIPPHtmlIsEmpty.ps1 at $HtmlPath" }

    . $HtmlPath
    . $RequestPath

    function New-ValidOffboardBody {
        param([hashtable]$Extra = @{})
        $Body = [pscustomobject]@{
            tenantFilter = 'contoso.com'
            user         = @(@{ value = 'pat@contoso.com' })
        }
        foreach ($Key in $Extra.Keys) {
            $Body | Add-Member -NotePropertyName $Key -NotePropertyValue $Extra[$Key] -Force
        }
        $Body
    }
}

Describe 'Test-CIPPOffboardingRequest OOO' {
    It 'accepts a real Out of Office message as the only action' {
        $Result = Test-CIPPOffboardingRequest -Body (New-ValidOffboardBody -Extra @{
                OOO = '<p>No longer at %tenantname%.</p>'
            })

        $Result.IsValid | Should -BeTrue
        $Result.Errors | Should -BeNullOrEmpty
    }

    It 'rejects empty TipTap HTML when no other actions are selected' {
        $Result = Test-CIPPOffboardingRequest -Body (New-ValidOffboardBody -Extra @{
                OOO = '<p></p>'
            })

        $Result.IsValid | Should -BeFalse
        $Result.Errors -join ' ' | Should -Match 'No offboarding actions'
    }

    It 'rejects blank OOO when no other actions are selected' {
        $Result = Test-CIPPOffboardingRequest -Body (New-ValidOffboardBody -Extra @{
                OOO = ''
            })

        $Result.IsValid | Should -BeFalse
        $Result.Errors -join ' ' | Should -Match 'No offboarding actions'
    }
}
