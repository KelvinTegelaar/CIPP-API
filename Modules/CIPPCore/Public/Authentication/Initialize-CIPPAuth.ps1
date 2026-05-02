function Initialize-CIPPAuth {
    <#
    .SYNOPSIS
    Bootstraps authentication state for CIPP.

    .DESCRIPTION
    Loads SAM credentials from Key Vault (or DevSecrets table)
    and auto-patches redirect URIs on the SAM app registration.
    #>
    [CmdletBinding()]
    param()

    $AuthState = @{
        IsConfigured      = $false
        HasKeyVault       = $false
        HasSAMCredentials = $false
        NeedsSetup        = $true
    }

    # 1. Determine Key Vault name
    $KVName = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]

    # 2. Try loading SAM credentials
    if ($KVName -or $env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        $AuthState.HasKeyVault = [bool]$KVName
        try {
            $Auth = Get-CIPPAuthentication
            if ($Auth -and $env:ApplicationID -and $env:TenantID) {
                $AuthState.HasSAMCredentials = $true
                $AuthState.NeedsSetup = $false
                $AuthState.IsConfigured = $true
                Write-Information "[Auth-Init] SAM credentials loaded (AppID: $($env:ApplicationID))"
            }
        } catch {
            Write-Information "[Auth-Init] Could not load SAM credentials: $_"
        }
    }

    # 3. Auto-patch redirect URIs if we have credentials
    if ($AuthState.HasSAMCredentials) {
        try {
            Update-CIPPSAMRedirectUri
        } catch {
            Write-Information "[Auth-Init] Redirect URI patch failed (non-fatal): $_"
        }
    }

    return $AuthState
}
