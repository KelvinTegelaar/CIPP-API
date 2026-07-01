# Pester tests for Invoke-ExecEditMailboxPermissions
# The endpoint now delegates every request bucket (RemoveFullAccess / AddFullAccess /
# AddFullAccessNoAutoMap / AddSendAs / RemoveSendAs / AddSendOnBehalf / RemoveSendOnBehalf) to
# Set-CIPPMailboxPermission, so these tests assert each bucket maps to the right
# PermissionLevel / Action / AutoMap. The EXO cmdlet mapping, logging, and cache sync are the
# delegate's responsibility and are covered by Set-CIPPMailboxPermission.Tests.ps1.
#
# NOTE: the early `if ($username -eq $null) { exit }` guard is deliberately NOT exercised - `exit`
# inside a dot-sourced function terminates the Pester runspace, so it cannot be tested in-process.
# Every test below supplies a userID.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecEditMailboxPermissions.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecEditMailboxPermissions.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    # The function uses the short [HttpStatusCode] (the Functions host supplies `using namespace
    # System.Net`). Register a type accelerator so it resolves when the function is dot-sourced here.
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Set-CIPPMailboxPermission { param($UserId, $AccessUser, $PermissionLevel, $Action, $AutoMap, $TenantFilter, $APIName, $Headers) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    # Build a request whose body carries a single bucket of delegates (mirrors the frontend's
    # { value = @(...) } shape that the function reads via ($Request.body.<Bucket>).value).
    function New-EditRequest {
        param([string]$Bucket, [string[]]$Users, [string]$UserID = 'shared@contoso.com')
        $body = [pscustomobject]@{ userID = $UserID; tenantfilter = 'contoso.com' }
        $body | Add-Member -NotePropertyName $Bucket -NotePropertyValue ([pscustomobject]@{ value = $Users })
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecEditMailboxPermissions' }
            Headers = @{ Authorization = 'token' }
            Body    = $body
        }
    }
}

Describe 'Invoke-ExecEditMailboxPermissions' {
    BeforeEach {
        Mock -CommandName Set-CIPPMailboxPermission -MockWith { "$Action $PermissionLevel for $AccessUser" }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'returns OK and passes the mailbox UPN through as the identity' {
        $response = Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddFullAccess' -Users @('user@contoso.com')) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $UserId -eq 'shared@contoso.com' -and $TenantFilter -eq 'contoso.com' }
    }

    It 'RemoveFullAccess -> FullAccess / Remove' {
        Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'RemoveFullAccess' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter {
            $PermissionLevel -eq 'FullAccess' -and $Action -eq 'Remove' -and $AccessUser -eq 'user@contoso.com'
        }
    }

    It 'AddFullAccess -> FullAccess / Add with AutoMap $true' {
        Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddFullAccess' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter {
            $PermissionLevel -eq 'FullAccess' -and $Action -eq 'Add' -and $AutoMap -eq $true
        }
    }

    It 'AddFullAccessNoAutoMap -> FullAccess / Add with AutoMap $false' {
        Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddFullAccessNoAutoMap' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter {
            $PermissionLevel -eq 'FullAccess' -and $Action -eq 'Add' -and $AutoMap -eq $false
        }
    }

    It 'AddSendAs -> SendAs / Add' {
        Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddSendAs' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $PermissionLevel -eq 'SendAs' -and $Action -eq 'Add' }
    }

    It 'RemoveSendAs -> SendAs / Remove' {
        Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'RemoveSendAs' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $PermissionLevel -eq 'SendAs' -and $Action -eq 'Remove' }
    }

    It 'AddSendOnBehalf -> SendOnBehalf / Add' {
        Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddSendOnBehalf' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $PermissionLevel -eq 'SendOnBehalf' -and $Action -eq 'Add' }
    }

    It 'RemoveSendOnBehalf -> SendOnBehalf / Remove' {
        Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'RemoveSendOnBehalf' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $PermissionLevel -eq 'SendOnBehalf' -and $Action -eq 'Remove' }
    }

    It 'processes every user in a multi-user bucket and collects their results' {
        $response = Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddSendAs' -Users @('a@contoso.com', 'b@contoso.com')) -TriggerMetadata $null

        Should -Invoke Set-CIPPMailboxPermission -Times 2 -Exactly -ParameterFilter { $PermissionLevel -eq 'SendAs' -and $Action -eq 'Add' }
        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body.Results | Should -Contain 'Add SendAs for a@contoso.com'
        $response.Body.Results | Should -Contain 'Add SendAs for b@contoso.com'
    }

    It 'surfaces the delegate failure string in Results and still returns OK' {
        Mock -CommandName Set-CIPPMailboxPermission -MockWith { 'Failed to Add FullAccess for user@contoso.com on shared@contoso.com: boom' }

        $response = Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddFullAccess' -Users @('user@contoso.com')) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        ($response.Body.Results -join "`n") | Should -Match 'Failed to Add FullAccess for user@contoso.com on shared@contoso.com: boom'
    }
}
