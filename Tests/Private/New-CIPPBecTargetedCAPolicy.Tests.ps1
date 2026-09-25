[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Stubs exist only so Pester can mock them.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stubs exist only so Pester can mock them.')]
param()

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $noPagination) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Add-CIPPScheduledTask { param($Task, $Hidden, $Headers) }
    function Write-LogMessage { param($message, $tenant, $API, $headers, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecTargetedCAPolicy.ps1')

    $script:Common = @{ TenantFilter = 'contoso.com'; UserId = 'u1'; UserPrincipalName = 'victim@contoso.com'; CaseId = 'BEC-1'; Headers = @{ 'x-ms-client-principal' = 'p' } }
    $script:PoliciesUri = 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies'
}

Describe 'New-CIPPBecTargetedCAPolicy' {
    BeforeEach {
        Mock New-GraphGetRequest { @() }
        Mock New-GraphPOSTRequest { [pscustomobject]@{ id = 'pol-1' } }
        Mock Add-CIPPScheduledTask { }
        Mock Write-LogMessage { }
    }

    It 'creates an enabled policy that targets only the user, every application and client, and requires MFA' {
        $Message = New-CIPPBecTargetedCAPolicy @script:Common
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -eq $script:PoliciesUri -and $tenantid -eq 'contoso.com' -and $type -eq 'POST' -and $AsApp -eq $true }
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $Policy = $body | ConvertFrom-Json; (@($Policy.conditions.users.PSObject.Properties.Name) -join ',') -eq 'includeUsers' -and (@($Policy.conditions.users.includeUsers) -join ',') -eq 'u1' } -Because 'the users condition must name the one user and nothing else'
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $Policy = $body | ConvertFrom-Json; (@($Policy.conditions.applications.includeApplications) -join ',') -eq 'All' -and (@($Policy.conditions.clientAppTypes) -join ',') -eq 'all' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $Policy = $body | ConvertFrom-Json; $Policy.state -eq 'enabled' -and (@($Policy.grantControls.builtInControls) -join ',') -eq 'mfa' -and $Policy.grantControls.operator -eq 'OR' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $Policy = $body | ConvertFrom-Json; $Policy.displayName -like 'CIPP BEC containment - victim@contoso.com - expires ????-??-?? ??:??Z' -and $Policy.description -like 'ManagedBy=CIPP-BEC;Target=u1;CaseId=BEC-1;ExpiresUtc=*' }
        $Message | Should -Match "^Created Conditional Access policy 'CIPP BEC containment - victim@contoso\.com - expires .+Z' \(enabled, mfa\) for victim@contoso\.com; removal scheduled for \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}Z$"
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Info' -and $message -like 'Created Conditional Access policy*' -and $tenant -eq 'contoso.com' -and $API -eq 'BECRemediate' }
    }

    It 'maps mfaAndCompliantDevice to both controls ANDed and passes the report-only state through' {
        $Message = New-CIPPBecTargetedCAPolicy @script:Common -State 'enabledForReportingButNotEnabled' -Controls 'mfaAndCompliantDevice'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $Policy = $body | ConvertFrom-Json; $Policy.state -eq 'enabledForReportingButNotEnabled' -and (@($Policy.grantControls.builtInControls) -join ',') -eq 'mfa,compliantDevice' -and $Policy.grantControls.operator -eq 'AND' }
        $Message | Should -Match '\(enabledForReportingButNotEnabled, mfa \+ compliantDevice\)'
    }

    It 'schedules Remove-CIPPBecTargetedCAPolicy for the new policy at the expiry, referenced to the case' {
        $script:Expected = [DateTimeOffset]::UtcNow.AddHours(4).ToUnixTimeSeconds()
        $Message = New-CIPPBecTargetedCAPolicy @script:Common -ExpiresHours 4
        Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { $Task.Command.value -eq 'Remove-CIPPBecTargetedCAPolicy' -and $Task.Parameters.PolicyId -eq 'pol-1' -and $Task.Parameters.TenantFilter -eq 'contoso.com' -and $Task.TenantFilter -eq 'contoso.com' -and $Task.Reference -eq 'BEC-1' -and $Task.Name -like '*victim@contoso.com*' -and $Hidden -eq $false }
        Should -Invoke Add-CIPPScheduledTask -Times 1 -ParameterFilter { [math]::Abs([int64]$Task.ScheduledTime - $script:Expected) -le 120 } -Because 'ScheduledTime is the expiry as unix seconds'
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { $Policy = $body | ConvertFrom-Json; [math]::Abs(([DateTimeOffset]($Policy.description -split 'ExpiresUtc=')[1]).ToUnixTimeSeconds() - $script:Expected) -le 120 } -Because 'the description carries the same expiry'
        $Message | Should -Match '; removal scheduled for \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}Z$'
    }

    It 'still reports the created policy, with a WARNING to remove it by hand, when the removal cannot be scheduled' {
        Mock Add-CIPPScheduledTask { throw 'scheduler down' }
        $Message = New-CIPPBecTargetedCAPolicy @script:Common
        $Message | Should -Match "^Created Conditional Access policy .+; WARNING: could not schedule its removal \(scheduler down\) - remove it manually after \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}Z$"
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Warning' -and $message -eq 'Could not schedule removal of CA policy pol-1: scheduler down' }
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $Sev -eq 'Error' }
    }

    It 'throws with the normalized Graph error, logs it and schedules nothing when the policy cannot be created' {
        Mock New-GraphPOSTRequest { throw 'Insufficient privileges to complete the operation.' }
        { New-CIPPBecTargetedCAPolicy @script:Common } | Should -Throw 'Failed to create the targeted Conditional Access policy for victim@contoso.com: Insufficient privileges to complete the operation.'
        Should -Invoke Add-CIPPScheduledTask -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Error' -and $message -like 'Failed to create the targeted Conditional Access policy for victim@contoso.com:*' -and $LogData.NormalizedError -like 'Insufficient privileges*' }
    }

    It 'reuses an existing containment policy for the same user, but not one that belongs to another user' {
        Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'pol-old'; displayName = 'CIPP BEC containment - victim@contoso.com - expires 2026-09-07 10:00Z'; description = 'ManagedBy=CIPP-BEC;Target=u1;CaseId=BEC-0;ExpiresUtc=2026-09-07T10:00:00.0000000Z'; state = 'enabled' }, [pscustomobject]@{ id = 'pol-admins'; displayName = 'Require MFA for admins'; description = $null; state = 'enabled' }) }
        $Message = New-CIPPBecTargetedCAPolicy @script:Common
        $Message | Should -Be "A CIPP BEC containment policy already exists for victim@contoso.com ('CIPP BEC containment - victim@contoso.com - expires 2026-09-07 10:00Z', enabled); not creating another."
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -like "$script:PoliciesUri?*" -and $tenantid -eq 'contoso.com' -and $AsApp -eq $true }
        Should -Invoke New-GraphPOSTRequest -Times 0
        Should -Invoke Add-CIPPScheduledTask -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Info' -and $message -like '*already exists*' }

        Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'pol-u2'; displayName = 'CIPP BEC containment - other@contoso.com - expires 2026-09-07 10:00Z'; description = 'ManagedBy=CIPP-BEC;Target=u2;CaseId=BEC-0;ExpiresUtc=2026-09-07T10:00:00.0000000Z'; state = 'enabled' }) }
        $null = New-CIPPBecTargetedCAPolicy @script:Common
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -Because 'another user''s containment policy is not a reason to skip this one'
    }

    It 'creates nothing under -WhatIf and rejects an out-of-range lifetime or unknown control before touching Graph' {
        $null = New-CIPPBecTargetedCAPolicy @script:Common -WhatIf
        Should -Invoke New-GraphPOSTRequest -Times 0
        Should -Invoke Add-CIPPScheduledTask -Times 0
        { New-CIPPBecTargetedCAPolicy @script:Common -ExpiresHours 0 } | Should -Throw
        { New-CIPPBecTargetedCAPolicy @script:Common -ExpiresHours 169 } | Should -Throw
        { New-CIPPBecTargetedCAPolicy @script:Common -Controls 'passwordless' } | Should -Throw
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -Because 'only the -WhatIf run got past parameter binding'
    }
}
