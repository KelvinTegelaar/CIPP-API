[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Stubs exist only so Pester can mock them.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stubs exist only so Pester can mock them.')]
param()

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $noPagination) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Write-LogMessage { param($message, $tenant, $API, $headers, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Remove-CIPPBecTargetedCAPolicy.ps1')

    # Two containment policies for u1, one for u2, and an unmanaged policy without a description.
    $script:Policies = @(
        [pscustomobject]@{ id = 'pol-a'; description = 'ManagedBy=CIPP-BEC;Target=u1;CaseId=BEC-1;ExpiresUtc=2026-09-07T10:00:00.0000000Z' }
        [pscustomobject]@{ id = 'pol-b'; description = 'ManagedBy=CIPP-BEC;Target=u1;CaseId=BEC-2;ExpiresUtc=2026-09-08T10:00:00.0000000Z' }
        [pscustomobject]@{ id = 'pol-c'; description = 'ManagedBy=CIPP-BEC;Target=u2;CaseId=BEC-3;ExpiresUtc=2026-09-08T10:00:00.0000000Z' }
        [pscustomobject]@{ id = 'pol-d'; description = $null }
    )
}

Describe 'Remove-CIPPBecTargetedCAPolicy' {
    BeforeEach {
        Mock New-GraphGetRequest { $script:Policies }
        Mock New-GraphPOSTRequest { }
        Mock Write-LogMessage { }
    }

    It 'deletes the policy by id as the application, without listing policies, and logs it' {
        $Message = Remove-CIPPBecTargetedCAPolicy -TenantFilter 'contoso.com' -PolicyId 'pol-1' -Headers @{ 'x-ms-client-principal' = 'p' }
        $Message | Should -Be 'Removed BEC containment Conditional Access policy pol-1'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -eq 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/pol-1' -and $type -eq 'DELETE' -and $tenantid -eq 'contoso.com' -and $AsApp -eq $true }
        Should -Invoke New-GraphGetRequest -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Info' -and $message -eq 'Removed BEC containment Conditional Access policy pol-1' -and $tenant -eq 'contoso.com' -and $API -eq 'BECRemediate' -and $headers.'x-ms-client-principal' -eq 'p' }
    }

    It 'reports a policy that is already gone instead of failing' {
        Mock New-GraphPOSTRequest { throw 'Request_ResourceNotFound: Resource pol-1 does not exist or one of its queried reference-property objects are not present.' }
        $Message = Remove-CIPPBecTargetedCAPolicy -TenantFilter 'contoso.com' -PolicyId 'pol-1'
        $Message | Should -Be 'BEC containment Conditional Access policy pol-1 was already removed'
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $Sev -eq 'Error' }
    }

    It 'throws with the normalized error and logs it when the delete fails for another reason' {
        Mock New-GraphPOSTRequest { throw 'Insufficient privileges to complete the operation.' }
        { Remove-CIPPBecTargetedCAPolicy -TenantFilter 'contoso.com' -PolicyId 'pol-1' } | Should -Throw 'Failed to remove BEC containment Conditional Access policy pol-1: Insufficient privileges to complete the operation.'
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Error' -and $message -like 'Failed to remove BEC containment Conditional Access policy pol-1:*' -and $LogData.NormalizedError -like 'Insufficient privileges*' }
    }

    It 'requires a PolicyId or a UserId before touching Graph' {
        { Remove-CIPPBecTargetedCAPolicy -TenantFilter 'contoso.com' } | Should -Throw 'PolicyId or UserId is required'
        Should -Invoke New-GraphGetRequest -Times 0
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'removes every CIPP-BEC policy targeting the user, and only those, when given a UserId' {
        $Message = Remove-CIPPBecTargetedCAPolicy -TenantFilter 'contoso.com' -UserId 'u1'
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?*' -and $tenantid -eq 'contoso.com' -and $AsApp -eq $true }
        Should -Invoke New-GraphPOSTRequest -Times 2 -Exactly -ParameterFilter { $type -eq 'DELETE' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $uri -like '*/policies/pol-a' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $uri -like '*/policies/pol-b' }
        Should -Invoke New-GraphPOSTRequest -Times 0 -ParameterFilter { $uri -like '*/pol-c' -or $uri -like '*/pol-d' }
        $Message | Should -Be 'Removed BEC containment Conditional Access policy pol-a; Removed BEC containment Conditional Access policy pol-b'
    }

    It 'reports when the user has no containment policy and deletes nothing' {
        $Message = Remove-CIPPBecTargetedCAPolicy -TenantFilter 'contoso.com' -UserId 'u9'
        $Message | Should -Be 'No CIPP BEC containment policy exists for user u9'
        Should -Invoke New-GraphPOSTRequest -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Info' -and $message -eq 'No CIPP BEC containment policy exists for user u9' }
    }

    It 'keeps going past a policy that is already gone when removing by user' {
        Mock New-GraphPOSTRequest { throw 'Response status code does not indicate success: 404 (Not Found).' } -ParameterFilter { $uri -like '*/pol-a' }
        $Message = Remove-CIPPBecTargetedCAPolicy -TenantFilter 'contoso.com' -UserId 'u1'
        $Message | Should -Be 'BEC containment Conditional Access policy pol-a was already removed; Removed BEC containment Conditional Access policy pol-b'
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $uri -like '*/pol-b' }
    }

    It 'deletes nothing under -WhatIf' {
        $Message = Remove-CIPPBecTargetedCAPolicy -TenantFilter 'contoso.com' -UserId 'u1' -WhatIf
        Should -Invoke New-GraphGetRequest -Times 1
        Should -Invoke New-GraphPOSTRequest -Times 0
        $Message | Should -BeNullOrEmpty
    }
}
