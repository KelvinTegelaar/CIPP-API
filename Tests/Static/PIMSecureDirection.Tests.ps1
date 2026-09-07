# Source invariant: CIPP's PIM surfaces only move privileged access in the secure direction.
#
# The maintainer's rule is that CIPP must be able to convert permanent assignments to eligible and
# create time-bound active assignments, but must never - through any UI, standard, template, API
# or MCP path - create a permanent assignment, convert eligible to permanent, or weaken PIM role
# settings below the secure floor. New-CIPPPIMScheduleRequest enforces the expiration rule and
# Test-CIPPPIMRoleSettingsFloor the settings rule; this test makes sure nothing routes around them:
#
#   1. the PIM schedule-request endpoints are only addressed from the builder, so every request
#      body passes its expiration checks;
#   2. no PIM-related source assigns a 'noExpiration' schedule;
#   3. no PIM-related source re-introduces the legacy permanent directoryRoles/members/$ref write;
#   4. every file that PATCHes a PIM role policy rule validates against the floor first.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ModulesRoot = Join-Path $BackendRoot 'Modules'

    $script:PIMFiles = @(
        Get-ChildItem -Path (Join-Path $ModulesRoot 'CIPPCore/Public/PIM') -Filter '*.ps1' -File
        Get-ChildItem -Path (Join-Path $ModulesRoot 'CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Roles') -Filter '*.ps1' -File
        Get-ChildItem -Path (Join-Path $ModulesRoot 'CIPPStandards/Public/Standards') -Filter 'Invoke-CIPPStandardPIM*.ps1' -File
        Get-ChildItem -Path (Join-Path $ModulesRoot 'CIPPAlerts/Public/Alerts') -Filter 'Get-CIPPAlertPermanentActiveAdminAssigned.ps1' -File
    )
    if ($script:PIMFiles.Count -lt 10) { throw "Expected the PIM source set to be present; found $($script:PIMFiles.Count) files" }

    $script:Sources = foreach ($File in $script:PIMFiles) {
        [pscustomobject]@{ Name = $File.Name; Text = [System.IO.File]::ReadAllText($File.FullName) }
    }

    $script:AllSources = foreach ($File in (Get-ChildItem -Path $ModulesRoot -Filter '*.ps1' -File -Recurse)) {
        [pscustomobject]@{ Name = $File.Name; Text = [System.IO.File]::ReadAllText($File.FullName) }
    }
}

Describe 'PIM secure-direction invariants' {
    It 'addresses the schedule-request endpoints only from New-CIPPPIMScheduleRequest' {
        $Pattern = [regex]'role(Eligibility|Assignment)ScheduleRequests'
        $Offenders = @($script:AllSources | Where-Object { $_.Name -ne 'New-CIPPPIMScheduleRequest.ps1' -and $Pattern.IsMatch($_.Text) } | ForEach-Object { $_.Name })
        # The builder's tests mention the URIs in assertions; sources elsewhere may not.
        $Offenders | Should -BeNullOrEmpty -Because 'every schedule request must go through the builder that refuses no-expiration schedules'
    }

    It 'never assigns a noExpiration schedule type' {
        # The string may appear in a rejection regex or in read-side detection, never as a value
        # being set on a request.
        $Pattern = [regex]"(type|expiration)\s*=\s*['""]noExpiration['""]"
        $Offenders = @($script:Sources | Where-Object { $Pattern.IsMatch($_.Text) } | ForEach-Object { $_.Name })
        $Offenders | Should -BeNullOrEmpty
    }

    It 'does not re-introduce the permanent directoryRoles member write' {
        $Pattern = [regex]'directoryRoles[^\r\n]*members/\$ref'
        $Offenders = @($script:Sources | Where-Object { $Pattern.IsMatch($_.Text) } | ForEach-Object { $_.Name })
        $Offenders | Should -BeNullOrEmpty -Because 'the PIM surfaces must not create permanent role memberships'
    }

    It 'validates against the secure floor wherever role policy rules are written' {
        $Writers = @($script:AllSources | Where-Object { $_.Text -match 'roleManagementPolicies/[^\r\n]*?/rules/' -and $_.Text -match 'PATCH' })
        $Writers.Count | Should -BeGreaterThan 0
        foreach ($Writer in $Writers) {
            # Set-CIPPPIMRoleSettings is the writer; its callers must have run the floor check.
            $Writer.Name | Should -Be 'Set-CIPPPIMRoleSettings.ps1'
        }
        $Callers = @($script:AllSources | Where-Object { $_.Name -ne 'Set-CIPPPIMRoleSettings.ps1' -and $_.Text -match 'Set-CIPPPIMRoleSettings\b' -and $_.Name -notlike '*.Tests.ps1' })
        $Callers.Count | Should -BeGreaterThan 0
        foreach ($Caller in $Callers) {
            $Caller.Text | Should -Match 'Test-CIPPPIMRoleSettingsFloor' -Because "$($Caller.Name) writes PIM policy rules and must validate the floor first"
        }
    }

    It 'keeps every secure-direction action inside Invoke-CIPPPIMAssignmentAction or the builder' {
        # The endpoint and the standards must delegate; they may not post schedule requests directly.
        $Direct = @($script:Sources | Where-Object {
                $_.Name -notin @('New-CIPPPIMScheduleRequest.ps1', 'Invoke-CIPPPIMAssignmentAction.ps1') -and
                $_.Text -match 'New-CIPPPIMScheduleRequest\b'
            } | ForEach-Object { $_.Name })
        $Direct | Should -BeNullOrEmpty
    }
}
