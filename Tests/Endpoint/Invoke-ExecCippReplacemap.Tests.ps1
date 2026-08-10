# Pester tests for Invoke-ExecCippReplacemap.
#
# Custom variables carry an optional declared type. It is validated on save rather than at
# deployment, because a mistyped value silently falls back to being substituted as a string - in a
# template that might not deploy for days. The type is optional so that every variable saved before
# it existed, and any caller that omits it, keeps the original string behaviour.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecCippReplacemap.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecCippReplacemap.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    # The function uses the short [HttpStatusCode]; the Functions host supplies `using namespace
    # System.Net`. Register the accelerator so it resolves when dot-sourced here.
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity {
        param($Filter)
        if ($null -eq $Filter) { return $script:AllRows }
        if ($script:RowsByFilter -and $script:RowsByFilter.ContainsKey($Filter)) {
            return $script:RowsByFilter[$Filter]
        }
        return $script:ExistingEntity
    }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) $script:SavedEntity = $Entity }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) $script:RemovedEntity = $Entity }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }

    . $FunctionPath

    function New-SaveRequest {
        param(
            [string]$Name = 'wallpaperpath',
            $Value = 'C:\Wallpapers\corp.png',
            $VariableType,
            [string]$TenantId = 'AllTenants'
        )
        $Body = [pscustomobject]@{
            Action      = 'AddEdit'
            tenantId    = $TenantId
            RowKey      = $Name
            Value       = $Value
            Description = 'A test variable'
        }
        if ($PSBoundParameters.ContainsKey('VariableType')) {
            $Body | Add-Member -NotePropertyName 'VariableType' -NotePropertyValue $VariableType
        }
        return [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecCippReplacemap' }
            Headers = @{ Authorization = 'token' }
            Query   = @{}
            Body    = $Body
        }
    }

    function New-ListRequest {
        param([string]$TenantId = 'contoso.onmicrosoft.com', [bool]$IncludeGlobal = $true)
        $Query = @{ Action = 'List'; tenantId = $TenantId }
        if ($IncludeGlobal) { $Query['includeGlobal'] = 'true' }
        return [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecCippReplacemap' }
            Headers = @{}
            Query   = $Query
            Body    = [pscustomobject]@{}
        }
    }

    function New-UsageRequest {
        return [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecCippReplacemap' }
            Headers = @{}
            Query   = @{ Action = 'Usage' }
            Body    = [pscustomobject]@{}
        }
    }
}

Describe 'Invoke-ExecCippReplacemap - variable types' {
    BeforeEach {
        $script:SavedEntity = $null
        $script:RemovedEntity = $null
        $script:ExistingEntity = $null
        $script:AllRows = @()
        $script:RowsByFilter = @{}
        $script:AllTenants = @(
            [pscustomobject]@{ customerId = 'contoso-id'; displayName = 'Contoso Ltd' }
            [pscustomobject]@{ customerId = 'fabrikam-id'; displayName = 'Fabrikam Inc' }
        )

        Mock -CommandName Get-CIPPTable -MockWith { @{} }
        Mock -CommandName Get-Tenants -MockWith {
            param($TenantFilter, [switch]$IncludeAll)
            if ($IncludeAll) { return $script:AllTenants }
            [pscustomobject]@{ customerId = '11111111-1111-1111-1111-111111111111' }
        }
    }

    Context 'the type is optional' {
        It 'defaults to string when no type is sent' {
            $Response = Invoke-ExecCippReplacemap -Request (New-SaveRequest)

            $Response.StatusCode | Should -Be 200
            $script:SavedEntity.VariableType | Should -Be 'string'
            $script:SavedEntity.Value | Should -Be 'C:\Wallpapers\corp.png'
            $script:SavedEntity.RowKey | Should -Be 'wallpaperpath'
        }

        It 'defaults to string when the type is sent empty' {
            $Response = Invoke-ExecCippReplacemap -Request (New-SaveRequest -VariableType '')

            $Response.StatusCode | Should -Be 200
            $script:SavedEntity.VariableType | Should -Be 'string'
        }
    }

    Context 'accepted types' {
        It 'stores a valid integer variable' {
            $Response = Invoke-ExecCippReplacemap -Request (New-SaveRequest -Name 'lockseconds' -Value '300' -VariableType 'integer')

            $Response.StatusCode | Should -Be 200
            $script:SavedEntity.VariableType | Should -Be 'integer'
        }

        It 'stores a valid boolean variable' {
            $Response = Invoke-ExecCippReplacemap -Request (New-SaveRequest -Name 'requirepw' -Value 'true' -VariableType 'boolean')

            $Response.StatusCode | Should -Be 200
            $script:SavedEntity.VariableType | Should -Be 'boolean'
        }

        It 'stores a valid json variable' {
            $Response = Invoke-ExecCippReplacemap -Request (New-SaveRequest -Name 'allowedapps' -Value '["word.exe","excel.exe"]' -VariableType 'json')

            $Response.StatusCode | Should -Be 200
            $script:SavedEntity.VariableType | Should -Be 'json'
        }

        It 'accepts the {label, value} shape the type selector posts' {
            $Response = Invoke-ExecCippReplacemap -Request (
                New-SaveRequest -Name 'lockseconds' -Value '300' -VariableType ([pscustomobject]@{ label = 'Integer'; value = 'integer' })
            )

            $Response.StatusCode | Should -Be 200
            $script:SavedEntity.VariableType | Should -Be 'integer'
        }
    }

    Context 'a value that does not match its declared type is rejected' {
        It 'rejects a non-numeric integer' {
            $Response = Invoke-ExecCippReplacemap -Request (New-SaveRequest -Name 'lockseconds' -Value 'not-a-number' -VariableType 'integer')

            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -Match 'not a whole number'
            $script:SavedEntity | Should -BeNullOrEmpty
        }

        It 'rejects a non-boolean boolean' {
            $Response = Invoke-ExecCippReplacemap -Request (New-SaveRequest -Name 'requirepw' -Value 'maybe' -VariableType 'boolean')

            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -Match 'not true or false'
            $script:SavedEntity | Should -BeNullOrEmpty
        }

        It 'rejects malformed json' {
            $Response = Invoke-ExecCippReplacemap -Request (New-SaveRequest -Name 'allowedapps' -Value '{not json' -VariableType 'json')

            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -Match 'not valid JSON'
            $script:SavedEntity | Should -BeNullOrEmpty
        }

        It 'rejects an unknown type' {
            $Response = Invoke-ExecCippReplacemap -Request (New-SaveRequest -VariableType 'decimal')

            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -Match 'not a valid variable type'
            $script:SavedEntity | Should -BeNullOrEmpty
        }
    }

    Context 'values at the edges of each type' {
        It 'accepts zero and negative integers' {
            foreach ($Value in @('0', '-5')) {
                $script:SavedEntity = $null
                $Response = Invoke-ExecCippReplacemap -Request (New-SaveRequest -Name 'n' -Value $Value -VariableType 'integer')
                $Response.StatusCode | Should -Be 200 -Because "$Value is a whole number"
            }
        }

        It 'accepts the alternate boolean spellings the substitution understands' {
            foreach ($Value in @('true', 'false', '1', '0', 'yes', 'no')) {
                $script:SavedEntity = $null
                $Response = Invoke-ExecCippReplacemap -Request (New-SaveRequest -Name 'b' -Value $Value -VariableType 'boolean')
                $Response.StatusCode | Should -Be 200 -Because "$Value is a recognised boolean"
            }
        }

        It 'accepts a json object as well as an array' {
            $Response = Invoke-ExecCippReplacemap -Request (New-SaveRequest -Name 'cfg' -Value '{"a":1,"b":[2,3]}' -VariableType 'json')
            $Response.StatusCode | Should -Be 200
        }
    }

    Context 'existing behaviour is preserved' {
        It 'still resolves a tenant to its customerId' {
            $Response = Invoke-ExecCippReplacemap -Request (New-SaveRequest -TenantId 'contoso.onmicrosoft.com')

            $Response.StatusCode | Should -Be 200
            $script:SavedEntity.PartitionKey | Should -Be '11111111-1111-1111-1111-111111111111'
        }

        It 'still deletes a variable' {
            $script:ExistingEntity = [pscustomobject]@{ PartitionKey = 'AllTenants'; RowKey = 'wallpaperpath' }
            $Request = [pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecCippReplacemap' }
                Headers = @{}
                Query   = @{}
                Body    = [pscustomobject]@{ Action = 'Delete'; tenantId = 'AllTenants'; RowKey = 'wallpaperpath' }
            }

            $Response = Invoke-ExecCippReplacemap -Request $Request

            $Response.StatusCode | Should -Be 200
            $script:RemovedEntity.RowKey | Should -Be 'wallpaperpath'
        }
    }
}

Describe 'Invoke-ExecCippReplacemap - Usage' {
    BeforeEach {
        $script:SavedEntity = $null
        $script:AllTenants = @(
            [pscustomobject]@{ customerId = 'contoso-id'; displayName = 'Contoso Ltd' }
            [pscustomobject]@{ customerId = 'fabrikam-id'; displayName = 'Fabrikam Inc' }
        )
        $script:AllRows = @(
            [pscustomobject]@{ PartitionKey = 'AllTenants'; RowKey = 'wallpaperpath'; Value = 'C:\Global'; VariableType = 'string' }
            [pscustomobject]@{ PartitionKey = 'contoso-id'; RowKey = 'wallpaperpath'; Value = 'C:\Contoso'; VariableType = 'string' }
            [pscustomobject]@{ PartitionKey = 'fabrikam-id'; RowKey = 'wallpaperpath'; Value = 'C:\Fabrikam'; VariableType = 'string' }
            [pscustomobject]@{ PartitionKey = 'contoso-id'; RowKey = 'lockseconds'; Value = '300'; VariableType = 'integer' }
            [pscustomobject]@{ PartitionKey = 'fabrikam-id'; RowKey = 'lockseconds'; Value = '900'; VariableType = 'integer' }
            [pscustomobject]@{ PartitionKey = 'contoso-id'; RowKey = 'legacyvar'; Value = 'old' }
            [pscustomobject]@{ PartitionKey = 'deleted-tenant-id'; RowKey = 'driftvar'; Value = 'true'; VariableType = 'boolean' }
            [pscustomobject]@{ PartitionKey = 'contoso-id'; RowKey = 'driftvar'; Value = 'yes-ish'; VariableType = 'string' }
        )
        Mock -CommandName Get-CIPPTable -MockWith { @{} }
        Mock -CommandName Get-Tenants -MockWith {
            param($TenantFilter, [switch]$IncludeAll)
            if ($IncludeAll) { return $script:AllTenants }
            [pscustomobject]@{ customerId = 'contoso-id' }
        }
    }

    It 'groups every definition of a name across tenants' {
        $Response = Invoke-ExecCippReplacemap -Request (New-UsageRequest)
        $Wallpaper = $Response.Body.Results | Where-Object { $_.Name -eq 'wallpaperpath' }

        $Wallpaper.TenantCount | Should -Be 2
        $Wallpaper.HasGlobal | Should -BeTrue
        @($Wallpaper.Definitions).Count | Should -Be 3
        ($Wallpaper.Definitions | Where-Object { $_.Scope -eq 'Tenant' }).TenantName | Should -Contain 'Contoso Ltd'
    }

    It 'needs no tenantId' {
        # The action is answered before the tenant guard, so a missing tenantId is not an error.
        $Response = Invoke-ExecCippReplacemap -Request (New-UsageRequest)
        $Response.StatusCode | Should -Be 200
    }

    It 'suggests the global type when there is one' {
        $Response = Invoke-ExecCippReplacemap -Request (New-UsageRequest)
        ($Response.Body.Results | Where-Object { $_.Name -eq 'wallpaperpath' }).SuggestedType | Should -Be 'string'
    }

    It 'suggests the most common tenant type when there is no global definition' {
        $Response = Invoke-ExecCippReplacemap -Request (New-UsageRequest)
        $Lock = $Response.Body.Results | Where-Object { $_.Name -eq 'lockseconds' }

        $Lock.HasGlobal | Should -BeFalse
        $Lock.SuggestedType | Should -Be 'integer'
        $Lock.TypesConsistent | Should -BeTrue
    }

    It 'flags a name that is typed differently in different tenants' {
        $Response = Invoke-ExecCippReplacemap -Request (New-UsageRequest)
        $Drift = $Response.Body.Results | Where-Object { $_.Name -eq 'driftvar' }

        $Drift.TypesConsistent | Should -BeFalse
        @($Drift.Types) | Should -Be @('boolean', 'string')
    }

    It 'reports an untyped row as string' {
        $Response = Invoke-ExecCippReplacemap -Request (New-UsageRequest)
        $Legacy = $Response.Body.Results | Where-Object { $_.Name -eq 'legacyvar' }
        $Legacy.Definitions[0].VariableType | Should -Be 'string'
    }

    It 'falls back to the partition key when a tenant no longer resolves' {
        $Response = Invoke-ExecCippReplacemap -Request (New-UsageRequest)
        $Drift = $Response.Body.Results | Where-Object { $_.Name -eq 'driftvar' }
        $Drift.Definitions.TenantName | Should -Contain 'deleted-tenant-id'
    }
}

Describe 'Invoke-ExecCippReplacemap - List marks overridden variables' {
    BeforeEach {
        $script:ExistingEntity = $null
        $script:AllRows = @()
        # One row per partition, keyed by the filter the function builds for each.
        $script:RowsByFilter = @{
            "PartitionKey eq 'AllTenants'"  = @(
                [pscustomobject]@{ PartitionKey = 'AllTenants'; RowKey = 'wallpaperpath'; Value = 'C:\Global' }
                [pscustomobject]@{ PartitionKey = 'AllTenants'; RowKey = 'globalonly'; Value = 'only-global' }
            )
            "PartitionKey eq 'contoso-id'" = @(
                [pscustomobject]@{ PartitionKey = 'contoso-id'; RowKey = 'wallpaperpath'; Value = 'C:\Contoso' }
                [pscustomobject]@{ PartitionKey = 'contoso-id'; RowKey = 'tenantonly'; Value = 'local' }
            )
        }
        Mock -CommandName Get-CIPPTable -MockWith { @{} }
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ customerId = 'contoso-id' } }
    }

    It 'reports a tenant value that shadows a global one as Overridden' {
        $Response = Invoke-ExecCippReplacemap -Request (New-ListRequest)
        $Row = $Response.Body.Results | Where-Object { $_.RowKey -eq 'wallpaperpath' }

        @($Row).Count | Should -Be 1 -Because 'the shadowed global is dropped from the list'
        $Row.Scope | Should -Be 'Overridden'
        $Row.Value | Should -Be 'C:\Contoso'
    }

    It 'leaves a tenant-only variable as Tenant' {
        $Response = Invoke-ExecCippReplacemap -Request (New-ListRequest)
        ($Response.Body.Results | Where-Object { $_.RowKey -eq 'tenantonly' }).Scope | Should -Be 'Tenant'
    }

    It 'leaves an unshadowed global as Global' {
        $Response = Invoke-ExecCippReplacemap -Request (New-ListRequest)
        ($Response.Body.Results | Where-Object { $_.RowKey -eq 'globalonly' }).Scope | Should -Be 'Global'
    }

    It 'never reports Overridden when globals are not being included' {
        $Response = Invoke-ExecCippReplacemap -Request (New-ListRequest -IncludeGlobal $false)
        @($Response.Body.Results | Where-Object { $_.Scope -eq 'Overridden' }).Count | Should -Be 0
        ($Response.Body.Results | Where-Object { $_.RowKey -eq 'wallpaperpath' }).Scope | Should -Be 'Tenant'
    }

    It 'reports every row on the global page as Global' {
        $Response = Invoke-ExecCippReplacemap -Request (New-ListRequest -TenantId 'AllTenants')
        @($Response.Body.Results | Where-Object { $_.Scope -ne 'Global' }).Count | Should -Be 0
    }
}
