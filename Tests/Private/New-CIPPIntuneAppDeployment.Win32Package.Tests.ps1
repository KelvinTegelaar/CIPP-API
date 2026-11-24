# Pester tests for New-CIPPIntuneAppDeployment with uploaded .intunewin packages (Win32PackageApp).
# A tenant app is current when it carries the template's package marker in its notes; an older app
# is updated in place (new content version on the same app) or superseded by a new app.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $ComplexFilter) }
    function New-GraphPostRequest { [CmdletBinding()] param($uri, $tenantid, $type, $body, $AddedHeaders) }
    function Get-CIPPAppPackageStorage { [pscustomobject]@{ ConnectionString = 'UseDevelopmentStorage=true'; Custom = $false; LimitBytes = 0 } }
    function New-CIPPAzStorageRequest { [CmdletBinding()] param($Service, $ConnectionString, $Resource, $Method, $QueryParams, $ContentType, $Body, $Headers) }
    function Add-CIPPWin32LobAppContent { [CmdletBinding()] param($AppId, $BlobPath, $ConnectionString, $EncryptedSize, $FileName, $UnencryptedSize, $EncryptionInfo, $TenantFilter, $APIName, $AppProperties, $AppType) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $Sev2, $LogData) }
    function Set-CIPPAssignedApplication { [CmdletBinding()] param($GroupName, $ExcludeGroup, $ExcludeGroupIds, $ExcludeGroupNames, $Intent, $AppType, $ApplicationId, $TenantFilter, $GroupIds, $AssignmentMode, $AssignmentDirection, $APIName, $Headers, $AssignmentFilterName, $AssignmentFilterType) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPIntuneAppDeployment.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:PackageId = '6f1c2a3b-1111-2222-3333-444455556666'
    $script:Metadata = @{
        Name = 'Contoso Agent'; FileName = 'IntunePackage.intunewin'; SetupFile = 'agent.msi'; UnencryptedContentSize = 1000; EncryptedSize = 1072
        EncryptionInfo = @{ EncryptionKey = 'a2V5'; MacKey = 'bWFj'; InitializationVector = 'aXY='; Mac = 'bWFjMg=='; ProfileIdentifier = 'ProfileVersion1'; FileDigest = 'ZGln'; FileDigestAlgorithm = 'SHA256' }
        MsiInfo = @{ MsiProductCode = '{11111111-2222-3333-4444-555555555555}'; MsiProductVersion = '2.0.0'; MsiPublisher = 'Contoso'; MsiExecutionContext = 'System'; MsiRequiresReboot = 'false' }
    } | ConvertTo-Json -Depth 5

    function New-QueuedPackageApp {
        param([hashtable]$Extra = @{})
        $Config = [ordered]@{
            tenant = $script:Tenant; type = 'Win32PackageApp'; Applicationname = 'Contoso Agent'; assignTo = 'AllDevices'
            packageId = $script:PackageId; installCommandLine = 'msiexec /i "agent.msi" /qn'; uninstallCommandLine = 'msiexec /x "{11111111-2222-3333-4444-555555555555}" /qn'
            detectionType = 'msi'; returnCodes = '0=success, 3010=softReboot'
        }
        foreach ($Key in $Extra.Keys) { $Config[$Key] = $Extra[$Key] }
        return ([pscustomobject]$Config | ConvertTo-Json -Depth 15 | ConvertFrom-Json)
    }
}

Describe 'New-CIPPIntuneAppDeployment uploaded Win32 packages' {
    BeforeEach {
        $script:Posts = [System.Collections.Generic.List[object]]::new()
        $script:Existing = @()
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Set-CIPPAssignedApplication -MockWith { }
        Mock -CommandName Add-CIPPWin32LobAppContent -MockWith { '1' }
        Mock -CommandName New-CIPPAzStorageRequest -MockWith { [pscustomobject]@{ Bytes = [System.Text.Encoding]::UTF8.GetBytes($script:Metadata) } }
        Mock -CommandName New-GraphGetRequest -MockWith {
            if ($uri -like '*isof*') { return $script:Existing }
            [pscustomobject]@{ id = 'old-app'; largeIcon = [pscustomobject]@{ type = 'image/png'; value = 'aWNvbg==' } }
        }
        Mock -CommandName New-GraphPostRequest -MockWith {
            $script:Posts.Add([pscustomobject]@{ Uri = $uri; Type = $type; Body = $body })
            if ($type -eq 'POST' -and $uri -like '*/mobileApps') { return [pscustomobject]@{ id = 'new-app' } }
        }
    }

    It 'creates the app with the package marker, MSI detection and the parsed return codes, then uploads and assigns it' {
        $Result = New-CIPPIntuneAppDeployment -AppConfig (New-QueuedPackageApp) -TenantFilter $script:Tenant

        $Result.id | Should -Be 'new-app'
        $Body = $script:Posts.Where({ $_.Type -eq 'POST' -and $_.Uri -like '*/mobileApps' })[0].Body | ConvertFrom-Json
        $Body.notes | Should -Be "Package: $($script:PackageId)"
        $Body.setupFilePath | Should -Be 'agent.msi'
        $Body.rules[0].'@odata.type' | Should -Be '#microsoft.graph.win32LobAppProductCodeRule'
        $Body.rules[0].productCode | Should -Be '{11111111-2222-3333-4444-555555555555}'
        $Body.msiInformation.packageType | Should -Be 'perMachine'
        @($Body.returnCodes).returnCode | Should -Be @(0, 3010)
        Should -Invoke Add-CIPPWin32LobAppContent -Times 1 -ParameterFilter { $AppId -eq 'new-app' -and $ConnectionString -eq 'UseDevelopmentStorage=true' -and $BlobPath -eq "app-packages/$($script:PackageId)/IntunePackage.intunewin" -and $EncryptedSize -eq 1072 }
        Should -Invoke Set-CIPPAssignedApplication -Times 1 -ParameterFilter { $ApplicationId -eq 'new-app' }
    }

    It 'skips a tenant whose app already carries this package' {
        $script:Existing = @([pscustomobject]@{ id = 'old-app'; displayName = 'Contoso Agent'; notes = "Package: $($script:PackageId)"; createdDateTime = '2026-01-01T00:00:00Z' })

        $Result = New-CIPPIntuneAppDeployment -AppConfig (New-QueuedPackageApp) -TenantFilter $script:Tenant

        $Result | Should -BeNullOrEmpty
        Should -Invoke Add-CIPPWin32LobAppContent -Times 0
        $script:Posts.Count | Should -Be 0
    }

    It 'updates an older app in place, keeping its icon, without creating or reassigning anything' {
        $script:Existing = @([pscustomobject]@{ id = 'old-app'; displayName = 'Contoso Agent'; notes = 'Package: 00000000-0000-0000-0000-000000000000'; createdDateTime = '2026-01-01T00:00:00Z' })

        $Result = New-CIPPIntuneAppDeployment -AppConfig (New-QueuedPackageApp) -TenantFilter $script:Tenant

        $Result.id | Should -Be 'old-app'
        Should -Invoke Add-CIPPWin32LobAppContent -Times 1 -ParameterFilter {
            $AppId -eq 'old-app' -and $AppProperties.notes -eq "Package: $($script:PackageId)" -and $AppProperties.largeIcon.value -eq 'aWNvbg=='
        }
        $script:Posts.Count | Should -Be 0
        Should -Invoke Set-CIPPAssignedApplication -Times 0
    }

    It 'supersedes an older app with a new one and moves targeting off the old app' {
        $script:Existing = @([pscustomobject]@{ id = 'old-app'; displayName = 'Contoso Agent'; notes = $null; createdDateTime = '2026-01-01T00:00:00Z' })

        $Result = New-CIPPIntuneAppDeployment -AppConfig (New-QueuedPackageApp -Extra @{ updateMode = 'supersede'; supersedenceType = 'replace' }) -TenantFilter $script:Tenant

        $Result.id | Should -Be 'new-app'
        $Relationship = ($script:Posts.Where({ $_.Uri -like '*/new-app/updateRelationships' })[0].Body | ConvertFrom-Json).relationships[0]
        $Relationship.targetId | Should -Be 'old-app'
        $Relationship.supersedenceType | Should -Be 'replace'
        $script:Posts.Where({ $_.Uri -like '*/old-app/assign' })[0].Body | Should -Be '{"mobileAppAssignments":[]}'
        Should -Invoke Set-CIPPAssignedApplication -Times 1 -ParameterFilter { $ApplicationId -eq 'new-app' }
    }

    It 'deletes a newly created app when its content upload fails' {
        Mock -CommandName Add-CIPPWin32LobAppContent -MockWith { throw 'commitFileFailed' }

        { New-CIPPIntuneAppDeployment -AppConfig (New-QueuedPackageApp) -TenantFilter $script:Tenant } | Should -Throw '*commitFileFailed*'

        $script:Posts.Where({ $_.Type -eq 'DELETE' -and $_.Uri -like '*/new-app' }).Count | Should -Be 1
    }

    It 'explains when the package is no longer in CIPP storage' {
        Mock -CommandName New-CIPPAzStorageRequest -MockWith { }

        { New-CIPPIntuneAppDeployment -AppConfig (New-QueuedPackageApp) -TenantFilter $script:Tenant } | Should -Throw '*no longer in CIPP storage*'
    }
}

Describe 'New-CIPPIntuneAppDeployment uploaded macOS packages' {
    BeforeEach {
        $script:Posts = [System.Collections.Generic.List[object]]::new()
        $script:Existing = @()
        $script:FileName = 'Dialog.pkg'
        $script:ExistingBundleId = 'au.csiro.dialog'
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Set-CIPPAssignedApplication -MockWith { }
        Mock -CommandName Add-CIPPWin32LobAppContent -MockWith { '1' }
        Mock -CommandName New-CIPPAzStorageRequest -MockWith {
            $Meta = @{ Name = $script:FileName; FileName = $script:FileName; UnencryptedContentSize = 1000; EncryptedSize = 1072; EncryptionInfo = @{ EncryptionKey = 'a2V5'; MacKey = 'bWFj' } } | ConvertTo-Json
            [pscustomobject]@{ Bytes = [System.Text.Encoding]::UTF8.GetBytes($Meta) }
        }
        Mock -CommandName New-GraphGetRequest -MockWith { if ($uri -like '*isof*') { return $script:Existing }; [pscustomobject]@{ id = 'old-app'; primaryBundleId = $script:ExistingBundleId } }
        Mock -CommandName New-GraphPostRequest -MockWith {
            $script:Posts.Add([pscustomobject]@{ Uri = $uri; Type = $type; Body = $body })
            if ($type -eq 'POST' -and $uri -like '*/mobileApps') { return [pscustomobject]@{ id = 'new-app' } }
        }
        function New-QueuedMacApp {
            param([hashtable]$Extra = @{})
            $Config = [ordered]@{
                tenant = $script:Tenant; type = 'MacOSPackageApp'; Applicationname = 'Dialog'; assignTo = 'AllDevices'; packageId = $script:PackageId
                primaryBundleId = 'au.csiro.dialog'; primaryBundleVersion = '3.1.1'; includedApps = "com.example.helper 1.0"
                minimumMacOS = 'v13_0'; preInstallScript = "#!/bin/sh`necho pre"
            }
            foreach ($Key in $Extra.Keys) { $Config[$Key] = $Extra[$Key] }
            return ([pscustomobject]$Config | ConvertTo-Json -Depth 15 | ConvertFrom-Json)
        }
    }

    It 'creates a PKG app with its bundle identity, minimum macOS, scripts and the package marker' {
        $Result = New-CIPPIntuneAppDeployment -AppConfig (New-QueuedMacApp) -TenantFilter $script:Tenant

        $Result.id | Should -Be 'new-app'
        $Body = $script:Posts.Where({ $_.Type -eq 'POST' -and $_.Uri -like '*/mobileApps' })[0].Body | ConvertFrom-Json
        $Body.'@odata.type' | Should -Be '#microsoft.graph.macOSPkgApp'
        $Body.primaryBundleId | Should -Be 'au.csiro.dialog'
        $Body.primaryBundleVersion | Should -Be '3.1.1'
        # The primary app is always one of the included apps, listed first.
        @($Body.includedApps).bundleId | Should -Be @('au.csiro.dialog', 'com.example.helper')
        $Body.minimumSupportedOperatingSystem.v13_0 | Should -BeTrue
        [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Body.preInstallScript.scriptContent)) | Should -Be "#!/bin/sh`necho pre"
        $Body.notes | Should -Be "Package: $($script:PackageId)"
        Should -Invoke Add-CIPPWin32LobAppContent -Times 1 -ParameterFilter { $AppId -eq 'new-app' -and $AppType -eq 'macOSPkgApp' }
        Should -Invoke Set-CIPPAssignedApplication -Times 1 -ParameterFilter { $ApplicationId -eq 'new-app' -and -not $AppType }
    }

    It 'creates a DMG app, which has no install scripts' {
        $script:FileName = 'Rectangle.dmg'

        $null = New-CIPPIntuneAppDeployment -AppConfig (New-QueuedMacApp) -TenantFilter $script:Tenant

        $Body = $script:Posts.Where({ $_.Type -eq 'POST' -and $_.Uri -like '*/mobileApps' })[0].Body | ConvertFrom-Json
        $Body.'@odata.type' | Should -Be '#microsoft.graph.macOSDmgApp'
        $Body.PSObject.Properties.Name | Should -Not -Contain 'preInstallScript'
        Should -Invoke Add-CIPPWin32LobAppContent -Times 1 -ParameterFilter { $AppType -eq 'macOSDmgApp' }
    }

    It 'updates an older macOS app in place even when the template asks to supersede' {
        $script:Existing = @([pscustomobject]@{ id = 'old-app'; displayName = 'Dialog'; notes = 'Package: 00000000-0000-0000-0000-000000000000'; createdDateTime = '2026-01-01T00:00:00Z' })

        $Result = New-CIPPIntuneAppDeployment -AppConfig (New-QueuedMacApp -Extra @{ updateMode = 'supersede'; primaryBundleVersion = '3.2.0' }) -TenantFilter $script:Tenant

        $Result.id | Should -Be 'old-app'
        Should -Invoke Add-CIPPWin32LobAppContent -Times 1 -ParameterFilter { $AppId -eq 'old-app' -and $AppProperties.primaryBundleVersion -eq '3.2.0' -and $AppType -eq 'macOSPkgApp' }
        $script:Posts.Where({ $_.Uri -like '*updateRelationships' }).Count | Should -Be 0
    }

    It 'refuses to update an existing macOS app with a package for a different bundle ID' {
        $script:Existing = @([pscustomobject]@{ id = 'old-app'; displayName = 'Dialog'; notes = 'Package: 00000000-0000-0000-0000-000000000000'; createdDateTime = '2026-01-01T00:00:00Z' })
        $script:ExistingBundleId = 'com.other.app'

        { New-CIPPIntuneAppDeployment -AppConfig (New-QueuedMacApp) -TenantFilter $script:Tenant } | Should -Throw '*same bundle ID*'

        Should -Invoke Add-CIPPWin32LobAppContent -Times 0
    }
}
