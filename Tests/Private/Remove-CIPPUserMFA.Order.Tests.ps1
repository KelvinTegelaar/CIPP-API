# Graph refuses to delete the user's default MFA method while other methods remain, and a mobile phone while an
# alternate mobile remains. Removing every method has to order the deletes around both rules.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Remove-CIPPUserMFA.ps1')

    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp)
        if ($uri -like '*signInPreferences') { return [pscustomobject]@{ userPreferredMethodForSecondaryAuthentication = $script:Default } }
        @($script:Methods)
    }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $AsApp)
        if ($type -eq 'PATCH') { $script:Default = ($body | ConvertFrom-Json).userPreferredMethodForSecondaryAuthentication; return }
        $Id = ($uri -split '/')[-1]
        $Method = @($script:Methods).Where({ $_.id -eq $Id })[0]
        $Others = @($script:Methods).Where({ $_.id -ne $Id -and $_.'@odata.type' -ne '#microsoft.graph.passwordAuthenticationMethod' })
        $IsDefault = switch ($script:Default) {
            'push' { $Method.'@odata.type' -eq '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' }
            'sms' { $Method.phoneType -eq 'mobile' }
            'voiceMobile' { $Method.phoneType -eq 'mobile' }
            'voiceAlternateMobile' { $Method.phoneType -eq 'alternateMobile' }
            default { $false }
        }
        if ($IsDefault -and $Others.Count -gt 0) { throw "matches the user's current default authentication method" }
        if ($Method.phoneType -eq 'mobile' -and $Others.Where({ $_.phoneType -eq 'alternateMobile' }).Count -gt 0) { throw 'Cannot delete mobile number without first deleting alternate mobile number.' }
        $script:Deleted.Add($Method.id)
        $script:Methods = @($script:Methods).Where({ $_.id -ne $Id })
    }
    function New-Method($Id, $Type, $PhoneType) {
        [pscustomobject]@{ id = $Id; '@odata.type' = "#microsoft.graph.$Type"; phoneType = $PhoneType }
    }
}

Describe 'Remove-CIPPUserMFA delete order' {
    BeforeEach {
        $script:Deleted = [System.Collections.Generic.List[string]]::new()
        $script:Methods = @(
            New-Method 'pw' 'passwordAuthenticationMethod'
            New-Method 'm' 'phoneAuthenticationMethod' 'mobile'
            New-Method 'alt' 'phoneAuthenticationMethod' 'alternateMobile'
            New-Method 'off' 'phoneAuthenticationMethod' 'office'
            New-Method 'app' 'microsoftAuthenticatorAuthenticationMethod'
        )
    }

    It 'removes every method when the default is <Default>' -ForEach @(
        @{ Default = 'sms'; Last = 'm' }
        @{ Default = 'push'; Last = 'app' }
        @{ Default = 'voiceAlternateMobile'; Last = 'm' }
        @{ Default = $null; Last = 'm' }
    ) {
        $script:Default = $Default
        Remove-CIPPUserMFA -UserPrincipalName 'user@contoso.com' -TenantFilter 'contoso.com' | Should -Match 'Successfully removed'
        $script:Deleted | Should -HaveCount 4
        $script:Deleted[-1] | Should -Be $Last
    }

    It 'still removes a single chosen method as asked' {
        $script:Default = 'sms'
        Remove-CIPPUserMFA -UserPrincipalName 'user@contoso.com' -TenantFilter 'contoso.com' -MethodId 'off' | Should -Match 'Successfully removed'
        $script:Deleted | Should -Be @('off')
    }
}
