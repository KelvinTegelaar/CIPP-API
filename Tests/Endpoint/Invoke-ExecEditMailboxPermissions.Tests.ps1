# Pester tests for Invoke-ExecEditMailboxPermissions
# Covers each request body bucket (RemoveFullAccess / AddFullAccess / AddFullAccessNoAutoMap /
# AddSendAs / RemoveSendAs / AddSendOnBehalf / RemoveSendOnBehalf) mapping to the right EXO cmdlet
# and parameters, the success Results strings, cache syncing, and the per-item error path.
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

    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-ExoRequest { param($Anchor, $tenantid, $cmdlet, $cmdParams) }
    function Sync-CIPPMailboxPermissionCache { param($TenantFilter, $MailboxIdentity, $User, $PermissionType, $Action) }
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
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ id = 'user-guid' } }
        Mock -CommandName New-ExoRequest -MockWith { }
        Mock -CommandName Sync-CIPPMailboxPermissionCache -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'resolves the userID via Graph and returns OK' {
        $response = Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddFullAccess' -Users @('user@contoso.com')) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*graph.microsoft.com/beta/users/shared@contoso.com*' }
    }

    It 'RemoveFullAccess -> Remove-MailboxPermission (FullAccess) and syncs cache' {
        $response = Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'RemoveFullAccess' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Remove-MailboxPermission' -and $cmdParams.Identity -eq 'user-guid' -and
            $cmdParams.user -eq 'user@contoso.com' -and $cmdParams.accessRights -contains 'FullAccess'
        }
        Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter { $PermissionType -eq 'FullAccess' -and $Action -eq 'Remove' }
        $response.Body.Results | Should -Contain 'Removed user@contoso.com from shared@contoso.com Shared Mailbox permissions'
    }

    It 'AddFullAccess -> Add-MailboxPermission with automapping $true and syncs cache' {
        $response = Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddFullAccess' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Add-MailboxPermission' -and $cmdParams.automapping -eq $true -and $cmdParams.accessRights -contains 'FullAccess'
        }
        Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter { $PermissionType -eq 'FullAccess' -and $Action -eq 'Add' }
        $response.Body.Results | Should -Contain 'Granted user@contoso.com access to shared@contoso.com Mailbox with automapping'
    }

    It 'AddFullAccessNoAutoMap -> Add-MailboxPermission with automapping $false' {
        $response = Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddFullAccessNoAutoMap' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Add-MailboxPermission' -and $cmdParams.automapping -eq $false
        }
        $response.Body.Results | Should -Contain 'Granted user@contoso.com access to shared@contoso.com Mailbox without automapping'
    }

    It 'AddSendAs -> Add-RecipientPermission (Trustee) and syncs cache' {
        $response = Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddSendAs' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Add-RecipientPermission' -and $cmdParams.Trustee -eq 'user@contoso.com' -and $cmdParams.accessRights -contains 'SendAs'
        }
        Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter { $PermissionType -eq 'SendAs' -and $Action -eq 'Add' }
        $response.Body.Results | Should -Contain 'Granted user@contoso.com access to shared@contoso.com with Send As permissions'
    }

    It 'RemoveSendAs -> Remove-RecipientPermission (Trustee) and syncs cache' {
        $response = Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'RemoveSendAs' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Remove-RecipientPermission' -and $cmdParams.Trustee -eq 'user@contoso.com'
        }
        Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter { $PermissionType -eq 'SendAs' -and $Action -eq 'Remove' }
        $response.Body.Results | Should -Contain 'Removed user@contoso.com from shared@contoso.com with Send As permissions'
    }

    It 'AddSendOnBehalf -> Set-Mailbox with GrantSendonBehalfTo add hashtable' {
        $response = Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddSendOnBehalf' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-Mailbox' -and $cmdParams.GrantSendonBehalfTo.add -eq 'user@contoso.com' -and
            $cmdParams.GrantSendonBehalfTo['@odata.type'] -eq '#Exchange.GenericHashTable'
        }
        $response.Body.Results | Should -Contain 'Granted user@contoso.com access to shared@contoso.com with Send On Behalf Permissions'
    }

    It 'RemoveSendOnBehalf -> Set-Mailbox with GrantSendonBehalfTo remove hashtable' {
        $response = Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'RemoveSendOnBehalf' -Users @('user@contoso.com')) -TriggerMetadata $null

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-Mailbox' -and $cmdParams.GrantSendonBehalfTo.remove -eq 'user@contoso.com'
        }
        $response.Body.Results | Should -Contain 'Removed user@contoso.com from shared@contoso.com Send on Behalf Permissions'
    }

    It 'processes every user in a multi-user bucket' {
        $response = Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddSendAs' -Users @('a@contoso.com', 'b@contoso.com')) -TriggerMetadata $null

        Should -Invoke New-ExoRequest -Times 2 -Exactly -ParameterFilter { $cmdlet -eq 'Add-RecipientPermission' }
        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
    }

    It 'records a per-item failure message and logs an error when New-ExoRequest throws' {
        Mock -CommandName New-ExoRequest -MockWith { throw 'EXO down' }

        $response = Invoke-ExecEditMailboxPermissions -Request (New-EditRequest -Bucket 'AddFullAccess' -Users @('user@contoso.com')) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        ($response.Body.Results -join "`n") | Should -Match 'Could not add user@contoso.com shared mailbox permissions for shared@contoso.com'
        Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Error' }
    }
}
