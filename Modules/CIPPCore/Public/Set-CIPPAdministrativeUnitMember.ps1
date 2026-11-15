function Set-CIPPAdministrativeUnitMember {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Adds users, groups or devices to an administrative unit, or removes them, in one Graph batch.
    .DESCRIPTION
        Members are picker objects ({ value, label }), objects with an id and name, or bare object ids. Returns one
        @{ resultText; state } per member and logs each. Adding a group adds the group itself, not its members.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [Parameter(Mandatory)][string]$UnitId,
        [string]$UnitName,
        [Parameter(Mandatory)][ValidateSet('Add', 'Remove')][string]$Action,
        $Members,
        $Headers,
        $APIName = 'AdministrativeUnitMembers'
    )

    if (-not $UnitName) { $UnitName = $UnitId }
    $Targets = [System.Collections.Generic.List[object]]::new()
    $Requests = [System.Collections.Generic.List[object]]::new()
    foreach ($Member in @($Members)) {
        if (-not $Member) { continue }
        $MemberId = [string]($Member.value ?? $Member.id ?? $Member)
        $Targets.Add([PSCustomObject]@{ id = $MemberId; name = [string]($Member.label ?? $Member.name ?? $Member.displayName ?? $MemberId) })
        $Request = if ($Action -eq 'Add') {
            @{
                id      = "$($Targets.Count)"
                method  = 'POST'
                url     = "directory/administrativeUnits/$UnitId/members/`$ref"
                body    = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$MemberId" }
                headers = @{ 'Content-Type' = 'application/json' }
            }
        } else {
            @{
                id     = "$($Targets.Count)"
                method = 'DELETE'
                url    = "directory/administrativeUnits/$UnitId/members/$MemberId/`$ref"
            }
        }
        $Requests.Add($Request)
    }
    if ($Requests.Count -eq 0) { return @() }

    $Responses = @{}
    $BatchError = $null
    try {
        foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests) -Version 'v1.0')) {
            $Responses[[string]$Response.id] = $Response
        }
    } catch {
        $BatchError = (Get-CippException -Exception $_).NormalizedError
    }

    for ($Index = 0; $Index -lt $Targets.Count; $Index++) {
        $Target = $Targets[$Index]
        $Response = $Responses["$($Index + 1)"]
        $Failure = if ($BatchError) {
            $BatchError
        } elseif (-not $Response) {
            'Graph returned no result for this member'
        } elseif ([int]$Response.status -ge 300) {
            Get-NormalizedError -message (Get-CippExoErrorText -ErrorRecord $Response.body)
        }
        if ($Failure) {
            $Step = if ($Action -eq 'Add') { "add $($Target.name) to" } else { "remove $($Target.name) from" }
            $Message = "Failed to $Step administrative unit '$UnitName': $Failure"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error'
            @{ resultText = $Message; state = 'error' }
        } else {
            $Message = if ($Action -eq 'Add') { "Added $($Target.name) to administrative unit '$UnitName'" } else { "Removed $($Target.name) from administrative unit '$UnitName'" }
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
            @{ resultText = $Message; state = 'success' }
        }
    }
}
