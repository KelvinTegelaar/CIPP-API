BeforeAll {
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/NinjaOne/Initialize-NinjaOneCredentialField.ps1"

    function Get-CIPPTable { param($TableName) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $message, $Sev) }
    function Get-ExtensionMapping { param($Extension) }
    function Get-NinjaOneToken { param($configuration, $WebSession) }

    $script:Config = [pscustomobject]@{ Instance = 'app.ninjarmm.com'; IncludeLAPS = $true; IncludeBitLocker = $false }
    $script:Token = [pscustomobject]@{ access_token = 'x' }
    $script:List = { param($Names) [pscustomobject]@{ Content = (ConvertTo-Json -InputObject @($Names | ForEach-Object { @{ name = $_ } })) } }
    $script:LapsNames = @('cippLapsAccount', 'cippLapsBackupDate', 'cippLapsPassword')
}

Describe 'Initialize-NinjaOneCredentialField' {
    BeforeEach {
        Mock Get-CIPPTable { @{} }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Write-LogMessage { }
    }

    It 'does nothing when the credential fields are already mapped' {
        Mock Invoke-WebRequest { }
        $Mapped = [pscustomobject]@{ LAPSAccount = 'a'; LAPSPassword = 'b'; LAPSBackupDate = 'c' }

        Initialize-NinjaOneCredentialField -Configuration $Config -Token $Token -MappedFields $Mapped

        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        $Mapped.LAPSPassword | Should -Be 'b'
    }

    It 'leaves a manual mapping alone and adopts existing fields by fieldName without creating' {
        Mock Invoke-WebRequest -ParameterFilter { $Method -eq 'GET' } { & $List @('cippLapsPassword', 'cippLapsBackupDate', 'other') }
        Mock Invoke-WebRequest -ParameterFilter { $Method -eq 'POST' } { }
        $Mapped = [pscustomobject]@{ LAPSAccount = 'myAccountField' }

        Initialize-NinjaOneCredentialField -Configuration $Config -Token $Token -MappedFields $Mapped

        Should -Invoke Invoke-WebRequest -ParameterFilter { $Method -eq 'POST' } -Times 0 -Exactly
        $Mapped.LAPSAccount | Should -Be 'myAccountField'
        $Mapped.LAPSPassword | Should -Be 'cippLapsPassword'
        $Mapped.LAPSBackupDate | Should -Be 'cippLapsBackupDate'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { @($Entity).Count -eq 2 -and 'LAPSAccount' -notin $Entity.RowKey }
    }

    It 'creates the absent fields and writes their mapping rows' {
        Mock Invoke-WebRequest -ParameterFilter { $Method -eq 'GET' } { & $List @() }
        Mock Invoke-WebRequest -ParameterFilter { $Method -eq 'POST' } { }
        $Mapped = [pscustomobject]@{}

        Initialize-NinjaOneCredentialField -Configuration $Config -Token $Token -MappedFields $Mapped

        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*/api/v2/custom-fields/bulk' -and
            (($Body | ConvertFrom-Json).customFields.fieldName | Sort-Object) -join ',' -eq ($LapsNames -join ',') -and
            (($Body | ConvertFrom-Json).customFields | Where-Object fieldName -EQ 'cippLapsPassword').type -eq 'TEXT_ENCRYPTED' -and
            @(($Body | ConvertFrom-Json).customFields | Where-Object apiPermission -NE 'WRITE_ONLY').Count -eq 0
        }
        $Mapped.LAPSPassword | Should -Be 'cippLapsPassword'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            @($Entity).Count -eq 3 -and ($Entity | Where-Object RowKey -EQ 'LAPSPassword').IntegrationId -eq 'cippLapsPassword' -and $Entity[0].PartitionKey -eq 'NinjaOneFieldMapping'
        }
    }

    It 'adopts fields a concurrent sync created when the create fails' {
        $script:Listed = 0
        Mock Invoke-WebRequest -ParameterFilter { $Method -eq 'GET' } { $script:Listed++; if ($script:Listed -eq 1) { & $List @() } else { & $List $LapsNames } }
        Mock Invoke-WebRequest -ParameterFilter { $Method -eq 'POST' } { throw 'fieldName already exists' }
        $Mapped = [pscustomobject]@{}

        Initialize-NinjaOneCredentialField -Configuration $Config -Token $Token -MappedFields $Mapped

        $Mapped.LAPSPassword | Should -Be 'cippLapsPassword'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { @($Entity).Count -eq 3 }
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }

    It 'adopts write-only fields the listing cannot show when NinjaOne rejects the create as a duplicate' {
        Mock Invoke-WebRequest -ParameterFilter { $Method -eq 'GET' } { & $List @() }
        Mock Invoke-WebRequest -ParameterFilter { $Method -eq 'POST' } { throw '{"resultCode":"duplicate_attribute_names_detected","errorMessage":"Duplicate attributes found"}' }
        $Mapped = [pscustomobject]@{}

        Initialize-NinjaOneCredentialField -Configuration $Config -Token $Token -MappedFields $Mapped

        $Mapped.LAPSPassword | Should -Be 'cippLapsPassword'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { @($Entity).Count -eq 3 }
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }

    It 'reads the current mapping and requests a token when called without them' {
        Mock Get-ExtensionMapping { @([pscustomobject]@{ RowKey = 'LAPSAccount'; IntegrationId = 'myAccountField' }, [pscustomobject]@{ RowKey = 'TenantLinks'; IntegrationId = 'links' }) }
        Mock Get-NinjaOneToken { $Token }
        Mock Invoke-WebRequest -ParameterFilter { $Method -eq 'GET' } { & $List @() }
        Mock Invoke-WebRequest -ParameterFilter { $Method -eq 'POST' } { throw '{"resultCode":"duplicate_attribute_names_detected"}' }

        Initialize-NinjaOneCredentialField -Configuration $Config

        Should -Invoke Get-ExtensionMapping -Times 1 -Exactly -ParameterFilter { $Extension -eq 'NinjaOneField' }
        Should -Invoke Get-NinjaOneToken -Times 1 -Exactly
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' -and (($Body | ConvertFrom-Json).customFields.fieldName | Sort-Object) -join ',' -eq 'cippLapsBackupDate,cippLapsPassword' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { @($Entity).Count -eq 2 -and 'LAPSAccount' -notin $Entity.RowKey }
    }

    It 'requests no token when every switched-on field is already mapped' {
        Mock Get-ExtensionMapping { @([pscustomobject]@{ RowKey = 'LAPSAccount'; IntegrationId = 'a' }, [pscustomobject]@{ RowKey = 'LAPSPassword'; IntegrationId = 'b' }, [pscustomobject]@{ RowKey = 'LAPSBackupDate'; IntegrationId = 'c' }) }
        Mock Get-NinjaOneToken { }
        Mock Invoke-WebRequest { }

        Initialize-NinjaOneCredentialField -Configuration $Config

        Should -Invoke Get-NinjaOneToken -Times 0 -Exactly
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'warns and maps nothing when the create fails and the fields are still absent' {
        Mock Invoke-WebRequest -ParameterFilter { $Method -eq 'GET' } { & $List @() }
        Mock Invoke-WebRequest -ParameterFilter { $Method -eq 'POST' } { throw 'forbidden' }
        $Mapped = [pscustomobject]@{}

        Initialize-NinjaOneCredentialField -Configuration $Config -Token $Token -MappedFields $Mapped

        $Mapped.PSObject.Properties.Name | Should -BeNullOrEmpty
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -match 'forbidden' }
    }
}
