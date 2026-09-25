# Pester tests for the 'teamsvoice' branch of New-CIPPRestoreTask.
#
# The branch re-assigns backed-up Teams phone numbers through the Graph teamsAdministration
# actions. What matters is the decision per number: skip when already in place, assign when
# free, and only move a number away from another holder when overwrite is on, waiting for the
# async unassign to land first. These tests pin that decision table and the request bodies.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'New-CIPPRestoreTask.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate New-CIPPRestoreTask.ps1 under Modules/' }

    function Get-CIPPBackup { param($Type, $Name) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Get-NormalizedError { param($Message) $Message }

    # Real helper: the number type must reach Graph in camelCase.
    $NumberTypePath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CippTeamsNumberType.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $NumberTypePath) { throw 'Could not locate Get-CippTeamsNumberType.ps1 under Modules/' }
    . $NumberTypePath

    . $FunctionPath

    $script:BaseUri = 'https://graph.microsoft.com/v1.0/admin/teams/telephoneNumberManagement/numberAssignments'
    $script:UserA = '11111111-1111-1111-1111-111111111111'
    $script:UserB = '22222222-2222-2222-2222-222222222222'

    function New-BackedUpNumber {
        [pscustomobject]@{
            telephoneNumber    = '+4512345678'
            assignmentTargetId = $script:UserA
            assignmentStatus   = 'userAssigned'
            assignmentCategory = 'primary'
            numberType         = 'directRouting'
            locationId         = 'loc-1'
        }
    }

    function New-LiveNumber {
        param($TargetId, $Status, $LocationId, $Category)
        [pscustomobject]@{
            telephoneNumber    = '+4512345678'
            assignmentTargetId = $TargetId
            assignmentStatus   = $Status
            numberType         = 'directRouting'
            locationId         = $LocationId
            assignmentCategory = $Category
        }
    }

    function Invoke-Restore {
        param($Live, [bool]$Overwrite = $false)
        Mock Get-CIPPBackup { [pscustomobject]@{ teamsvoice = @(New-BackedUpNumber) } }
        Mock New-GraphGetRequest { $Live }
        Mock New-GraphPOSTRequest { }
        Mock Write-LogMessage { }
        Mock Start-Sleep { }
        New-CIPPRestoreTask -Task 'teamsvoice' -TenantFilter 'contoso.onmicrosoft.com' -backup 'contoso_2026-09-16-0100' -overwrite $Overwrite -APINAME 'Restore' -Headers @{}
    }
}

Describe 'New-CIPPRestoreTask teamsvoice' {
    It 'assigns a number that is currently unassigned, with the backed-up attributes' {
        $Result = Invoke-Restore -Live (New-LiveNumber -TargetId $null -Status 'unassigned')

        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq "$script:BaseUri/assignNumber" -and
            ($body | ConvertFrom-Json).telephoneNumber -eq '+4512345678' -and
            ($body | ConvertFrom-Json).assignmentTargetId -eq $script:UserA -and
            ($body | ConvertFrom-Json).numberType -eq 'directRouting' -and
            ($body | ConvertFrom-Json).assignmentCategory -eq 'primary' -and
            ($body | ConvertFrom-Json).locationId -eq 'loc-1'
        }
        $Result | Should -Contain 'Restored: 1 TeamsPhoneNumber from backup'
    }

    It 'skips a number already assigned to the backed-up target' {
        $Result = Invoke-Restore -Live (New-LiveNumber -TargetId $script:UserA -Status 'userAssigned')

        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        $Result | Should -Contain "Teams phone number +4512345678 is already assigned to $script:UserA"
        $Result | Should -Contain 'No items were restored from backup.'
    }

    It 'leaves a number held by someone else alone when overwrite is off' {
        $Result = Invoke-Restore -Live (New-LiveNumber -TargetId $script:UserB -Status 'userAssigned')

        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        $Result | Should -Contain "Teams phone number +4512345678 is assigned to $script:UserB and overwrite is disabled"
    }

    It 'unassigns, waits for the unassign to land, then assigns when overwrite is on' {
        # First GET is the live snapshot (held by B); the poll after unassign sees it free.
        $script:GetCalls = 0
        Mock Get-CIPPBackup { [pscustomobject]@{ teamsvoice = @(New-BackedUpNumber) } }
        Mock New-GraphGetRequest {
            $script:GetCalls++
            if ($script:GetCalls -eq 1) { New-LiveNumber -TargetId $script:UserB -Status 'userAssigned' } else { New-LiveNumber -TargetId $null -Status 'unassigned' }
        }
        Mock New-GraphPOSTRequest { }
        Mock Write-LogMessage { }
        Mock Start-Sleep { }

        $Result = New-CIPPRestoreTask -Task 'teamsvoice' -TenantFilter 'contoso.onmicrosoft.com' -backup 'contoso_2026-09-16-0100' -overwrite $true -APINAME 'Restore' -Headers @{}

        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq "$script:BaseUri/unassignNumber" -and ($body | ConvertFrom-Json).numberType -eq 'directRouting'
        }
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -eq "$script:BaseUri/assignNumber" }
        Should -Invoke Start-Sleep -Times 1 -Exactly
        $Result | Should -Contain 'Restored: 1 TeamsPhoneNumber from backup'
    }

    It 'reports the failure and keeps going when the unassign never lands' {
        Mock Get-CIPPBackup { [pscustomobject]@{ teamsvoice = @(New-BackedUpNumber) } }
        Mock New-GraphGetRequest { New-LiveNumber -TargetId $script:UserB -Status 'userAssigned' }
        Mock New-GraphPOSTRequest { }
        Mock Write-LogMessage { }
        Mock Start-Sleep { }

        $Result = New-CIPPRestoreTask -Task 'teamsvoice' -TenantFilter 'contoso.onmicrosoft.com' -backup 'contoso_2026-09-16-0100' -overwrite $true -APINAME 'Restore' -Headers @{}

        Should -Invoke Start-Sleep -Times 10 -Exactly
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly -ParameterFilter { $uri -eq "$script:BaseUri/assignNumber" }
        ($Result | Where-Object { $_ -like 'Could not restore Teams phone number +4512345678 : Unassignment*' }).Count | Should -Be 1
    }

    It 'updates the emergency location when the holder matches but the location changed and overwrite is on' {
        $Result = Invoke-Restore -Live (New-LiveNumber -TargetId $script:UserA -Status 'userAssigned' -LocationId 'loc-old') -Overwrite $true

        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq "$script:BaseUri/updateNumber" -and
            ($body | ConvertFrom-Json).telephoneNumber -eq '+4512345678' -and
            ($body | ConvertFrom-Json).locationId -eq 'loc-1'
        }
        $Result | Should -Contain 'Restored: 1 TeamsPhoneNumber from backup'
    }

    It 'leaves a matching holder with a changed location alone when overwrite is off' {
        $Result = Invoke-Restore -Live (New-LiveNumber -TargetId $script:UserA -Status 'userAssigned' -LocationId 'loc-old')

        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        $Result | Should -Contain "Teams phone number +4512345678 is already assigned to $script:UserA"
    }

    It 'reassigns through unassign + assign when the holder matches but the category changed and overwrite is on' {
        # updateNumber cannot change assignmentCategory, so this has to take the move path.
        $script:GetCalls = 0
        Mock Get-CIPPBackup { [pscustomobject]@{ teamsvoice = @(New-BackedUpNumber) } }
        Mock New-GraphGetRequest {
            $script:GetCalls++
            if ($script:GetCalls -eq 1) { New-LiveNumber -TargetId $script:UserA -Status 'userAssigned' -Category 'private' } else { New-LiveNumber -TargetId $null -Status 'unassigned' }
        }
        Mock New-GraphPOSTRequest { }
        Mock Write-LogMessage { }
        Mock Start-Sleep { }

        $Result = New-CIPPRestoreTask -Task 'teamsvoice' -TenantFilter 'contoso.onmicrosoft.com' -backup 'contoso_2026-09-16-0100' -overwrite $true -APINAME 'Restore' -Headers @{}

        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -eq "$script:BaseUri/unassignNumber" }
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq "$script:BaseUri/assignNumber" -and ($body | ConvertFrom-Json).assignmentCategory -eq 'primary'
        }
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly -ParameterFilter { $uri -eq "$script:BaseUri/updateNumber" }
        $Result | Should -Contain 'Restored: 1 TeamsPhoneNumber from backup'
    }

    It 'leaves a matching holder with a changed category alone when overwrite is off' {
        $Result = Invoke-Restore -Live (New-LiveNumber -TargetId $script:UserA -Status 'userAssigned' -Category 'private')

        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        $Result | Should -Contain "Teams phone number +4512345678 is already assigned to $script:UserA"
    }
}
