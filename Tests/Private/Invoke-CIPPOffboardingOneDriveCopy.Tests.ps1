# Pester tests for Invoke-CIPPOffboardingOneDriveCopy: the offboarding step reuses Start-CIPPOneDriveCopyToUser

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPOffboardingOneDriveCopy.ps1')
    function Start-CIPPOneDriveCopyToUser { param($TenantFilter, $Leaver, $Recipients, $StartedBy, $OperationId, $Headers, $APIName, [switch]$WaitForSignInBlock) }

    function New-StartResult([object[]]$Recipients) {
        [pscustomobject]@{ OperationId = 'op-1'; FolderName = 'pat@contoso.com'; RootItemCount = 4; ExpectedBytes = 100; Warnings = @(); Recipients = $Recipients }
    }
}

Describe 'Invoke-CIPPOffboardingOneDriveCopy' {
    BeforeEach {
        Mock Start-CIPPOneDriveCopyToUser { New-StartResult @([pscustomobject]@{ UserPrincipalName = 'bob@contoso.com'; State = 'Queued' }) }
    }

    It 'passes the wizard recipients (objects after a JSON round trip, or strings) to the core function' {
        $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"tech@partner.com"}'))
        $Result = Invoke-CIPPOffboardingOneDriveCopy -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Headers @{ 'x-ms-client-principal' = $Principal } `
            -Recipients @(@{ label = 'Bob'; value = 'bob-id' }, [pscustomobject]@{ value = 'carol-id' }, 'dave@contoso.com', $null)
        $Result | Should -BeLike 'Started OneDrive copy op-1 of pat@contoso.com into folder pat@contoso.com for bob@contoso.com*'
        Should -Invoke Start-CIPPOneDriveCopyToUser -Times 1 -Exactly -ParameterFilter {
            $Leaver -eq 'pat@contoso.com' -and (@($Recipients) -join ';') -eq 'bob-id;carol-id;dave@contoso.com' -and $StartedBy -eq 'tech@partner.com' -and $WaitForSignInBlock
        }
    }

    It 'starts the copy under the operation id the offboarding job chose' {
        $Id = '11111111-2222-3333-4444-555555555555'
        $null = Invoke-CIPPOffboardingOneDriveCopy -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Recipients @('bob-id') -OperationId $Id
        Should -Invoke Start-CIPPOneDriveCopyToUser -Times 1 -Exactly -ParameterFilter { $OperationId -eq $Id }
    }

    It 'reports a recipient that did not start as an error line' {
        Mock Start-CIPPOneDriveCopyToUser { New-StartResult @([pscustomobject]@{ UserPrincipalName = 'bob@contoso.com'; State = 'Failed'; Message = 'Copy failed to start: denied' }, [pscustomobject]@{ UserPrincipalName = 'carol@contoso.com'; State = 'Queued' }) }
        Invoke-CIPPOffboardingOneDriveCopy -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Recipients @('bob-id', 'carol-id') | Should -BeLike 'Error: *bob@contoso.com (Copy failed to start: denied)*'
    }

    It 'throws when there are no recipients, without starting anything' {
        { Invoke-CIPPOffboardingOneDriveCopy -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Recipients @(@{ label = 'x' }) } | Should -Throw 'No OneDrive copy recipients were given.'
        Should -Invoke Start-CIPPOneDriveCopyToUser -Times 0 -Exactly
    }

    It 'lets a refusal from the core function fail the step' {
        Mock Start-CIPPOneDriveCopyToUser { throw [System.ArgumentException]::new('OneDrive copy not started. Recipient bob@contoso.com does not have enough space.') }
        { Invoke-CIPPOffboardingOneDriveCopy -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Recipients @('bob-id') } | Should -Throw '*does not have enough space*'
    }
}
