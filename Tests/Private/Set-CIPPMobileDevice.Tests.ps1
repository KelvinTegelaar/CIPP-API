BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPMobileDevice.ps1')

    function New-ExoRequest { param($tenant, $tenantid, $cmdlet, $cmdParams, $UseSystemMailbox, $Anchor) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
}

Describe 'Set-CIPPMobileDevice' {
    It 'returns the success message when Exchange accepts the change' {
        Mock New-ExoRequest { }
        Set-CIPPMobileDevice -UserId 'user@contoso.com' -DeviceId 'dev-1' -Quarantine 'true' -TenantFilter 'contoso.com' | Should -Be 'Blocked Active Sync Device for user@contoso.com'
    }

    It 'takes an allowed device off the block list in the same change' {
        Mock New-ExoRequest { }
        $null = Set-CIPPMobileDevice -UserId 'user@contoso.com' -DeviceId 'dev-1' -Quarantine 'false' -TenantFilter 'contoso.com'
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdParams.ActiveSyncAllowedDeviceIDs.add -eq 'dev-1' -and $cmdParams.ActiveSyncBlockedDeviceIDs.remove -eq 'dev-1'
        }
    }

    It 'takes a blocked device off the allow list in the same change' {
        Mock New-ExoRequest { }
        $null = Set-CIPPMobileDevice -UserId 'user@contoso.com' -DeviceId 'dev-1' -Quarantine 'true' -TenantFilter 'contoso.com'
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdParams.ActiveSyncBlockedDeviceIDs.add -eq 'dev-1' -and $cmdParams.ActiveSyncAllowedDeviceIDs.remove -eq 'dev-1'
        }
    }

    It 'issues an account-only wipe for the one device' {
        Mock New-ExoRequest { }
        Set-CIPPMobileDevice -UserId 'user@contoso.com' -Guid 'guid-1' -Wipe 'true' -TenantFilter 'contoso.com' | Should -BeLike 'Issued an account-only wipe*'
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Clear-MobileDevice' -and $cmdParams.Identity -eq 'guid-1' -and $cmdParams.AccountOnly -eq $true -and -not $cmdParams.ContainsKey('Cancel')
        }
    }

    It 'cancels a pending account-only wipe' {
        Mock New-ExoRequest { }
        Set-CIPPMobileDevice -UserId 'user@contoso.com' -Guid 'guid-1' -CancelWipe 'true' -TenantFilter 'contoso.com' | Should -BeLike 'Cancelled*'
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Clear-MobileDevice' -and $cmdParams.Identity -eq 'guid-1' -and $cmdParams.Cancel -eq $true
        }
    }

    It 'throws the failure message instead of returning it: <Name>' -ForEach @(
        @{ Name = 'block'; Params = @{ Quarantine = 'true' }; Message = 'Failed to Block Active Sync Device for user@contoso.com: denied' }
        @{ Name = 'allow'; Params = @{ Quarantine = 'false' }; Message = 'Failed to Allow Active Sync Device for user@contoso.com: denied' }
        @{ Name = 'wipe'; Params = @{ Wipe = 'true'; Guid = 'guid-1' }; Message = 'Failed to wipe Mobile Device guid-1: denied' }
        @{ Name = 'cancel wipe'; Params = @{ CancelWipe = 'true'; Guid = 'guid-1' }; Message = 'Failed to cancel the wipe for Mobile Device guid-1: denied' }
        @{ Name = 'delete'; Params = @{ Delete = 'true'; Guid = 'guid-1' }; Message = 'Failed to delete Mobile Device guid-1: denied' }
    ) {
        Mock New-ExoRequest { throw 'denied' }
        { Set-CIPPMobileDevice -UserId 'user@contoso.com' -DeviceId 'dev-1' -TenantFilter 'contoso.com' @Params } | Should -Throw $Message
    }
}
