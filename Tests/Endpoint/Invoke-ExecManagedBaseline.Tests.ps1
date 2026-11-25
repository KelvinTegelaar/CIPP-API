# Adding a published baseline, and Align and Merge on a managed one. The endpoint decides what is
# allowed and hands the write to the shared import; a preview never writes.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Write-LogMessage { param($headers, $API, $message, $Sev) }
    function Invoke-ManagedBaselinesRequest { param($Path, $Method, $Body) }
    function Get-CIPPBaseline { param($ID, [switch]$ResolveIdentityLabels) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Get-CIPPBaselineOutOfScopeAssignment { param($Assignments) }
    function Import-CIPPManagedBaseline { param($Package, $Baseline, $Kind, $RequestId, $User, [string[]]$TemplateIds) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Merge-CIPPManagedBaseline.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-ExecManagedBaseline.ps1')

    $script:Package = Get-Content (Join-Path $BackendRoot 'Tests/Fixtures/ManagedBaselines/template-sample-identity-essentials.json') -Raw | ConvertFrom-Json -Depth 100
    $Principal = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"userDetails":"admin@partner.example"}'))
    $script:NewRequest = {
        param($Body)
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecManagedBaseline' }; Headers = @{ 'x-ms-client-principal' = $Principal }; Body = [pscustomobject]$Body }
    }
    # A managed baseline holding two of the package's six standards plus one of the partner's own.
    function New-LocalBaseline {
        param($Kind = 'template', [bool]$Managed = $true)
        $Config = { param($Name) [pscustomobject]@{ standard = $Name; instance = $Name; variables = [pscustomobject]@{}; remediateEnabled = $true; alertEnabled = $true; alertOnRemediate = $false } }
        [pscustomobject]@{
            GUID             = 'baseline-1'
            templateName     = 'Contoso baseline'
            description      = 'Renamed by the partner'
            isManaged        = $Managed
            managedId        = 'sample-identity-essentials'
            managedVersion   = '1'
            managedKind      = $Kind
            managedRequestId = 'request-9'
            assignments      = @([pscustomobject]@{ label = 'Contoso'; value = 'contoso.com'; type = 'Tenant' })
            exclusions       = @()
            stages           = @([pscustomobject]@{
                    name = 'Baseline'; logic = 'and'; conditions = @(); conditionGroups = @()
                    standardsConfig = @((& $Config 'SmartLockout'), (& $Config 'OauthConsent'), (& $Config 'DisableReshare'))
                })
        }
    }
}

Describe 'Invoke-ExecManagedBaseline' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Get-CIPPAzDataTableEntity {}
        Mock Get-CIPPBaselineDefinition {}
        Mock Get-CIPPBaselineOutOfScopeAssignment {}
        Mock Invoke-ManagedBaselinesRequest { $script:Package }
        Mock Import-CIPPManagedBaseline { @{ GUID = 'baseline-1'; DeltaCount = 6; Templates = 0; Failures = @() } }
        Mock Get-CIPPBaseline { New-LocalBaseline }
    }

    Context 'Import' {
        It 'adds a published baseline with the placeholder assignment' {
            $Response = Invoke-ExecManagedBaseline -Request (& $script:NewRequest @{ Action = 'Import'; id = 'sample-identity-essentials' })

            $Response.StatusCode | Should -Be 200
            $Response.Body.Results | Should -BeLike "*Sample - Identity Essentials*6 standards*"
            Should -Invoke Invoke-ManagedBaselinesRequest -Times 1 -Exactly -ParameterFilter { $Path -eq 'templates/sample-identity-essentials' }
            Should -Invoke Import-CIPPManagedBaseline -Times 1 -Exactly -ParameterFilter {
                $Kind -eq 'template' -and $User -eq 'admin@partner.example' -and
                $Baseline.assignedTenants[0].value -eq 'Exported Template' -and
                @($Baseline.stages[0].standards).Count -eq 6 -and -not $Baseline.GUID
            }
        }

        It 'refuses to add the same published baseline twice' {
            Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'baseline-1'; templateName = 'Contoso baseline'; ManagedId = 'sample-identity-essentials'; ManagedKind = 'template' } }

            $Response = Invoke-ExecManagedBaseline -Request (& $script:NewRequest @{ Action = 'Import'; id = 'sample-identity-essentials' })

            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -BeLike '*already added*'
            Should -Invoke Import-CIPPManagedBaseline -Times 0 -Exactly
        }

        It 'refuses without a published baseline to add' {
            (Invoke-ExecManagedBaseline -Request (& $script:NewRequest @{ Action = 'Import' })).StatusCode | Should -Be 400
            Should -Invoke Invoke-ManagedBaselinesRequest -Times 0 -Exactly
        }
    }

    Context 'Align and Merge' {
        It 'previews <Action> without writing anything' -ForEach @(@{ Action = 'Align' }, @{ Action = 'Merge' }) {
            $Response = Invoke-ExecManagedBaseline -Request (& $script:NewRequest @{ Action = $Action; GUID = 'baseline-1'; Preview = $true })

            $Response.StatusCode | Should -Be 200
            $Response.Body.Metadata.currentVersion | Should -Be '1'
            $Response.Body.Metadata.newVersion | Should -Be '2'
            $Response.Body.Metadata.overwritten.standard | Should -Be @('SmartLockout', 'OauthConsent')
            Should -Invoke Import-CIPPManagedBaseline -Times 0 -Exactly
        }

        It 'lists the partner-only standard as removed by Align and kept by Merge' {
            $Align = (Invoke-ExecManagedBaseline -Request (& $script:NewRequest @{ Action = 'Align'; GUID = 'baseline-1'; Preview = $true })).Body.Metadata
            $Merge = (Invoke-ExecManagedBaseline -Request (& $script:NewRequest @{ Action = 'Merge'; GUID = 'baseline-1'; Preview = $true })).Body.Metadata

            $Align.removed.standard | Should -Be @('DisableReshare')
            @($Align.added).Count | Should -Be 4
            $Merge.kept.standard | Should -Be @('DisableReshare')
            @($Merge.available).Count | Should -Be 4
            @($Merge.added).Count | Should -Be 0
        }

        It 'writes an Align with every template in the package' {
            $Response = Invoke-ExecManagedBaseline -Request (& $script:NewRequest @{ Action = 'Align'; GUID = 'baseline-1' })

            $Response.StatusCode | Should -Be 200
            $Response.Body.Results | Should -BeLike "Aligned 'Contoso baseline'*version 2: 2 overwritten, 4 added, 1 removed."
            Should -Invoke Import-CIPPManagedBaseline -Times 1 -Exactly -ParameterFilter {
                $Kind -eq 'template' -and $Baseline.GUID -eq 'baseline-1' -and $Baseline.templateName -eq 'Contoso baseline' -and
                @($Baseline.stages[0].standards).Count -eq 6 -and -not $PesterBoundParameters.ContainsKey('TemplateIds')
            }
        }

        It 'writes a Merge with only the ticked standards added and only the templates it touched' {
            $Response = Invoke-ExecManagedBaseline -Request (& $script:NewRequest @{ Action = 'Merge'; GUID = 'baseline-1'; Add = @('EnableFIDO2|1') })

            $Response.Body.Results | Should -BeLike "Merged*into 'Contoso baseline': 2 overwritten, 1 added, 1 of your own kept."
            Should -Invoke Import-CIPPManagedBaseline -Times 1 -Exactly -ParameterFilter {
                $PesterBoundParameters.ContainsKey('TemplateIds') -and @($TemplateIds).Count -eq 0 -and
                (@($Baseline.stages[0].standards.standard) -join ',') -eq 'SmartLockout,OauthConsent,DisableReshare,EnableFIDO2'
            }
        }

        It 'fetches a custom baseline from its request, not from the catalog' {
            Mock Get-CIPPBaseline { New-LocalBaseline -Kind 'custom' }
            Mock Invoke-ManagedBaselinesRequest { [pscustomobject]@{ status = 'implemented'; package = $script:Package } }

            $null = Invoke-ExecManagedBaseline -Request (& $script:NewRequest @{ Action = 'Align'; GUID = 'baseline-1' })

            Should -Invoke Invoke-ManagedBaselinesRequest -Times 1 -Exactly -ParameterFilter { $Path -eq 'requests/request-9' }
            Should -Invoke Import-CIPPManagedBaseline -Times 1 -Exactly -ParameterFilter { $Kind -eq 'custom' -and $RequestId -eq 'request-9' }
        }

        It 'refuses a baseline CyberDrain does not manage' {
            Mock Get-CIPPBaseline { New-LocalBaseline -Managed $false }

            (Invoke-ExecManagedBaseline -Request (& $script:NewRequest @{ Action = 'Align'; GUID = 'baseline-1' })).StatusCode | Should -Be 400
            Should -Invoke Invoke-ManagedBaselinesRequest -Times 0 -Exactly
        }

        It 'refuses when the baseline reaches tenants outside the caller''s access' {
            Mock Get-CIPPBaselineOutOfScopeAssignment { 'Contoso' }

            $Response = Invoke-ExecManagedBaseline -Request (& $script:NewRequest @{ Action = 'Merge'; GUID = 'baseline-1' })

            $Response.StatusCode | Should -Be 403
            Should -Invoke Import-CIPPManagedBaseline -Times 0 -Exactly
        }

        It 'answers not found for a baseline that does not exist' {
            Mock Get-CIPPBaseline {}

            (Invoke-ExecManagedBaseline -Request (& $script:NewRequest @{ Action = 'Align'; GUID = 'missing' })).StatusCode | Should -Be 404
        }
    }

    It 'refuses an action it does not know' {
        (Invoke-ExecManagedBaseline -Request (& $script:NewRequest @{ Action = 'Delete'; GUID = 'baseline-1' })).StatusCode | Should -Be 400
    }
}
