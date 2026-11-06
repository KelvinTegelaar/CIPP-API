# Pester tests for Invoke-ExecAssignPartnerTenant
#
# Pinning a customer to the wrong partner leaves every subsequent Graph call authenticating
# as a CSP with no relationship to that tenant, so each validation guard is asserted along
# with the two writes the success path owes the caller: the manual pin and the token-cache clear.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecAssignPartnerTenant.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecAssignPartnerTenant.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    # The Functions worker exposes [HttpStatusCode] as an accelerator; register it for tests.
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # Minimal stubs so Mock has commands to replace during tests
    function Get-CIPPTable { param($tablename, $Context) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Get-CIPPFeatureFlag { param($Id) }
    function Get-CIPPAuthentication { }
    function Clear-CippTokenCache { param($TenantFilter) }
    function Write-LogMessage { param($API, $headers, $message, $Sev, $LogData, $tenant) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    $script:PrimaryPartner = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:PartnerB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    $script:PartnerC = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
    $script:CustomerId = '11111111-1111-1111-1111-111111111111'

    function New-AssignRequest {
        param($CustomerId, $PartnerTenantId)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecAssignPartnerTenant' }
            Headers = @{ }
            Body    = [pscustomobject]@{
                customerId      = $CustomerId
                partnerTenantId = $PartnerTenantId
            }
        }
    }
}

Describe 'Invoke-ExecAssignPartnerTenant' {
    BeforeEach {
        $script:OriginalTenantId = $env:TenantID
        $env:TenantID = $script:PrimaryPartner

        $script:PartnerRows = [System.Collections.Generic.List[object]]::new()
        $script:PartnerRows.Add([pscustomobject]@{ PartitionKey = 'Partners'; RowKey = $script:PartnerB; Enabled = $true })
        $script:PartnerRows.Add([pscustomobject]@{ PartitionKey = 'Partners'; RowKey = $script:PartnerC; Enabled = $false })

        $script:TenantRow = [pscustomobject]@{
            PartitionKey             = 'Tenants'
            RowKey                   = $script:CustomerId
            customerId               = $script:CustomerId
            displayName              = 'Contoso'
            defaultDomainName        = 'contoso.onmicrosoft.com'
            delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges'
            partnerTenantId          = $script:PrimaryPartner
            partnerAssignmentMode    = 'auto'
            knownPartners            = "$script:PrimaryPartner,$script:PartnerB"
            isPartnerTenantRow       = $false
        }

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { 'stub-exception' }
        Mock -CommandName Get-CIPPAuthentication -MockWith { }
        Mock -CommandName Get-CIPPFeatureFlag -MockWith { [pscustomobject]@{ Id = $Id; Enabled = $true } }
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = $tablename } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Clear-CippTokenCache -MockWith { 0 }

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($TableName -eq 'PartnerTenants') {
                return @($script:PartnerRows | Where-Object { $Filter -like "*'$($_.RowKey)'*" })
            }
            if ($null -eq $script:TenantRow) { return @() }
            return @($script:TenantRow | Where-Object { $Filter -like "*'$($_.RowKey)'*" })
        }
    }

    AfterEach {
        $env:TenantID = $script:OriginalTenantId
    }

    Context 'Rejected assignments' {
        It 'refuses a partner that is not in the tenant knownPartners list' {
            $script:PartnerRows.Add([pscustomobject]@{ PartitionKey = 'Partners'; RowKey = '99999999-9999-9999-9999-999999999999'; Enabled = $true })

            $Response = Invoke-ExecAssignPartnerTenant -Request (New-AssignRequest -CustomerId $script:CustomerId -PartnerTenantId '99999999-9999-9999-9999-999999999999') -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $Response.Body.Results[0] | Should -BeLike '*no active GDAP relationship*'
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
            Should -Invoke -CommandName Clear-CippTokenCache -Times 0 -Exactly
        }

        It 'refuses a disabled partner' {
            $script:TenantRow.knownPartners = "$script:PrimaryPartner,$script:PartnerC"

            $Response = Invoke-ExecAssignPartnerTenant -Request (New-AssignRequest -CustomerId $script:CustomerId -PartnerTenantId $script:PartnerC) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $Response.Body.Results[0] | Should -BeLike '*is not configured or is disabled*'
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
            Should -Invoke -CommandName Clear-CippTokenCache -Times 0 -Exactly
        }

        It 'refuses a partner that has no PartnerTenants row at all' {
            $script:TenantRow.knownPartners = "$script:PrimaryPartner,99999999-9999-9999-9999-999999999999"

            $Response = Invoke-ExecAssignPartnerTenant -Request (New-AssignRequest -CustomerId $script:CustomerId -PartnerTenantId '99999999-9999-9999-9999-999999999999') -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $Response.Body.Results[0] | Should -BeLike '*is not configured or is disabled*'
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'refuses to reassign a partner tenant row' {
            $script:TenantRow.isPartnerTenantRow = $true

            $Response = Invoke-ExecAssignPartnerTenant -Request (New-AssignRequest -CustomerId $script:CustomerId -PartnerTenantId $script:PartnerB) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $Response.Body.Results[0] | Should -BeLike '*Partner tenant rows cannot be reassigned*'
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
            Should -Invoke -CommandName Clear-CippTokenCache -Times 0 -Exactly
        }

        It 'refuses to assign a direct tenant to a partner' {
            $script:TenantRow.delegatedPrivilegeStatus = 'directTenant'

            $Response = Invoke-ExecAssignPartnerTenant -Request (New-AssignRequest -CustomerId $script:CustomerId -PartnerTenantId $script:PartnerB) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $Response.Body.Results[0] | Should -BeLike '*Direct tenants*'
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'refuses a tenant that is not in the tenant cache' {
            $script:TenantRow = $null

            $Response = Invoke-ExecAssignPartnerTenant -Request (New-AssignRequest -CustomerId $script:CustomerId -PartnerTenantId $script:PartnerB) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $Response.Body.Results[0] | Should -BeLike '*was not found in the tenant cache*'
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'refuses ids that are not GUIDs before touching any table' {
            $Response = Invoke-ExecAssignPartnerTenant -Request (New-AssignRequest -CustomerId 'contoso.onmicrosoft.com' -PartnerTenantId $script:PartnerB) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $Response.Body.Results[0] | Should -BeLike '*must be tenant ids*'
            Should -Invoke -CommandName Get-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'refuses everything while the MultiPartner flag is off' {
            Mock -CommandName Get-CIPPFeatureFlag -MockWith { [pscustomobject]@{ Id = $Id; Enabled = $false } }

            $Response = Invoke-ExecAssignPartnerTenant -Request (New-AssignRequest -CustomerId $script:CustomerId -PartnerTenantId $script:PartnerB) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $Response.Body.Results[0] | Should -BeLike '*not enabled*'
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
            Should -Invoke -CommandName Clear-CippTokenCache -Times 0 -Exactly
        }
    }

    Context 'Successful reassignment' {
        It 'pins the new owner and marks the assignment manual' {
            $Response = Invoke-ExecAssignPartnerTenant -Request (New-AssignRequest -CustomerId $script:CustomerId -PartnerTenantId $script:PartnerB) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
                $Entity.partnerTenantId -eq 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -and
                $Entity.partnerAssignmentMode -eq 'manual'
            }
        }

        It 'clears the token cache for the reassigned customer' {
            $null = Invoke-ExecAssignPartnerTenant -Request (New-AssignRequest -CustomerId $script:CustomerId -PartnerTenantId $script:PartnerB) -TriggerMetadata $null

            Should -Invoke -CommandName Clear-CippTokenCache -Times 1 -Exactly -ParameterFilter {
                $TenantFilter -eq '11111111-1111-1111-1111-111111111111'
            }
        }

        It 'allows assigning back to the primary partner without a PartnerTenants row' {
            $script:PartnerRows.Clear()

            $Response = Invoke-ExecAssignPartnerTenant -Request (New-AssignRequest -CustomerId $script:CustomerId -PartnerTenantId $script:PrimaryPartner) -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
                $Entity.partnerTenantId -eq 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            }
        }
    }
}
