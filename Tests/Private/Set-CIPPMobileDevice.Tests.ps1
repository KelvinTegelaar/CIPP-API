BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPMobileDevice.ps1')

    function New-ExoRequest { param($tenant, $tenantid, $cmdlet, $cmdParams, $UseSystemMailbox) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
}

Describe 'Set-CIPPMobileDevice' {
    It 'returns the success message when Exchange accepts the change' {
        Mock New-ExoRequest { }
        Set-CIPPMobileDevice -UserId 'user@contoso.com' -DeviceId 'dev-1' -Quarantine 'true' -TenantFilter 'contoso.com' | Should -Be 'Blocked Active Sync Device for user@contoso.com'
    }

    It 'throws the failure message instead of returning it: <Name>' -ForEach @(
        @{ Name = 'block'; Params = @{ Quarantine = 'true' }; Message = 'Failed to Block Active Sync Device for user@contoso.com: denied' }
        @{ Name = 'allow'; Params = @{ Quarantine = 'false' }; Message = 'Failed to Allow Active Sync Device for user@contoso.com: denied' }
        @{ Name = 'delete'; Params = @{ Delete = 'true'; Guid = 'guid-1' }; Message = 'Failed to delete Mobile Device guid-1: denied' }
    ) {
        Mock New-ExoRequest { throw 'denied' }
        { Set-CIPPMobileDevice -UserId 'user@contoso.com' -DeviceId 'dev-1' -TenantFilter 'contoso.com' @Params } | Should -Throw $Message
    }
}
