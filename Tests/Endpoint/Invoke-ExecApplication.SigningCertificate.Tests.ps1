# Pester tests for the SAML token signing certificate actions on Invoke-ExecApplication.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function New-GraphGetRequest { param($Uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($Uri, $Type, $Body, $tenantid, $AsApp, $AddedHeaders) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $AsApp) }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval/Invoke-ExecApplication.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    # A stand-in public key; the thumbprint Graph uses is the SHA-1 of the key bytes.
    $script:KeyBytes = [byte[]](1..48)
    $script:KeyB64 = [Convert]::ToBase64String($script:KeyBytes)
    $script:Thumb = ([System.BitConverter]::ToString([System.Security.Cryptography.SHA1]::HashData($script:KeyBytes)) -replace '-', '')
    # A second, non-preferred signing cert (Verify + Sign + PFX password sharing one customKeyIdentifier).
    $script:OldKeyBytes = [byte[]](49..96)
    $script:OldThumb = ([System.BitConverter]::ToString([System.Security.Cryptography.SHA1]::HashData($script:OldKeyBytes)) -replace '-', '')
    function New-SpWithSigningKeys {
        [pscustomobject]@{
            displayName                        = 'test'
            preferredTokenSigningKeyThumbprint = $script:Thumb
            keyCredentials                     = @(
                [pscustomobject]@{ keyId = 'k-sign'; type = 'AsymmetricX509Cert'; usage = 'Sign'; customKeyIdentifier = 'AAAA'; key = $null }
                [pscustomobject]@{ keyId = 'k-verify'; type = 'AsymmetricX509Cert'; usage = 'Verify'; displayName = 'CN=x'; customKeyIdentifier = 'AAAA'; key = $script:KeyB64; startDateTime = '2026-01-01T00:00:00Z'; endDateTime = '2029-01-01T00:00:00Z' }
                [pscustomobject]@{ keyId = 'old-sign'; type = 'AsymmetricX509Cert'; usage = 'Sign'; customKeyIdentifier = 'BBBB'; key = $null }
                [pscustomobject]@{ keyId = 'old-verify'; type = 'AsymmetricX509Cert'; usage = 'Verify'; displayName = 'CN=old'; customKeyIdentifier = 'BBBB'; key = [Convert]::ToBase64String($script:OldKeyBytes); startDateTime = '2023-01-01T00:00:00Z'; endDateTime = '2026-01-01T00:00:00Z' }
            )
            passwordCredentials                = @(
                [pscustomobject]@{ keyId = 'k-sign'; customKeyIdentifier = 'AAAA'; secretText = $null }
                [pscustomobject]@{ keyId = 'old-sign'; customKeyIdentifier = 'BBBB'; secretText = $null }
            )
        }
    }

    function New-Request {
        param([hashtable]$Body)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecApplication' }
            Headers = @{}
            Query   = [pscustomobject]@{}
            Body    = [pscustomobject]((@{ Id = 'sp-1'; Type = 'servicePrincipals'; tenantFilter = 'contoso.onmicrosoft.com' }, $Body) | ForEach-Object -Begin { $m = @{} } -Process { foreach ($k in $_.Keys) { $m[$k] = $_[$k] } } -End { $m })
        }
    }
}

Describe 'ListSigningCertificates' {
    It 'derives SHA-1 thumbprints from the Verify key and flags the preferred one' {
        Mock New-GraphGetRequest -MockWith { New-SpWithSigningKeys }

        $Response = Invoke-ExecApplication -Request (New-Request @{ Action = 'ListSigningCertificates' })

        $Response.StatusCode | Should -Be 200
        @($Response.Body.Results).Count | Should -Be 2
        ($Response.Body.Results | Where-Object thumbprint -EQ $script:Thumb).preferred | Should -BeTrue
        ($Response.Body.Results | Where-Object thumbprint -EQ $script:OldThumb).preferred | Should -BeFalse
        $Response.Body.Results[0].PSObject.Properties.Name | Should -Not -Contain 'customKeyIdentifier'
        $Response.Body.Metadata.Preferred | Should -Be $script:Thumb
    }
}

Describe 'AddSigningCertificate' {
    BeforeEach {
        $script:Posts = [System.Collections.Generic.List[object]]::new()
        # No lifetime policy unless a test says otherwise.
        Mock New-GraphGetRequest -MockWith { param($Uri) if ($Uri -match 'defaultAppManagementPolicy') { [pscustomobject]@{ isEnabled = $true } } else { @() } }
        Mock New-GraphPOSTRequest -MockWith {
            param($Uri, $Type, $Body)
            $script:Posts.Add(@{ Uri = $Uri; Type = $Type; Body = $Body })
            [pscustomobject]@{ keyId = 'k1'; thumbprint = $script:Thumb; displayName = 'CN=x'; startDateTime = '2026-01-01T00:00:00Z'; endDateTime = '2029-01-01T00:00:00Z' }
        }
    }

    It 'defaults the subject to the Entra convention and a 3 year expiry when no policy caps it' {
        $Response = Invoke-ExecApplication -Request (New-Request @{ Action = 'AddSigningCertificate' })

        $Response.StatusCode | Should -Be 200
        $script:Posts.Count | Should -Be 1
        $script:Posts[0].Uri | Should -Be 'https://graph.microsoft.com/beta/servicePrincipals/sp-1/addTokenSigningCertificate'
        $script:Posts[0].Body | Should -Match '"displayName":"CN=Microsoft Azure Federated SSO Certificate"'
        $End = [DateTimeOffset]::Parse(($script:Posts[0].Body | ConvertFrom-Json -AsHashtable).endDateTime)
        ($End - [DateTimeOffset]::UtcNow).TotalDays | Should -BeGreaterThan (3 * 365 - 2)
        $Response.Body.Results.details[0].thumbprint | Should -Be $script:Thumb
    }

    It 'caps the default expiry at the tenant app management policy lifetime' {
        Mock New-GraphGetRequest -MockWith {
            param($Uri)
            if ($Uri -match 'defaultAppManagementPolicy') {
                [pscustomobject]@{ isEnabled = $true; servicePrincipalRestrictions = [pscustomobject]@{ keyCredentials = @([pscustomobject]@{ restrictionType = 'asymmetricKeyLifetime'; state = 'enabled'; maxLifetime = 'P999D' }) } }
            } else { @() }
        }

        $null = Invoke-ExecApplication -Request (New-Request @{ Action = 'AddSigningCertificate' })

        $End = [DateTimeOffset]::Parse(($script:Posts[0].Body | ConvertFrom-Json -AsHashtable).endDateTime)
        $Days = ($End - [DateTimeOffset]::UtcNow).TotalDays
        $Days | Should -BeLessThan 999
        $Days | Should -BeGreaterThan 996
    }

    It 'prefixes CN= and converts a unix-seconds expiry to ISO UTC' {
        $null = Invoke-ExecApplication -Request (New-Request @{ Action = 'AddSigningCertificate'; DisplayName = 'Meraki SSO'; EndDateTime = 1893456000 })

        $script:Posts[0].Body | Should -Match '"displayName":"CN=Meraki SSO"'
        $script:Posts[0].Body | Should -Match '"endDateTime":"2030-01-01T00:00:00Z"'
    }

    It 'refuses applications' {
        $Response = Invoke-ExecApplication -Request (New-Request @{ Action = 'AddSigningCertificate'; Type = 'applications' })

        $Response.StatusCode | Should -Be 500
        $script:Posts.Count | Should -Be 0
    }
}

Describe 'SetPreferredSigningKey' {
    BeforeEach {
        $script:Posts = [System.Collections.Generic.List[object]]::new()
        Mock New-GraphGetRequest -MockWith { New-SpWithSigningKeys }
        Mock New-GraphPOSTRequest -MockWith { param($Uri, $Type, $Body) $script:Posts.Add(@{ Uri = $Uri; Type = $Type; Body = $Body }) }
    }

    It 'PATCHes preferredTokenSigningKeyThumbprint for a registered Verify key, case-insensitively' {
        $Response = Invoke-ExecApplication -Request (New-Request @{ Action = 'SetPreferredSigningKey'; Thumbprint = $script:Thumb.ToLower() })

        $Response.StatusCode | Should -Be 200
        $script:Posts.Count | Should -Be 1
        $script:Posts[0].Type | Should -Be 'PATCH'
        $script:Posts[0].Uri | Should -Be 'https://graph.microsoft.com/beta/servicePrincipals/sp-1'
        ($script:Posts[0].Body | ConvertFrom-Json).preferredTokenSigningKeyThumbprint | Should -Be $script:Thumb
    }

    It 'accepts the picker wrapper object' {
        $null = Invoke-ExecApplication -Request (New-Request @{ Action = 'SetPreferredSigningKey'; Thumbprint = @{ label = 'x'; value = $script:Thumb } })

        $script:Posts.Count | Should -Be 1
    }

    It 'rejects a thumbprint that is not on the service principal without writing' {
        $Response = Invoke-ExecApplication -Request (New-Request @{ Action = 'SetPreferredSigningKey'; Thumbprint = ('A' * 40) })

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results[0].resultText | Should -Match 'No signing certificate'
        $script:Posts.Count | Should -Be 0
    }

    It 'rejects a malformed thumbprint' {
        $Response = Invoke-ExecApplication -Request (New-Request @{ Action = 'SetPreferredSigningKey'; Thumbprint = 'not-a-thumbprint' })

        $Response.StatusCode | Should -Be 500
        $script:Posts.Count | Should -Be 0
    }
}

Describe 'RemoveSigningCertificate' {
    BeforeEach {
        $script:Posts = [System.Collections.Generic.List[object]]::new()
        Mock New-GraphGetRequest -MockWith { New-SpWithSigningKeys }
        Mock New-GraphPOSTRequest -MockWith { param($Uri, $Type, $Body) $script:Posts.Add(@{ Uri = $Uri; Type = $Type; Body = $Body }) }
    }

    It 'drops the Verify key, Sign key and PFX password that share the customKeyIdentifier, nulling retained key material' {
        $Response = Invoke-ExecApplication -Request (New-Request @{ Action = 'RemoveSigningCertificate'; Thumbprint = $script:OldThumb })

        $Response.StatusCode | Should -Be 200
        $script:Posts.Count | Should -Be 1
        $script:Posts[0].Type | Should -Be 'PATCH'
        $Parsed = $script:Posts[0].Body | ConvertFrom-Json
        @($Parsed.keyCredentials).keyId | Sort-Object | Should -Be @('k-sign', 'k-verify')
        @($Parsed.passwordCredentials).keyId | Should -Be @('k-sign')
        @($Parsed.keyCredentials | Where-Object { $null -ne $_.key }).Count | Should -Be 0
        $script:Posts[0].Body | Should -Match '"keyCredentials":\['
        $script:Posts[0].Body | Should -Match '"passwordCredentials":\['
    }

    It 'refuses to remove the preferred certificate' {
        $Response = Invoke-ExecApplication -Request (New-Request @{ Action = 'RemoveSigningCertificate'; Thumbprint = $script:Thumb })

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results[0].resultText | Should -Match 'preferred'
        $script:Posts.Count | Should -Be 0
    }
}
