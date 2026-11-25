BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPDefenderIndicator { param($TenantFilter, $PageSize) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type, $scope, $AsApp, $maxRetries) }
    function Write-LogMessage { param($headers, $API, $tenant, $tenantId, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Add-CIPPDefenderIndicator.ps1' -File | Select-Object -First 1 -ExpandProperty FullName)

    $script:Sha256 = 'a3f5' * 16
    $script:Other = 'd' * 64
    $script:Headers = @{ 'x-ms-client-principal' = 'principal' }
    function Invoke-Add ([string[]]$Values = @($script:Sha256), [hashtable]$Template = @{ indicatorType = 'FileSha256'; action = 'Block'; title = 'Known bad'; description = 'tech@msp.example via CIPP' }, [string]$QueueId) {
        Add-CIPPDefenderIndicator -TenantFilter 'a.com' -TenantId 'id-a' -Values $Values -Template $Template -Headers $script:Headers -APIName 'AddDefenderIndicator' -QueueId $QueueId
    }
}

Describe 'Add-CIPPDefenderIndicator' {
    BeforeEach {
        $script:Posts = [System.Collections.Generic.List[object]]::new()
        $script:Existing = @()
        $script:NextId = 100
        $script:Logs = [System.Collections.Generic.List[object]]::new()
        Mock Write-LogMessage { $script:Logs.Add([pscustomobject]@{ Headers = $headers; Tenant = $tenant; TenantId = $tenantId; Message = $message; Sev = $sev; LogData = $LogData }) }
        Mock Get-CIPPDefenderIndicator { $script:Existing }
        Mock New-GraphPOSTRequest {
            $script:Posts.Add([pscustomobject]@{ Tenant = $tenantid; Body = $body })
            [pscustomobject]@{ value = @(foreach ($Item in ($body | ConvertFrom-Json).Indicators) { [pscustomobject]@{ id = "$(($script:NextId++))"; indicator = $Item.indicatorValue; isFailed = $false; failureReason = $null } }) }
        }
    }

    It 'adds every value, logs Info with the tenant id, and counts nothing as failed' {
        $Outcome = Invoke-Add -Values @($script:Sha256, $script:Other)
        $Outcome.Failed | Should -Be 0
        $Outcome.Conflicts | Should -Be 0
        @($Outcome.Results.state) | Should -Be @('success', 'success')
        $script:Logs | Should -HaveCount 1
        $script:Logs[0].Sev | Should -Be 'Info'
        $script:Logs[0].Tenant | Should -Be 'a.com'
        $script:Logs[0].TenantId | Should -Be 'id-a'
        $script:Logs[0].Message | Should -BeExactly 'Added or updated 2 Block FileSha256 indicators (ids 100, 101), 0 failed or unconfirmed'
        $script:Logs[0].LogData | Should -BeNullOrEmpty
    }

    It 'names the queue in the log line and stores the results for queued work' {
        $Outcome = Invoke-Add -QueueId 'queue-1'
        $script:Logs[0].Message | Should -BeLike '* (queue queue-1)'
        $script:Logs[0].LogData.QueueId | Should -Be 'queue-1'
        @($script:Logs[0].LogData.Results) | Should -HaveCount 1
        $script:Logs[0].LogData.Results[0].resultText | Should -Be $Outcome.Results[0].resultText
        $script:Logs[0].Headers['x-ms-client-principal'] | Should -Be 'principal'
    }

    It 'writes nothing and fails every value when the existing indicators cannot be read, <Mode>' -ForEach @(
        @{ Mode = 'inline'; QueueId = $null }
        @{ Mode = 'queued'; QueueId = 'queue-1' }
    ) {
        Mock Get-CIPPDefenderIndicator { throw 'Service unavailable' }
        $Outcome = Invoke-Add -Values @($script:Sha256, $script:Other) -QueueId $QueueId
        $Outcome.Failed | Should -Be 2
        @($Outcome.Results) | Should -HaveCount 1
        $Outcome.Results[0].state | Should -Be 'error'
        $Outcome.Results[0].resultText | Should -BeLike 'Nothing was added in a.com*Service unavailable*'
        $script:Posts | Should -HaveCount 0
        $script:Logs[0].Sev | Should -Be 'Error'
        if ($QueueId) { $script:Logs[0].LogData.Results[0].state | Should -Be 'error' } else { $script:Logs[0].LogData.NormalizedError | Should -Be 'Service unavailable' }
    }

    It 'fails every value it tried to import when the import call fails' {
        $script:Existing = @(@{ id = '7'; indicatorValue = $script:Sha256; indicatorType = 'FileSha256'; action = 'Allowed' })
        Mock New-GraphPOSTRequest { throw 'Forbidden' }
        $Outcome = Invoke-Add -Values @($script:Sha256, $script:Other) -QueueId 'queue-1'
        $Outcome.Failed | Should -Be 2
        $Outcome.Conflicts | Should -Be 1
        @($Outcome.Results.state) | Should -Be @('warning', 'error')
        $Outcome.Results[1].resultText | Should -BeLike 'Failed to add 1 indicators in a.com*Forbidden*'
        $script:Logs[0].Sev | Should -Be 'Error'
        @($script:Logs[0].LogData.Results) | Should -HaveCount 2
    }

    It 'logs a Warning that counts skipped values when some values conflict' {
        $script:Existing = @(@{ id = '7'; indicatorValue = $script:Sha256.ToUpperInvariant(); indicatorType = 'FileSha256'; action = 'Allowed' })
        $Outcome = Invoke-Add -Values @($script:Sha256, $script:Other)
        $Outcome.Failed | Should -Be 1
        $Outcome.Conflicts | Should -Be 1
        $script:Posts | Should -HaveCount 1
        $script:Logs[0].Sev | Should -Be 'Warning'
        $script:Logs[0].Message | Should -BeLike '*0 failed or unconfirmed, 1 skipped*'
    }

    It 'logs a Warning and imports nothing when every value conflicts' {
        $script:Existing = @(@{ id = '7'; indicatorValue = $script:Sha256; indicatorType = 'FileSha256'; action = 'Block'; rbacGroupIds = @(4) })
        $Outcome = Invoke-Add -QueueId 'queue-1'
        $Outcome.Failed | Should -Be 1
        $Outcome.Conflicts | Should -Be 1
        $script:Posts | Should -HaveCount 0
        $script:Logs[0].Sev | Should -Be 'Warning'
        $script:Logs[0].Message | Should -BeLike 'Added no Block FileSha256 indicators*(queue queue-1)'
        $script:Logs[0].LogData.Results[0].resultText | Should -BeLike '*specific device groups*'
    }

    It 'matches the reply to each value without regard to case, and escapes percent signs in the request' {
        Mock New-GraphPOSTRequest {
            $script:Posts.Add([pscustomobject]@{ Tenant = $tenantid; Body = $body })
            [pscustomobject]@{ value = @([pscustomobject]@{ id = '9'; indicator = 'HTTPS://BAD.EXAMPLE/A%2F'; isFailed = $false }) }
        }
        $Outcome = Invoke-Add -Values @('https://bad.example/a%2f') -Template @{ indicatorType = 'Url'; action = 'Block'; title = 'Known bad'; description = 'x' }
        $Outcome.Failed | Should -Be 0
        $Outcome.Results[0].id | Should -Be '9'
        $script:Posts[0].Body | Should -Not -Match '%'
        ($script:Posts[0].Body | ConvertFrom-Json).Indicators[0].indicatorValue | Should -BeExactly 'https://bad.example/a%2f'
    }

    It 'counts a refused value and an unconfirmed value as failed' {
        Mock New-GraphPOSTRequest {
            [pscustomobject]@{ value = @(
                    [pscustomobject]@{ id = $null; indicator = $script:Sha256; isFailed = $true; failureReason = 'Indicator value is not valid' }
                ) }
        }
        $Outcome = Invoke-Add -Values @($script:Sha256, $script:Other)
        $Outcome.Failed | Should -Be 2
        $Outcome.Results[0].resultText | Should -BeLike 'Defender refused*Indicator value is not valid'
        $Outcome.Results[1].resultText | Should -BeLike 'Defender did not confirm*'
        $script:Logs[0].Sev | Should -Be 'Warning'
    }
}
