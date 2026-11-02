# App- and user-initiated audit log presets in frontend/src/data/AuditLogTemplates.json, run through
# the same condition builder and AND-join that Test-CIPPAuditLogRules uses, against records shaped
# like the engine's output (CIPPAddedKeyTypes is computed there from KeyDescription).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Test-CIPPConditionFilter.ps1')
    $TemplatePath = Join-Path (Split-Path -Parent $RepoRoot) 'frontend/src/data/AuditLogTemplates.json'
    $script:Templates = Get-Content -Path $TemplatePath -Raw | ConvertFrom-Json

    function Get-PresetFilter {
        param([string]$Preset)
        $Template = $script:Templates.Where({ $_.value -eq $Preset })[0]
        if (-not $Template) { throw "Preset $Preset not found" }
        $Strings = foreach ($Condition in $Template.template.conditions) {
            $Sanitized = Test-CIPPConditionFilter -Condition $Condition
            if ($null -eq $Sanitized) { throw "Preset $Preset has a condition the filter rejects: $($Condition.Property.label)" }
            $Sanitized
        }
        [scriptblock]::Create($Strings -join ' -and ')
    }

    function New-Record {
        param([string]$Operation, [string]$UserId, [string]$AddedKeyTypes)
        $Record = [pscustomobject]@{ Operation = $Operation; UserId = $UserId }
        if ($AddedKeyTypes) {
            $Record.PSObject.Properties.Add([psnoteproperty]::new('CIPPAddedKeyTypes', $AddedKeyTypes))
        }
        $Record
    }

    $script:AppActor = 'ServicePrincipal_6f1c2a4e-1b0e-4f6e-9a55-0d6a3f1e2b7c'
    $script:UserActor = 'admin@contoso.com'
    $script:AppCredentialOperation = "Update application $([char]0x2013) Certificates and secrets management "
}

Describe 'App-initiated audit log presets' {
    It '<Preset> matches when an app does it' -ForEach @(
        @{ Preset = 'AppAddedSecretToServicePrincipal'; Operation = 'Add service principal credentials.'; Key = 'Password' }
        @{ Preset = 'AppAddedCertificateToServicePrincipal'; Operation = 'Add service principal credentials.'; Key = 'AsymmetricX509Cert' }
        @{ Preset = 'AppAddedSecretToAppRegistration'; Operation = 'AppCredential'; Key = 'Password' }
        @{ Preset = 'AppAddedCertificateToAppRegistration'; Operation = 'AppCredential'; Key = 'AsymmetricX509Cert' }
        # A key supplied in the create request is logged under Create rather than Update.
        @{ Preset = 'AppAddedSecretToAppRegistration'; Operation = "Create application $([char]0x2013) Certificates and secrets management "; Key = 'Password' }
        @{ Preset = 'AppAddedCertificateToAppRegistration'; Operation = "Create application $([char]0x2013) Certificates and secrets management "; Key = 'AsymmetricX509Cert' }
        @{ Preset = 'AppGrantedApplicationPermission'; Operation = 'Add app role assignment to service principal.' }
        @{ Preset = 'AppGrantedDelegatedPermission'; Operation = 'Add delegated permission grant.' }
        @{ Preset = 'AppAddedOwnerToApp'; Operation = 'Add owner to application.' }
        @{ Preset = 'AppAddedOwnerToApp'; Operation = 'Add owner to service principal.' }
        @{ Preset = 'AppAddedDirectoryRoleMember'; Operation = 'Add member to role.' }
    ) {
        $Op = if ($Operation -eq 'AppCredential') { $script:AppCredentialOperation } else { $Operation }
        $Filter = Get-PresetFilter -Preset $Preset

        @(@(New-Record -Operation $Op -UserId $script:AppActor -AddedKeyTypes $Key).Where($Filter)).Count | Should -Be 1
        @(@(New-Record -Operation $Op -UserId $script:UserActor -AddedKeyTypes $Key).Where($Filter)).Count | Should -Be 0
    }

    It '<Preset> ignores a credential change that added no key' -ForEach @(
        @{ Preset = 'AppAddedSecretToAppRegistration' }
        @{ Preset = 'AppAddedCertificateToAppRegistration' }
    ) {
        $Filter = Get-PresetFilter -Preset $Preset
        $Removal = New-Record -Operation $script:AppCredentialOperation -UserId $script:AppActor
        $Removal.PSObject.Properties.Add([psnoteproperty]::new('CIPPAddedKeyTypes', ''))
        @(@($Removal).Where($Filter)).Count | Should -Be 0
    }

    It 'separates secrets from certificates' {
        $SecretFilter = Get-PresetFilter -Preset 'AppAddedSecretToServicePrincipal'
        $CertFilter = Get-PresetFilter -Preset 'AppAddedCertificateToServicePrincipal'
        $CertRecord = New-Record -Operation 'Add service principal credentials.' -UserId $script:AppActor -AddedKeyTypes 'AsymmetricX509Cert'

        @(@($CertRecord).Where($SecretFilter)).Count | Should -Be 0
        @(@($CertRecord).Where($CertFilter)).Count | Should -Be 1
    }

    It 'does not match owners added to groups' {
        $Filter = Get-PresetFilter -Preset 'AppAddedOwnerToApp'
        @(@(New-Record -Operation 'Add owner to group.' -UserId $script:AppActor).Where($Filter)).Count | Should -Be 0
    }
}

Describe 'User-initiated audit log presets' {
    It '<Preset> matches when a user does it' -ForEach @(
        @{ Preset = 'UserAddedSecretToServicePrincipal'; Operation = 'Add service principal credentials.'; Key = 'Password' }
        @{ Preset = 'UserAddedCertificateToServicePrincipal'; Operation = 'Add service principal credentials.'; Key = 'AsymmetricX509Cert' }
        @{ Preset = 'UserAddedSecretToAppRegistration'; Operation = 'AppCredential'; Key = 'Password' }
        @{ Preset = 'UserAddedCertificateToAppRegistration'; Operation = 'AppCredential'; Key = 'AsymmetricX509Cert' }
        @{ Preset = 'UserAddedSecretToAppRegistration'; Operation = "Create application $([char]0x2013) Certificates and secrets management "; Key = 'Password' }
        @{ Preset = 'UserAddedCertificateToAppRegistration'; Operation = "Create application $([char]0x2013) Certificates and secrets management "; Key = 'AsymmetricX509Cert' }
        @{ Preset = 'UserGrantedApplicationPermission'; Operation = 'Add app role assignment to service principal.' }
        @{ Preset = 'UserGrantedDelegatedPermission'; Operation = 'Add delegated permission grant.' }
        @{ Preset = 'UserAddedOwnerToApp'; Operation = 'Add owner to application.' }
        @{ Preset = 'UserAddedOwnerToApp'; Operation = 'Add owner to service principal.' }
        @{ Preset = 'UserAddedDirectoryRoleMember'; Operation = 'Add member to role.' }
    ) {
        $Op = if ($Operation -eq 'AppCredential') { $script:AppCredentialOperation } else { $Operation }
        $Filter = Get-PresetFilter -Preset $Preset

        @(@(New-Record -Operation $Op -UserId $script:UserActor -AddedKeyTypes $Key).Where($Filter)).Count | Should -Be 1
        @(@(New-Record -Operation $Op -UserId $script:AppActor -AddedKeyTypes $Key).Where($Filter)).Count | Should -Be 0
    }

    It '<Preset> ignores a credential change that added no key' -ForEach @(
        @{ Preset = 'UserAddedSecretToAppRegistration' }
        @{ Preset = 'UserAddedCertificateToAppRegistration' }
    ) {
        $Filter = Get-PresetFilter -Preset $Preset
        $Removal = New-Record -Operation $script:AppCredentialOperation -UserId $script:UserActor
        $Removal.PSObject.Properties.Add([psnoteproperty]::new('CIPPAddedKeyTypes', ''))
        @(@($Removal).Where($Filter)).Count | Should -Be 0
    }

    It 'separates secrets from certificates' {
        $SecretFilter = Get-PresetFilter -Preset 'UserAddedSecretToServicePrincipal'
        $CertFilter = Get-PresetFilter -Preset 'UserAddedCertificateToServicePrincipal'
        $CertRecord = New-Record -Operation 'Add service principal credentials.' -UserId $script:UserActor -AddedKeyTypes 'AsymmetricX509Cert'

        @(@($CertRecord).Where($SecretFilter)).Count | Should -Be 0
        @(@($CertRecord).Where($CertFilter)).Count | Should -Be 1
    }

    It 'does not match owners added to groups' {
        $Filter = Get-PresetFilter -Preset 'UserAddedOwnerToApp'
        @(@(New-Record -Operation 'Add owner to group.' -UserId $script:UserActor).Where($Filter)).Count | Should -Be 0
    }
}
