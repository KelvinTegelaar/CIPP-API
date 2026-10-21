BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Public = Join-Path $RepoRoot 'Modules/CIPPCore/Public'

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, [switch]$Compliance, [switch]$AsApp, $useSystemMailbox) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = "$($Exception.Exception.Message)" } }

    . (Join-Path $Public 'Format-CIPPCompliancePolicyParams.ps1')
    . (Join-Path $Public 'ConvertTo-CIPPComplianceSetParams.ps1')
    . (Join-Path $Public 'Set-CIPPRetentionCompliancePolicy.ps1')

    $script:Tenant = 'target.onmicrosoft.com'
    $script:NewTemplate = {
        '{"name":"Main Retention Policy","comments":"Seven years","RuleParams":{"RetentionDuration":"2555","RetentionComplianceAction":"Keep","Name":"Main Retention Policy","ExpirationDateOption":"ModificationAgeInDays"},"ExchangeLocation":"All","Enabled":true,"RestrictiveRetention":false,"GUID":"02ab8596-a69a-4cb8-99ef-da759076079c"}' | ConvertFrom-Json
    }
}

Describe 'Set-CIPPRetentionCompliancePolicy' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $script:Policies = @()
        $script:Rules = @()
        $script:FailCmdlet = $null
        Mock New-ExoRequest {
            $script:Calls.Add(@{ Cmdlet = $cmdlet; Params = $cmdParams })
            if ($cmdlet -eq $script:FailCmdlet) { throw 'The policy is being deployed.' }
            if ($cmdlet -eq 'Get-RetentionCompliancePolicy') { return $script:Policies }
            if ($cmdlet -eq 'Get-RetentionComplianceRule') { return $script:Rules }
        }
    }

    It 'creates the policy with the template comment and its rule' {
        $Result = Set-CIPPRetentionCompliancePolicy -TenantFilter $script:Tenant -Template (& $script:NewTemplate) -APIName 'Test'

        $Result | Should -Be "Created retention compliance policy 'Main Retention Policy' in $($script:Tenant). Created rule 'Main Retention Policy'."
        $NewPolicy = $script:Calls.Where({ $_.Cmdlet -eq 'New-RetentionCompliancePolicy' })[0]
        $NewPolicy.Params['Comment'] | Should -Be 'Seven years'
        $NewRule = $script:Calls.Where({ $_.Cmdlet -eq 'New-RetentionComplianceRule' })[0]
        $NewRule.Params['Policy'] | Should -Be 'Main Retention Policy'
        $NewRule.Params['RetentionDuration'] | Should -Be '2555'
    }

    It 'throws naming the rule step when the policy was created but the rule failed' {
        $script:FailCmdlet = 'New-RetentionComplianceRule'

        { Set-CIPPRetentionCompliancePolicy -TenantFilter $script:Tenant -Template (& $script:NewTemplate) -APIName 'Test' } |
            Should -Throw "Created retention compliance policy 'Main Retention Policy' in $($script:Tenant). Could not deploy its retention rule 'Main Retention Policy': The policy is being deployed."
    }

    It 'throws when the policy itself could not be deployed' {
        $script:FailCmdlet = 'New-RetentionCompliancePolicy'

        { Set-CIPPRetentionCompliancePolicy -TenantFilter $script:Tenant -Template (& $script:NewTemplate) -APIName 'Test' } |
            Should -Throw "Could not create retention compliance policy 'Main Retention Policy' in $($script:Tenant): The policy is being deployed."
        $script:Calls.Where({ $_.Cmdlet -like '*RetentionComplianceRule' -and $_.Cmdlet -notlike 'Get-*' }).Count | Should -Be 0
    }

    It 'updates the rule already under the policy, matched by policy GUID' {
        $script:Policies = @([PSCustomObject]@{ Name = 'Main Retention Policy'; Guid = '39aaeafc-4a55-4bd0-ac94-31e2bcdf83ae' })
        $script:Rules = @(
            [PSCustomObject]@{ Name = 'Main Retention Policy'; Policy = 'a705c7a0-2179-4385-ae80-b1711b8c0f67' }
            [PSCustomObject]@{ Name = 'Portal Rule'; Policy = '39aaeafc-4a55-4bd0-ac94-31e2bcdf83ae' }
        )

        $Result = Set-CIPPRetentionCompliancePolicy -TenantFilter $script:Tenant -Template (& $script:NewTemplate) -APIName 'Test'

        $Result | Should -BeLike "Updated retention compliance policy*Updated rule 'Portal Rule'."
        $script:Calls.Where({ $_.Cmdlet -eq 'New-RetentionComplianceRule' }).Count | Should -Be 0
        $SetRule = $script:Calls.Where({ $_.Cmdlet -eq 'Set-RetentionComplianceRule' })[0]
        $SetRule.Params['Identity'] | Should -Be 'Portal Rule'
        $SetRule.Params.ContainsKey('Policy') | Should -BeFalse
    }

    It 'still creates the rule of an existing policy whose update Purview refuses, then reports the refusal' {
        $script:Policies = @([PSCustomObject]@{ Name = 'Main Retention Policy'; Guid = '39aaeafc-4a55-4bd0-ac94-31e2bcdf83ae' })
        $script:FailCmdlet = 'Set-RetentionCompliancePolicy'

        { Set-CIPPRetentionCompliancePolicy -TenantFilter $script:Tenant -Template (& $script:NewTemplate) -APIName 'Test' } |
            Should -Throw "Could not update retention compliance policy 'Main Retention Policy' in $($script:Tenant): The policy is being deployed. Created rule 'Main Retention Policy'."
        $script:Calls.Where({ $_.Cmdlet -eq 'New-RetentionComplianceRule' }).Count | Should -Be 1
    }
}
