BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Set-CIPPMailboxPermission { param($UserId, $AccessUser, $PermissionLevel, $Action, $AutoMap, $TenantFilter, $APIName, $Headers, [switch]$AsCmdletObject) }
    function Remove-CIPPFolderPermission { param($TenantFilter, $FolderIdentity, $User, $AccessRights, $Anchor) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Anchor) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Remove-CIPPMailboxDelegation.ps1')
    $script:Upn = 'victim@contoso.com'

    # A row shaped like Get-CIPPBecMailboxInventory's Delegations output.
    function New-Delegation {
        param([string]$PermissionType, [string]$Trustee, [string]$Identity = 'victim@contoso.com', [string]$Resource = 'victim@contoso.com', [string]$AccessRights = $PermissionType)
        [pscustomobject]@{ PermissionType = $PermissionType; Resource = $Resource; Identity = $Identity; Trustee = $Trustee; AccessRights = $AccessRights }
    }
}

Describe 'Remove-CIPPMailboxDelegation' {
    BeforeEach {
        Mock Set-CIPPMailboxPermission { }
        Mock Remove-CIPPFolderPermission { }
        Mock New-ExoRequest { }
        Mock Write-LogMessage { }
    }

    It 'routes FullAccess, SendAs and SendOnBehalf through Set-CIPPMailboxPermission as a Remove of the trustee on the mailbox' {
        $Delegations = @(
            (New-Delegation -PermissionType 'FullAccess' -Trustee 'assistant@contoso.com')
            (New-Delegation -PermissionType 'SendAs' -Trustee 'outsider@example.org')
            (New-Delegation -PermissionType 'SendOnBehalf' -Trustee 'guest_example.org#EXT#@contoso.onmicrosoft.com')
        )
        $Rows = @(Remove-CIPPMailboxDelegation -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -Delegations $Delegations -Headers @{ 'x-ms-client-principal' = 'test' })

        Should -Invoke Set-CIPPMailboxPermission -Exactly -Times 3 -ParameterFilter { $UserId -eq 'victim@contoso.com' -and $Action -eq 'Remove' -and $TenantFilter -eq 'contoso.com' -and $APIName -eq 'BECRemediate' -and $Headers.'x-ms-client-principal' -eq 'test' }
        Should -Invoke Set-CIPPMailboxPermission -Times 1 -ParameterFilter { $PermissionLevel -eq 'FullAccess' -and $AccessUser -eq 'assistant@contoso.com' }
        Should -Invoke Set-CIPPMailboxPermission -Times 1 -ParameterFilter { $PermissionLevel -eq 'SendAs' -and $AccessUser -eq 'outsider@example.org' }
        Should -Invoke Set-CIPPMailboxPermission -Times 1 -ParameterFilter { $PermissionLevel -eq 'SendOnBehalf' -and $AccessUser -eq 'guest_example.org#EXT#@contoso.onmicrosoft.com' }
        Should -Invoke Remove-CIPPFolderPermission -Times 0
        Should -Invoke New-ExoRequest -Times 0
        $Rows.Count | Should -Be 3
        $Rows.state | Should -Be @('success', 'success', 'success')
        $Rows.Target | Should -Be @('FullAccess assistant@contoso.com', 'SendAs outsider@example.org', 'SendOnBehalf guest_example.org#EXT#@contoso.onmicrosoft.com')
        $Rows[0].resultText | Should -Be 'Removed FullAccess for assistant@contoso.com from victim@contoso.com'
        $Rows[0].PSObject.Properties.Name | Should -Be @('Target', 'state', 'resultText')
    }

    It 'removes a folder right by folder id through Remove-CIPPFolderPermission, anchored on the mailbox, and names the folder in the result' {
        $Delegations = @(
            (New-Delegation -PermissionType 'Folder' -Trustee 'assistant@contoso.com' -Identity 'victim@contoso.com:LgAAAACalendar' -Resource 'victim@contoso.com:\Calendar' -AccessRights 'Editor')
            ([pscustomobject]@{ PermissionType = 'Folder'; Trustee = 'Default'; Resource = 'victim@contoso.com:\Inbox'; AccessRights = 'Reviewer' })
        )
        $Rows = @(Remove-CIPPMailboxDelegation -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -Delegations $Delegations)

        Should -Invoke Remove-CIPPFolderPermission -Exactly -Times 2 -ParameterFilter { $TenantFilter -eq 'contoso.com' -and $Anchor -eq 'victim@contoso.com' }
        Should -Invoke Remove-CIPPFolderPermission -Times 1 -ParameterFilter { $FolderIdentity -eq 'victim@contoso.com:LgAAAACalendar' -and $User -eq 'assistant@contoso.com' -and $AccessRights -eq 'Editor' }
        Should -Invoke Remove-CIPPFolderPermission -Times 1 -ParameterFilter { $FolderIdentity -eq 'victim@contoso.com:\Inbox' -and $User -eq 'Default' -and $AccessRights -eq 'Reviewer' } -Because 'a row without a folder id falls back to the resource path'
        Should -Invoke Set-CIPPMailboxPermission -Times 0
        Should -Invoke New-ExoRequest -Times 0
        Should -Invoke Write-LogMessage -Exactly -Times 2 -ParameterFilter { $Sev -eq 'Info' -and $API -eq 'BECRemediate' -and $tenant -eq 'contoso.com' }
        $Rows.state | Should -Be @('success', 'success')
        $Rows[0].Target | Should -Be 'Folder assistant@contoso.com'
        $Rows[0].resultText | Should -Be 'Removed folder permission for assistant@contoso.com on victim@contoso.com:\Calendar'
        $Rows[1].resultText | Should -Be 'Removed folder permission for Default on victim@contoso.com:\Inbox'
    }

    It 'removes a resource delegate with Set-CalendarProcessing on the resource mailbox' {
        $Rows = @(Remove-CIPPMailboxDelegation -TenantFilter 'contoso.com' -UserPrincipalName 'room@contoso.com' -Delegations @((New-Delegation -PermissionType 'ResourceDelegate' -Trustee 'assistant@contoso.com' -Identity 'room@contoso.com' -Resource 'room@contoso.com')))

        Should -Invoke New-ExoRequest -Exactly -Times 1 -ParameterFilter { $tenantid -eq 'contoso.com' -and $cmdlet -eq 'Set-CalendarProcessing' -and $Anchor -eq 'room@contoso.com' -and $cmdParams.Identity -eq 'room@contoso.com' -and $cmdParams.ResourceDelegates['@odata.type'] -eq '#Exchange.GenericHashTable' -and $cmdParams.ResourceDelegates['remove'] -contains 'assistant@contoso.com' }
        Should -Invoke Set-CIPPMailboxPermission -Times 0
        Should -Invoke Remove-CIPPFolderPermission -Times 0
        Should -Invoke Write-LogMessage -Exactly -Times 1 -ParameterFilter { $Sev -eq 'Info' -and $message -eq 'Removed resource delegate assistant@contoso.com from room@contoso.com' }
        $Rows.Count | Should -Be 1
        $Rows[0].state | Should -Be 'success'
        $Rows[0].Target | Should -Be 'ResourceDelegate assistant@contoso.com'
        $Rows[0].resultText | Should -Be 'Removed resource delegate assistant@contoso.com from room@contoso.com'
    }

    It 'reports an unknown delegation type as an error row without touching Exchange' {
        $Rows = @(Remove-CIPPMailboxDelegation -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -Delegations @((New-Delegation -PermissionType 'Forwarding' -Trustee 'x@example.org')))

        $Rows.Count | Should -Be 1
        $Rows[0].state | Should -Be 'error'
        $Rows[0].Target | Should -Be 'Forwarding x@example.org'
        $Rows[0].resultText | Should -Be "Failed to remove Forwarding for x@example.org from victim@contoso.com: Unknown delegation type 'Forwarding'"
        Should -Invoke Set-CIPPMailboxPermission -Times 0
        Should -Invoke Remove-CIPPFolderPermission -Times 0
        Should -Invoke New-ExoRequest -Times 0
        Should -Invoke Write-LogMessage -Exactly -Times 1 -ParameterFilter { $Sev -eq 'Error' -and $null -ne $LogData }
    }

    It 'skips a row without a trustee with an error, ignores null rows, and continues with the rest' {
        $Delegations = @(
            (New-Delegation -PermissionType 'SendAs' -Trustee '')
            $null
            (New-Delegation -PermissionType 'FullAccess' -Trustee 'assistant@contoso.com')
        )
        $Rows = @(Remove-CIPPMailboxDelegation -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -Delegations $Delegations)

        $Rows.Count | Should -Be 2
        $Rows[0].state | Should -Be 'error'
        $Rows[0].resultText | Should -Be 'A SendAs delegation without a trustee cannot be removed'
        $Rows[1].state | Should -Be 'success'
        Should -Invoke Set-CIPPMailboxPermission -Exactly -Times 1 -ParameterFilter { $PermissionLevel -eq 'FullAccess' -and $AccessUser -eq 'assistant@contoso.com' }
    }

    It 'turns a helper failure into an error row and keeps going with the next delegation' {
        Mock Set-CIPPMailboxPermission -ParameterFilter { $PermissionLevel -eq 'FullAccess' } { throw 'The operation could not be performed because object could not be found' }
        $Delegations = @(
            (New-Delegation -PermissionType 'FullAccess' -Trustee 'gone@contoso.com')
            (New-Delegation -PermissionType 'SendAs' -Trustee 'assistant@contoso.com')
        )
        $Rows = @(Remove-CIPPMailboxDelegation -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -Delegations $Delegations)

        $Rows.Count | Should -Be 2
        $Rows[0].state | Should -Be 'error'
        $Rows[0].resultText | Should -Be 'Failed to remove FullAccess for gone@contoso.com from victim@contoso.com: The operation could not be performed because object could not be found'
        $Rows[1].state | Should -Be 'success'
        Should -Invoke Set-CIPPMailboxPermission -Exactly -Times 2
        Should -Invoke Write-LogMessage -Exactly -Times 1 -ParameterFilter { $Sev -eq 'Error' -and $null -ne $LogData -and $message -like 'Failed to remove FullAccess for gone@contoso.com*' }
    }

    It 'removes nothing and returns no rows under -WhatIf' {
        $Rows = @(Remove-CIPPMailboxDelegation -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -Delegations @((New-Delegation -PermissionType 'FullAccess' -Trustee 'assistant@contoso.com')) -WhatIf)
        $Rows.Count | Should -Be 0
        Should -Invoke Set-CIPPMailboxPermission -Times 0
        Should -Invoke Write-LogMessage -Times 0
    }
}
