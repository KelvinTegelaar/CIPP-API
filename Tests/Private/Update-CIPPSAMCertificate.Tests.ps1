# Pester tests for Update-CIPPSAMCertificate reconcile / renew / drift / bootstrap

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $UpdatePath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Update-CIPPSAMCertificate.ps1'
    $NewCertPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPSAMCertificate.ps1'
    $VersionsPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSAMCertificateVersions.ps1'

    function Get-CIPPSAMCertificateVersions { }
    function Get-CIPPSAMCertificate { param([switch]$SkipCache) }
    function New-GraphGetRequest { }
    function New-GraphPOSTRequest { }
    function New-CIPPSAMCertificate { }
    function Set-CIPPSAMCertificate { }
    function Update-AppManagementPolicy { }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ message = $Exception.Exception.Message } }

    . $NewCertPath
    . $VersionsPath
    . $UpdatePath

    $script:CurrentCert = New-CIPPSAMCertificate -SubjectName 'CN=CIPP-SAM-Current'
    $script:PreviousCert = New-CIPPSAMCertificate -SubjectName 'CN=CIPP-SAM-Previous'
    $script:HistoricalCert = New-CIPPSAMCertificate -SubjectName 'CN=CIPP-SAM-Historical'
    $script:OrphanCert = New-CIPPSAMCertificate -SubjectName 'CN=CIPP-SAM-Orphan'
    $script:UnknownCert = New-CIPPSAMCertificate -SubjectName 'CN=Manual-Unknown'
    $script:MintedCert = New-CIPPSAMCertificate -SubjectName 'CN=CIPP-SAM-Minted'
    $script:OrphanCerts = @(1..5 | ForEach-Object { New-CIPPSAMCertificate -SubjectName "CN=CIPP-SAM-Orphan-$_" })

    $script:AppObjectId = 'app-object-id'
    $env:ApplicationID = 'sam-app-id'
    $env:WEBSITE_SITE_NAME = 'cipp-test'

    function script:New-MockCredential {
        param(
            [string]$Thumbprint,
            [string]$DisplayName,
            [string]$KeyId = ([guid]::NewGuid().ToString())
        )
        [PSCustomObject]@{
            keyId               = $KeyId
            customKeyIdentifier = $Thumbprint
            displayName         = $DisplayName
            type                = 'AsymmetricX509Cert'
            usage               = 'Verify'
            endDateTime         = (Get-Date).ToUniversalTime().AddDays(200)
        }
    }

    function script:New-MockVersions {
        param(
            $Current = $null,
            $Previous = $null,
            [string[]]$Historical = @()
        )
        $All = [System.Collections.Generic.List[string]]::new()
        if ($Current) { $All.Add($Current.Thumbprint) }
        if ($Previous) { $All.Add($Previous.Thumbprint) }
        foreach ($H in $Historical) { $All.Add($H) }
        [PSCustomObject]@{
            Current               = $Current
            Previous              = $Previous
            HistoricalThumbprints = @($Historical)
            AllKnownThumbprints   = @($All)
        }
    }
}

Describe 'Update-CIPPSAMCertificate' {
    BeforeEach {
        $script:PatchBodies = [System.Collections.Generic.List[string]]::new()
        $script:MintCalled = $false
        $script:SetCalled = $false

        Mock -CommandName Update-AppManagementPolicy -MockWith { @{ PolicyAction = $null } }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            param($type, $uri, $Body)
            $script:PatchBodies.Add([string]$Body)
        }
        Mock -CommandName New-CIPPSAMCertificate -MockWith {
            $script:MintCalled = $true
            $script:MintedCert
        }
        Mock -CommandName Set-CIPPSAMCertificate -MockWith {
            $script:SetCalled = $true
            @{ StorageMode = 'Secret'; Name = 'SAMCertificate' }
        }
    }

    It 'no-ops when current is healthy on app with no removable extras' {
        Mock -CommandName Get-CIPPSAMCertificateVersions -MockWith {
            New-MockVersions -Current $script:CurrentCert -Previous $script:PreviousCert
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                id             = $script:AppObjectId
                keyCredentials = @(
                    (New-MockCredential -Thumbprint $script:CurrentCert.Thumbprint -DisplayName 'CIPP-SAM Certificate (cipp-test)')
                    (New-MockCredential -Thumbprint $script:PreviousCert.Thumbprint -DisplayName 'CIPP-SAM Certificate (cipp-test)')
                )
            }
        }

        $Result = Update-CIPPSAMCertificate

        $Result.Renewed | Should -BeFalse
        $Result.Reconciled | Should -BeFalse
        $script:PatchBodies.Count | Should -Be 0
        $script:MintCalled | Should -BeFalse
    }

    It 'reconciles CIPP displayName orphans without minting' {
        Mock -CommandName Get-CIPPSAMCertificateVersions -MockWith {
            New-MockVersions -Current $script:CurrentCert
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            $Creds = [System.Collections.Generic.List[object]]::new()
            $Creds.Add((New-MockCredential -Thumbprint $script:CurrentCert.Thumbprint -DisplayName 'CIPP-SAM Certificate (cipp-test)'))
            foreach ($Orphan in $script:OrphanCerts) {
                $Creds.Add((New-MockCredential -Thumbprint $Orphan.Thumbprint -DisplayName "CIPP-SAM Certificate (orphan)"))
            }
            [PSCustomObject]@{ id = $script:AppObjectId; keyCredentials = @($Creds) }
        }

        $Result = Update-CIPPSAMCertificate

        $Result.Renewed | Should -BeFalse
        $Result.Reconciled | Should -BeTrue
        $Result.RemovedCount | Should -Be 5
        $script:MintCalled | Should -BeFalse
        $script:PatchBodies.Count | Should -Be 1
        $Parsed = $script:PatchBodies[0] | ConvertFrom-Json
        @($Parsed.keyCredentials).Count | Should -Be 1
        $Parsed.keyCredentials[0].customKeyIdentifier | Should -Be $script:CurrentCert.Thumbprint
    }

    It 'removes extras whose thumbprint is in HistoricalThumbprints' {
        Mock -CommandName Get-CIPPSAMCertificateVersions -MockWith {
            New-MockVersions -Current $script:CurrentCert -Historical @($script:HistoricalCert.Thumbprint)
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                id             = $script:AppObjectId
                keyCredentials = @(
                    (New-MockCredential -Thumbprint $script:CurrentCert.Thumbprint -DisplayName 'CIPP-SAM Certificate (cipp-test)')
                    (New-MockCredential -Thumbprint $script:HistoricalCert.Thumbprint -DisplayName 'Some Other Name')
                )
            }
        }

        $Result = Update-CIPPSAMCertificate

        $Result.Reconciled | Should -BeTrue
        $Result.RemovedCount | Should -Be 1
        $Parsed = $script:PatchBodies[0] | ConvertFrom-Json
        @($Parsed.keyCredentials).Count | Should -Be 1
    }

    It 'preserves unknown credentials not in KV history' {
        Mock -CommandName Get-CIPPSAMCertificateVersions -MockWith {
            New-MockVersions -Current $script:CurrentCert
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                id             = $script:AppObjectId
                keyCredentials = @(
                    (New-MockCredential -Thumbprint $script:CurrentCert.Thumbprint -DisplayName 'CIPP-SAM Certificate (cipp-test)')
                    (New-MockCredential -Thumbprint $script:UnknownCert.Thumbprint -DisplayName 'Customer Manual Cert')
                )
            }
        }

        $Result = Update-CIPPSAMCertificate

        $Result.Renewed | Should -BeFalse
        $Result.Reconciled | Should -BeFalse
        $script:PatchBodies.Count | Should -Be 0
    }

    It 're-registers current on drift without minting' {
        Mock -CommandName Get-CIPPSAMCertificateVersions -MockWith {
            New-MockVersions -Current $script:CurrentCert
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                id             = $script:AppObjectId
                keyCredentials = @(
                    (New-MockCredential -Thumbprint $script:UnknownCert.Thumbprint -DisplayName 'Customer Manual Cert')
                )
            }
        }

        $Result = Update-CIPPSAMCertificate

        $Result.Renewed | Should -BeFalse
        $Result.Reconciled | Should -BeTrue
        $Result.Drift | Should -BeTrue
        $script:MintCalled | Should -BeFalse
        $script:SetCalled | Should -BeFalse
        $Parsed = $script:PatchBodies[0] | ConvertFrom-Json
        $Keys = @($Parsed.keyCredentials)
        $Keys.Count | Should -Be 2
        ($Keys | Where-Object { $_.key -eq $script:CurrentCert.PublicKeyBase64 }).Count | Should -Be 1
    }

    It 'mints on near expiry and keeps previous current plus new' {
        $Expiring = [PSCustomObject]@{
            Certificate     = $script:CurrentCert.Certificate
            Thumbprint      = $script:CurrentCert.Thumbprint
            NotBefore       = $script:CurrentCert.NotBefore
            NotAfter        = (Get-Date).ToUniversalTime().AddDays(10)
            PfxBase64       = $script:CurrentCert.PfxBase64
            PublicKeyBase64 = $script:CurrentCert.PublicKeyBase64
        }
        Mock -CommandName Get-CIPPSAMCertificateVersions -MockWith {
            New-MockVersions -Current $Expiring -Previous $script:PreviousCert
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                id             = $script:AppObjectId
                keyCredentials = @(
                    (New-MockCredential -Thumbprint $script:CurrentCert.Thumbprint -DisplayName 'CIPP-SAM Certificate (cipp-test)')
                    (New-MockCredential -Thumbprint $script:PreviousCert.Thumbprint -DisplayName 'CIPP-SAM Certificate (cipp-test)')
                )
            }
        }

        $Result = Update-CIPPSAMCertificate

        $Result.Renewed | Should -BeTrue
        $script:MintCalled | Should -BeTrue
        $script:SetCalled | Should -BeTrue
        $Parsed = $script:PatchBodies[0] | ConvertFrom-Json
        $Keys = @($Parsed.keyCredentials)
        # Old previous dropped; old current kept; new added
        $Keys.Count | Should -Be 2
        ($Keys | Where-Object { $_.customKeyIdentifier -eq $script:CurrentCert.Thumbprint }).Count | Should -Be 1
        ($Keys | Where-Object { $_.key -eq $script:MintedCert.PublicKeyBase64 }).Count | Should -Be 1
        ($Keys | Where-Object { $_.customKeyIdentifier -eq $script:PreviousCert.Thumbprint }).Count | Should -Be 0
    }

    It 'bootstraps with no current and drops CIPP extras keeping unknowns' {
        Mock -CommandName Get-CIPPSAMCertificateVersions -MockWith {
            New-MockVersions
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                id             = $script:AppObjectId
                keyCredentials = @(
                    (New-MockCredential -Thumbprint $script:OrphanCert.Thumbprint -DisplayName 'CIPP-SAM Certificate (debris)')
                    (New-MockCredential -Thumbprint $script:UnknownCert.Thumbprint -DisplayName 'Customer Manual Cert')
                )
            }
        }

        $Result = Update-CIPPSAMCertificate

        $Result.Renewed | Should -BeTrue
        $script:MintCalled | Should -BeTrue
        $Parsed = $script:PatchBodies[0] | ConvertFrom-Json
        $Keys = @($Parsed.keyCredentials)
        $Keys.Count | Should -Be 2
        ($Keys | Where-Object { $_.customKeyIdentifier -eq $script:UnknownCert.Thumbprint }).Count | Should -Be 1
        ($Keys | Where-Object { $_.key -eq $script:MintedCert.PublicKeyBase64 }).Count | Should -Be 1
        ($Keys | Where-Object { $_.customKeyIdentifier -eq $script:OrphanCert.Thumbprint }).Count | Should -Be 0
    }

    It 'rolls back only the new key when storage fails after mint' {
        Mock -CommandName Get-CIPPSAMCertificateVersions -MockWith {
            New-MockVersions
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                id             = $script:AppObjectId
                keyCredentials = @(
                    (New-MockCredential -Thumbprint $script:UnknownCert.Thumbprint -DisplayName 'Customer Manual Cert')
                )
            }
        }
        Mock -CommandName Set-CIPPSAMCertificate -MockWith { throw 'kv failed' }

        { Update-CIPPSAMCertificate } | Should -Throw 'kv failed'
        $script:PatchBodies.Count | Should -Be 2
        $Rollback = $script:PatchBodies[1] | ConvertFrom-Json
        $Keys = @($Rollback.keyCredentials)
        ($Keys | Where-Object { $_.key -eq $script:MintedCert.PublicKeyBase64 }).Count | Should -Be 0
        ($Keys | Where-Object { $_.customKeyIdentifier -eq $script:UnknownCert.Thumbprint }).Count | Should -Be 1
    }

    It 'falls back to latest cert when versions load fails and does not mint' {
        Mock -CommandName Get-CIPPSAMCertificateVersions -MockWith { throw 'versions unavailable' }
        Mock -CommandName Get-CIPPSAMCertificate -MockWith {
            [PSCustomObject]@{
                Certificate = $script:CurrentCert.Certificate
                Thumbprint  = $script:CurrentCert.Thumbprint
                NotBefore   = $script:CurrentCert.NotBefore
                NotAfter    = $script:CurrentCert.NotAfter
            }
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                id             = $script:AppObjectId
                keyCredentials = @(
                    (New-MockCredential -Thumbprint $script:CurrentCert.Thumbprint -DisplayName 'CIPP-SAM Certificate (cipp-test)')
                )
            }
        }

        $Result = Update-CIPPSAMCertificate

        $Result.Renewed | Should -BeFalse
        $Result.Thumbprint | Should -Be $script:CurrentCert.Thumbprint
        $script:MintCalled | Should -BeFalse
        $script:PatchBodies.Count | Should -Be 0
    }

    It 'fails closed when versions and latest cert loads both fail' {
        Mock -CommandName Get-CIPPSAMCertificateVersions -MockWith { throw 'versions unavailable' }
        Mock -CommandName Get-CIPPSAMCertificate -MockWith { throw 'secret unavailable' }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{ id = $script:AppObjectId; keyCredentials = @() }
        }

        { Update-CIPPSAMCertificate } | Should -Throw -ExceptionType ([System.Exception]) -ExpectedMessage '*temporarily unavailable*'
        $script:MintCalled | Should -BeFalse
        $script:PatchBodies.Count | Should -Be 0
    }
}