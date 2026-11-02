BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{ Context = @{ TableName = $TableName } } }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force, [string]$OperationType, [switch]$CreateTableIfNotExists) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property, $First) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function New-CIPPAzStorageRequest { param($Service, $Resource, $Method, $Body, $ContentType) throw 'blob storage must not be touched' }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Set-CIPPBecReport.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecReport.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Remove-CIPPBecReport.ps1')
}

Describe 'Set-CIPPBecReport' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add(@{ Table = $Context.TableName; Entity = $Entity; Force = $Force.IsPresent; OperationType = $OperationType }) }
    }

    It 'writes the results to their own BecResults row (replace) and records the size on the merged run row' {
        $Results = [pscustomobject]@{ CaseId = 'BEC-1'; NewRules = @([pscustomobject]@{ Name = 'r1' }) }
        $Entity = Set-CIPPBecReport -TenantFilter 'contoso.com' -CaseId 'BEC-1' -Properties @{ Status = 'Completed' } -Results $Results
        $ResultsWrite = $script:Writes | Where-Object { $_.Table -eq 'BecResults' }
        $ResultsWrite | Should -HaveCount 1
        $ResultsWrite.Force | Should -BeTrue -Because 'replace lets the large-entity writer clean up shrunken part rows'
        $ResultsWrite.Entity.PartitionKey | Should -Be 'contoso.com'
        $ResultsWrite.Entity.RowKey | Should -Be 'BEC-1'
        $ResultsWrite.Entity.Results | Should -Match '"NewRules"'
        $RowWrite = $script:Writes | Where-Object { $_.Table -eq 'BecReports' }
        $RowWrite | Should -HaveCount 1
        $RowWrite.OperationType | Should -Be 'UpsertMerge'
        $Entity.Keys | Should -Not -Contain 'ResultsBlob'
    }

    It 'replaces the run row without touching the results table when only properties are given' {
        Set-CIPPBecReport -TenantFilter 'contoso.com' -CaseId 'BEC-1' -Replace -Properties @{ Status = 'Waiting'; UserId = 'u1' } | Out-Null
        @($script:Writes | Where-Object { $_.Table -eq 'BecResults' }).Count | Should -Be 0
        ($script:Writes | Where-Object { $_.Table -eq 'BecReports' }).Force | Should -BeTrue
    }

    It 'stores structured properties as compact JSON' {
        $Entity = Set-CIPPBecReport -TenantFilter 'contoso.com' -CaseId 'BEC-1' -Properties @{ Containment = @([pscustomobject]@{ At = 'x'; Actions = @('ResetPassword') }) }
        $Entity.Containment | Should -BeOfType [string]
        $Entity.Containment | Should -Match '"Actions":\["ResetPassword"\]'
    }
}

Describe 'Get-CIPPBecReport' {
    BeforeEach {
        $script:RunRows = @(
            [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'BEC-20260801000000-aaaaaa'; UserId = 'u1'; Status = 'Completed'; Containment = '[{"At":"x","Actions":["ResetPassword"]}]'; EvidenceExports = '[{"At":"y","Sha256":"abc"}]'; ETag = 'e1' }
            [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'BEC-20260805000000-bbbbbb'; UserId = 'u2'; Status = 'Completed'; ETag = 'e2' }
            [pscustomobject]@{ PartitionKey = 'fabrikam.com'; RowKey = 'BEC-20260803000000-cccccc'; UserId = 'u3'; Status = 'Waiting'; ETag = 'e3' }
        )
        Mock Get-CIPPAzDataTableEntity {
            if ($Context.TableName -eq 'BecResults') {
                if ($Filter -like "*BEC-20260801000000-aaaaaa*") {
                    return [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'BEC-20260801000000-aaaaaa'; Results = '{"CaseId":"BEC-20260801000000-aaaaaa","NewRules":[{"Name":"r"}]}' }
                }
                return $null
            }
            $Rows = $script:RunRows
            if ($Filter -match "PartitionKey eq '([^']+)'") { $Rows = $Rows | Where-Object { $_.PartitionKey -eq $Matches[1] } }
            if ($Filter -match "RowKey eq '([^']+)'") { $Rows = $Rows | Where-Object { $_.RowKey -eq $Matches[1] } }
            if ($Filter -match "UserId eq '([^']+)'") { $Rows = $Rows | Where-Object { $_.UserId -eq $Matches[1] } }
            $Rows
        }
    }

    It 'lists a tenant newest first with CaseId/Tenant aliases and parsed Containment' {
        $Rows = @(Get-CIPPBecReport -TenantFilter 'contoso.com')
        $Rows.Count | Should -Be 2
        $Rows[0].CaseId | Should -Be 'BEC-20260805000000-bbbbbb'
        $Rows[1].Tenant | Should -Be 'contoso.com'
        $Rows[1].Containment[0].Actions | Should -Be @('ResetPassword')
        # ConvertFrom-Json unrolls a JSON array; a one-entry history must still be a list for the case page
        $Rows[1].Containment -is [array] | Should -BeTrue
        @($Rows[1].Containment).Count | Should -Be 1
    }

    It 'narrows to one user and scans every tenant for AllTenants' {
        @(Get-CIPPBecReport -TenantFilter 'contoso.com' -UserId 'u1').Count | Should -Be 1
        @(Get-CIPPBecReport -TenantFilter 'AllTenants').Count | Should -Be 3
    }

    It 'fetches and parses the results row from the BecResults table for a single run when asked' {
        $Run = Get-CIPPBecReport -TenantFilter 'contoso.com' -CaseId 'BEC-20260801000000-aaaaaa' -IncludeResults
        $Run.Results.NewRules[0].Name | Should -Be 'r'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Context.TableName -eq 'BecResults' }
    }

    It 'throws when a completed run has no results row rather than returning a run without data' {
        { Get-CIPPBecReport -TenantFilter 'contoso.com' -CaseId 'BEC-20260805000000-bbbbbb' -IncludeResults } | Should -Throw '*not found in the BecResults table*'
    }

    It 'attaches nothing for a run that has not completed - polling a queued or running run is not an error' {
        $Run = Get-CIPPBecReport -TenantFilter 'fabrikam.com' -CaseId 'BEC-20260803000000-cccccc' -IncludeResults
        $Run.Status | Should -Be 'Waiting'
        $Run.PSObject.Properties['Results'] | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -ParameterFilter { $Context.TableName -eq 'BecResults' }
    }
}

Describe 'Remove-CIPPBecReport' {
    BeforeEach {
        $script:Removed = [System.Collections.Generic.List[object]]::new()
        Mock Remove-CIPPAzDataTableEntity { $script:Removed.Add(@{ Table = $Context.TableName; Entity = $Entity }) }
    }

    It 'removes the BecResults row first, then the run row, through the part-aware remover' {
        Mock Get-CIPPAzDataTableEntity {
            if ($Context.TableName -eq 'BecResults') { return [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'BEC-1'; Results = '{}'; ETag = 'r1' } }
            [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'BEC-1'; Status = 'Completed'; ETag = 'e1' }
        }
        Remove-CIPPBecReport -TenantFilter 'contoso.com' -CaseId 'BEC-1' | Should -Match 'Deleted BEC run BEC-1'
        $script:Removed.Count | Should -Be 2
        $script:Removed[0].Table | Should -Be 'BecResults'
        $script:Removed[1].Table | Should -Be 'BecReports'
        $script:Removed[1].Entity.RowKey | Should -Be 'BEC-1'
    }

    It 'tolerates a run that never stored results and refuses one that does not exist' {
        Mock Get-CIPPAzDataTableEntity {
            if ($Context.TableName -eq 'BecResults') { return $null }
            [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'BEC-1'; Status = 'Error'; ETag = 'e1' }
        }
        $null = Remove-CIPPBecReport -TenantFilter 'contoso.com' -CaseId 'BEC-1'
        $script:Removed.Count | Should -Be 1
        $script:Removed[0].Table | Should -Be 'BecReports'
        Mock Get-CIPPAzDataTableEntity { $null }
        { Remove-CIPPBecReport -TenantFilter 'contoso.com' -CaseId 'BEC-x' } | Should -Throw '*was not found*'
    }
}
