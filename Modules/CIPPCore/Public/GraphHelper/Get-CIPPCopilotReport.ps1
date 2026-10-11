function Get-CIPPCopilotReport {
    <#
    .SYNOPSIS
        Reads a Microsoft 365 Copilot usage report, falling back between the D28 and D30 periods.
    .DESCRIPTION
        Copilot reports v2 accept D28 (RL28) and reject D30 as RL30; tenants still on v1 want D30. The period Graph
        rejects is retried once with the other one.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        # The report URI with {0} where the period goes
        [Parameter(Mandatory)][string]$UriTemplate,
        [Parameter(Mandatory)][string]$TenantFilter,
        [string]$Period = 'D28',
        [bool]$AsApp = $false,
        [switch]$Stream
    )

    try {
        New-GraphGetRequest -uri ($UriTemplate -f $Period) -tenantid $TenantFilter -AsApp $AsApp -Stream:$Stream
    } catch {
        $Alternate = switch ($Period) { 'D28' { 'D30' } 'D30' { 'D28' } default { $null } }
        if (-not $Alternate -or "$($_.Exception.Message)" -notmatch "period value 'RL(30|28)' is not supported|Use 'RL(28|30)' instead") { throw }
        Write-Information "Copilot report period '$Period' rejected for $TenantFilter; retrying with '$Alternate'."
        New-GraphGetRequest -uri ($UriTemplate -f $Alternate) -tenantid $TenantFilter -AsApp $AsApp -Stream:$Stream
    }
}
