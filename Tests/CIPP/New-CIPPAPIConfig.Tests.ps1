# A secret reset must never leave an API client app without a secret: the new one is added
# first and the old ones are removed only once it exists.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-GraphToken { @{ access_token = 'token' } }
    function Read-JwtAccessDetails { @{ Roles = @('Application.ReadWrite.All', 'Directory.ReadWrite.All') } }
    function Repair-CippApiIdentifierUri { @{ Fixed = $false; Message = 'ok' } }
    function Update-AppManagementPolicy { @{ PolicyAction = 'none' } }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
    function Start-Sleep { }
    function New-GraphGetRequest {
        param($uri)
        if ($uri -match 'servicePrincipals') { return @{ id = 'sp-id' } }
        if ($uri -match 'defaultAppManagementPolicy') { return @{ applicationRestrictions = @{ passwordcredentials = @() } } }
        @{
            id                  = 'app-object-id'
            appId               = 'app-id'
            displayName         = 'Test client'
            passwordCredentials = @(@{ keyId = 'old-key-1' }, @{ keyId = 'old-key-2' })
        }
    }
    # Records every write in order; $script:Fail decides which calls throw.
    function New-GraphPOSTRequest {
        param($uri, $body, $type)
        $Call = if ($uri -match 'addPassword') { 'add' } elseif ($uri -match 'removePassword') { "remove:$(($body | ConvertFrom-Json).keyId)" } else { 'other' }
        $script:Calls.Add($Call)
        $Error = & $script:Fail $Call
        if ($Error) { throw $Error }
        if ($Call -eq 'add') { return @{ secretText = 'new-secret' } }
    }
    # The pre-fix code cleared the old secrets and added the new one in a single batch.
    function New-GraphBulkRequest {
        param($Requests)
        foreach ($Request in $Requests) { $script:Calls.Add($Request.id) }
        $Error = & $script:Fail 'add'
        if ($Error) { return @(@{ id = 'removeOldPasswords'; status = 204 }, @{ id = 'addNewPassword'; status = 409; body = @{ error = @{ message = $Error } } }) }
        @(@{ id = 'removeOldPasswords'; status = 204 }, @{ id = 'addNewPassword'; status = 200; body = @{ secretText = 'new-secret' } })
    }

    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Authentication/New-CIPPAPIConfig.ps1')
    $env:TenantID = 'partner-tenant'
    $script:Concurrent = 'Error due to concurrent requests being made to the tenant. Please wait briefly and retry.'
}

Describe 'New-CIPPAPIConfig -ResetSecret' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        $script:Fail = { }
    }

    It 'adds the new secret before removing the old ones' {
        $Result = New-CIPPAPIConfig -ResetSecret -AppId 'app-id'
        $Result.ApplicationSecret | Should -Be 'new-secret'
        $Calls | Should -Be @('add', 'remove:old-key-1', 'remove:old-key-2')
        $Result.Results | Should -BeNullOrEmpty
    }

    It 'retries a concurrent-requests error on the add' {
        $script:AddAttempts = 0
        $script:Fail = { param($Call) if ($Call -eq 'add') { $script:AddAttempts++; if ($script:AddAttempts -lt 3) { $script:Concurrent } } }
        $Result = New-CIPPAPIConfig -ResetSecret -AppId 'app-id'
        $Result.ApplicationSecret | Should -Be 'new-secret'
        $AddAttempts | Should -Be 3
    }

    It 'removes nothing when the add fails for good' {
        $script:Fail = { param($Call) if ($Call -eq 'add') { $script:Concurrent } }
        { New-CIPPAPIConfig -ResetSecret -AppId 'app-id' } | Should -Throw '*concurrent requests*'
        @($Calls | Where-Object { $_ -like 'remove*' }).Count | Should -Be 0
    }

    It 'returns the new secret with a warning when an old secret cannot be removed' {
        $script:Fail = { param($Call) if ($Call -eq 'remove:old-key-2') { 'Insufficient privileges' } }
        $Result = New-CIPPAPIConfig -ResetSecret -AppId 'app-id'
        $Result.ApplicationSecret | Should -Be 'new-secret'
        $Result.Results.state | Should -Be 'warning'
        $Result.Results.resultText | Should -Match '1 old secret'
    }
}
