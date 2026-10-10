function Invoke-CIPPCAWhatIf {
    <#
    .SYNOPSIS
        Runs one or many Conditional Access What If evaluations, app-only, without signing in.
    .DESCRIPTION
        One body is a single POST to v1.0 identity/conditionalAccess/evaluate.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$TenantFilter,
        [Parameter(Mandatory = $true)]$Bodies
    )

    $Bodies = @($Bodies)
    $Results = [System.Collections.Generic.List[object]]::new()

    if ($Bodies.Count -eq 1) {
        try {
            $Json = ConvertTo-Json -Depth 20 -InputObject $Bodies[0]
            $Response = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/evaluate' -tenantid $TenantFilter -type POST -body $Json -AsApp $true
            $Policies = if ($null -ne $Response.value) { @($Response.value) } else { @($Response | Where-Object { $_.PSObject.Properties['policyApplies'] }) }
            $Results.Add([PSCustomObject]@{ Index = 0; Policies = @($Policies); Error = $null })
        } catch {
            $Results.Add([PSCustomObject]@{ Index = 0; Policies = @(); Error = $_.Exception.Message })
        }
        return @($Results)
    }

    $Requests = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Bodies.Count; $i++) {
        $Requests.Add([PSCustomObject]@{
                id      = "$i"
                method  = 'POST'
                url     = '/identity/conditionalAccess/evaluate'
                headers = @{ 'Content-Type' = 'application/json' }
                body    = $Bodies[$i]
            })
    }

    $Responses = @()
    $BatchError = $null
    try {
        $Responses = @(New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $true -Version 'v1.0')
    } catch {
        $BatchError = $_.Exception.Message
    }

    for ($i = 0; $i -lt $Bodies.Count; $i++) {
        $Response = $Responses | Where-Object { "$($_.id)" -eq "$i" } | Select-Object -First 1
        if ($null -eq $Response) {
            $Results.Add([PSCustomObject]@{ Index = $i; Policies = @(); Error = $(if ($BatchError) { $BatchError } else { 'No reply in the batch response.' }) })
            continue
        }
        if ([int]$Response.status -ge 400) {
            $Message = $Response.body.error.message
            $Results.Add([PSCustomObject]@{ Index = $i; Policies = @(); Error = $(if ($Message) { "$Message" } else { "HTTP $($Response.status)" }) })
            continue
        }
        $Results.Add([PSCustomObject]@{ Index = $i; Policies = @($Response.body.value | Where-Object { $_ }); Error = $null })
    }
    @($Results)
}
