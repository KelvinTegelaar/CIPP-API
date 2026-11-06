# A group that was removed from a relationship and mapped again has a deleted and an active access assignment.
# Graph rejects a batch with a repeated request id, so the member lookup must ask for each group once.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/GDAP/Invoke-ListGDAPAccessAssignments.ps1')

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphGetRequest { param($Uri, $tenantid, $asApp, $NoAuthCheck)
        if ($Uri -like '*accessAssignments*') { return $script:Assignments }
        @([pscustomobject]@{ id = 'g-reader'; displayName = 'M365 GDAP Global Reader' }, [pscustomobject]@{ id = 'g-exo'; displayName = 'M365 GDAP Exchange Administrator' })
    }
    function New-GraphBulkRequest { param($Requests, $tenantid, $asApp, $NoAuthCheck)
        $Ids = @($Requests.id)
        if (@($Ids | Select-Object -Unique).Count -ne $Ids.Count) { throw "Request Id $($Ids[0]) has to be unique in a batch." }
        foreach ($Id in $Ids) { [pscustomobject]@{ id = $Id; body = @{ value = @([pscustomobject]@{ id = "member-of-$Id" }) } } }
    }
}

Describe 'Invoke-ListGDAPAccessAssignments' {
    It 'lists a group that has both a deleted and an active assignment' {
        $script:Assignments = @(
            [pscustomobject]@{ id = 'a1'; status = 'deleted'; accessContainer = @{ accessContainerId = 'g-reader' }; accessDetails = @{ unifiedRoles = @() } }
            [pscustomobject]@{ id = 'a2'; status = 'active'; accessContainer = @{ accessContainerId = 'g-reader' }; accessDetails = @{ unifiedRoles = @() } }
            [pscustomobject]@{ id = 'a3'; status = 'active'; accessContainer = @{ accessContainerId = 'g-exo' }; accessDetails = @{ unifiedRoles = @() } }
        )
        $Response = Invoke-ListGDAPAccessAssignments -Request ([pscustomobject]@{ Query = @{ Id = 'rel-1' } }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -HaveCount 3
        @($Response.Body.Results.Where({ $_.id -eq 'a2' }))[0].members.id | Should -Be 'member-of-g-reader'
    }
}
