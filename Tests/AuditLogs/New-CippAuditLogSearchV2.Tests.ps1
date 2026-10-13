BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AuditLogs/New-CippAuditLogSearchV2.ps1')

    function New-GraphPOSTRequest { param($uri, $body, $tenantid, $AsApp, $maxRetries) }

    function New-GraphError {
        param([string]$Body)
        $Exception = [System.Exception]::new('Graph error')
        $Exception.Data['RawErrorBody'] = $Body
        $Exception
    }
}

Describe 'New-CippAuditLogSearchV2 error classification' {
    BeforeEach {
        Mock Start-Sleep {}
    }

    It 'treats a missing audit permission as access denied without retrying' {
        $script:Body = '{"error":{"code":"Forbidden","message":"{\"Message\":\"App:0531415b-c6ed-45e1-bac8-882ed3cde711 dont have any permissions\"}"}}'
        Mock New-GraphPOSTRequest { throw (New-GraphError -Body $script:Body) }

        $Result = New-CippAuditLogSearchV2 -TenantFilter 'contoso.onmicrosoft.com' -StartTime (Get-Date).AddHours(-1) -EndTime (Get-Date)

        $Result.Outcome | Should -Be 'AccessDenied'
        $Result.Status | Should -Be 'MissingPermissions'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly
    }

    It 'still retries an unknown error as transient' {
        Mock New-GraphPOSTRequest { throw (New-GraphError -Body '{"error":{"code":"UnknownError","message":"oops"}}') }

        $Result = New-CippAuditLogSearchV2 -TenantFilter 'contoso.onmicrosoft.com' -StartTime (Get-Date).AddHours(-1) -EndTime (Get-Date)

        $Result.Outcome | Should -Be 'Transient'
        Should -Invoke New-GraphPOSTRequest -Times 3 -Exactly
    }
}
